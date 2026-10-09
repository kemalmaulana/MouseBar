import Foundation
import IOKit
import IOKit.hid
import MouseCore

/// One opened HID interface. All mutable state is touched only on `queue`.
final class IOHIDConnection: HIDConnection, @unchecked Sendable {
    private struct Waiter {
        let token: UUID
        let length: Int
        let continuation: CheckedContinuation<[UInt8]?, Never>
    }

    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "mousebar.hid.connection")
    private var pending: [[UInt8]] = []
    private var waiter: Waiter?
    private let bufferSize: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    private var closed = false

    init(device: IOHIDDevice) {
        self.device = device
        let reported = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int
        bufferSize = max(reported ?? 64, 64)
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    func start() {
        let retained = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let connection = Unmanaged<IOHIDConnection>.fromOpaque(context).takeUnretainedValue()
            connection.received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, retained)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceSetCancelHandler(device) {
            Unmanaged<IOHIDConnection>.fromOpaque(retained).release()
        }
        IOHIDDeviceActivate(device)
    }

    private func received(_ report: [UInt8]) {
        // Runs on `queue`.
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: Array(report.prefix(waiter.length)))
        } else {
            pending.append(report)
            if pending.count > 64 { pending.removeFirst() }
        }
    }

    func write(_ payload: [UInt8]) async throws {
        guard !payload.isEmpty else { return }
        let result: IOReturn = await withCheckedContinuation { continuation in
            queue.async {
                guard !self.closed else {
                    continuation.resume(returning: kIOReturnNotOpen)
                    return
                }
                let status = payload.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(self.device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
                }
                continuation.resume(returning: status)
            }
        }
        guard result == kIOReturnSuccess else { throw HIDError.writeFailed(code: result) }
    }

    func read(length: Int, timeout: Duration) async throws -> [UInt8]? {
        let milliseconds = Int(timeout.components.seconds * 1000) + Int(timeout.components.attoseconds / 1_000_000_000_000_000)
        return await withCheckedContinuation { continuation in
            queue.async {
                if !self.pending.isEmpty {
                    continuation.resume(returning: Array(self.pending.removeFirst().prefix(length)))
                    return
                }
                let token = UUID()
                self.waiter = Waiter(token: token, length: length, continuation: continuation)
                self.queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    if let waiter = self.waiter, waiter.token == token {
                        self.waiter = nil
                        waiter.continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    func flushInput() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.pending.removeAll()
                continuation.resume()
            }
        }
    }

    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard !self.closed else {
                    continuation.resume()
                    return
                }
                self.closed = true
                if let waiter = self.waiter {
                    self.waiter = nil
                    waiter.continuation.resume(returning: nil)
                }
                IOHIDDeviceCancel(self.device)
                IOHIDDeviceClose(self.device, IOOptionBits(kIOHIDOptionsTypeNone))
                continuation.resume()
            }
        }
    }
}
