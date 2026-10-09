import MouseCore

/// `MouseBar --demo`: a simulated Prime Mini Wireless dongle at 50% battery, for UI work without hardware.
enum DemoTransport {
    static func make() -> SimulatedHIDTransport {
        let transport = SimulatedHIDTransport()
        let connection = SimulatedHIDConnection(replyProvider: { payload in
            guard payload.first == 0xD2 else { return nil }
            return [0x00, 0x0B] + [UInt8](repeating: 0, count: 62)
        })
        transport.plug(
            HIDDeviceInfo(id: 1, vendorID: 0x1038, productID: 0x1848, interfaceNumber: 3, product: "Demo Prime Mini Wireless"),
            connection: connection
        )
        return transport
    }
}
