import MouseCore

/// `MouseBar --demo`: a simulated Prime Mini Wireless dongle at 50% battery, for UI work without hardware.
enum DemoTransport {
    static func make() -> SimulatedHIDTransport {
        let transport = SimulatedHIDTransport()
        let connection = SimulatedHIDConnection(replyProvider: { payload in
            guard let command = payload.first, command == 0xD2 else { return nil }
            return [command, 0x0B] + [UInt8](repeating: 0, count: 62)   // byte 0 echoes the command, like the real mouse
        })
        transport.plug(
            HIDDeviceInfo(id: 1, vendorID: 0x1038, productID: 0x1848, interfaceNumber: 3, product: "Demo Prime Mini Wireless"),
            connection: connection
        )
        return transport
    }
}
