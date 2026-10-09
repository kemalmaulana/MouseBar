import Foundation
import IOKit
import IOKit.hid
import MouseCore
import os

public final class IOHIDTransport: HIDTransport, @unchecked Sendable {
    private let vendorID: Int
    private let queue = DispatchQueue(label: "mousebar.hid.manager")
    private let devices = OSAllocatedUnfairLock<[UInt64: IOHIDDevice]>(initialState: [:])

    public init(vendorID: Int = 0x1038) {
        self.vendorID = vendorID
    }

    public func events() -> AsyncStream<HIDEvent> {
        AsyncStream { continuation in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
            let context = CallbackContext(transport: self, continuation: continuation)
            let retained = Unmanaged.passRetained(context).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
                guard let ctx else { return }
                Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue().deviceAdded(device)
            }, retained)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
                guard let ctx else { return }
                Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
            }, retained)
            IOHIDManagerSetDispatchQueue(manager, queue)
            IOHIDManagerSetCancelHandler(manager) {
                Unmanaged<CallbackContext>.fromOpaque(retained).release()
            }
            IOHIDManagerActivate(manager)
            continuation.onTermination = { _ in IOHIDManagerCancel(manager) }
        }
    }

    public func open(_ info: HIDDeviceInfo) async throws -> any HIDConnection {
        guard let managerDevice = devices.withLock({ $0[info.id] }) else { throw HIDError.notOpen }
        // The manager's device object is for enumeration only. Each connection gets a private
        // IOHIDDevice for the same service (as hidapi's hid_open_path does), so its queue,
        // activation and cancellation never touch the shared object, and a later open starts fresh.
        let service = IOHIDDeviceGetService(managerDevice)
        guard service != MACH_PORT_NULL,
              let device = IOHIDDeviceCreate(kCFAllocatorDefault, service)
        else { throw HIDError.openFailed(code: kIOReturnNotFound) }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.openFailed(code: result) }
        let connection = IOHIDConnection(device: device)
        connection.start()
        return connection
    }

    fileprivate func remember(_ device: IOHIDDevice, id: UInt64) {
        devices.withLock { $0[id] = device }
    }

    fileprivate func forget(id: UInt64) {
        _ = devices.withLock { $0.removeValue(forKey: id) }
    }
}

private final class CallbackContext: @unchecked Sendable {
    let transport: IOHIDTransport
    let continuation: AsyncStream<HIDEvent>.Continuation

    init(transport: IOHIDTransport, continuation: AsyncStream<HIDEvent>.Continuation) {
        self.transport = transport
        self.continuation = continuation
    }

    func deviceAdded(_ device: IOHIDDevice) {
        guard let id = registryID(device) else { return }
        transport.remember(device, id: id)
        continuation.yield(.added(HIDDeviceInfo(
            id: id,
            vendorID: intProperty(device, kIOHIDVendorIDKey) ?? 0,
            productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
            interfaceNumber: interfaceNumber(device),
            usagePage: intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            usage: intProperty(device, kIOHIDPrimaryUsageKey) ?? 0,
            product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        )))
    }

    func deviceRemoved(_ device: IOHIDDevice) {
        guard let id = registryID(device) else { return }
        transport.forget(id: id)
        continuation.yield(.removed(id))
    }
}

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int
}

private func registryID(_ device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    guard service != MACH_PORT_NULL else { return nil }
    var id: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return nil }
    return id
}

/// The USB interface number (rivalcfg's "endpoint"). Looked up on the HID device first, then on its
/// registry ancestors; the spike (Step 5) records which one answers on this macOS version.
private func interfaceNumber(_ device: IOHIDDevice) -> Int? {
    if let direct = intProperty(device, "bInterfaceNumber") { return direct }
    var entry = IOHIDDeviceGetService(device)
    guard entry != MACH_PORT_NULL else { return nil }
    IOObjectRetain(entry)
    defer { IOObjectRelease(entry) }
    for _ in 0..<6 {
        if let value = IORegistryEntryCreateCFProperty(
            entry, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int {
            return value
        }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        IOObjectRelease(entry)
        entry = parent
    }
    return nil
}
