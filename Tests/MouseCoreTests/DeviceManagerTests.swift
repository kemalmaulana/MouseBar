import Testing
@testable import MouseCore

@Suite struct DeviceManagerTests {
    func makeManager(_ transport: SimulatedHIDTransport) throws -> DeviceManager {
        DeviceManager(
            transport: transport,
            catalog: try ProfileCatalog.load(),
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()),
            sleeper: RecordingSleeper()
        )
    }

    func info(id: UInt64, pid: Int, iface: Int?) -> HIDDeviceInfo {
        HIDDeviceInfo(id: id, vendorID: 0x1038, productID: pid, interfaceNumber: iface)
    }

    @Test(.timeLimit(.minutes(1)))
    func dongleInterfaceThreeBecomesAConnectedMouse() async throws {
        let transport = SimulatedHIDTransport()
        transport.plug(info(id: 1, pid: 0x1848, iface: 3), connection: SimulatedHIDConnection())
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .connected(let mouse)? = await events.next() else { Issue.record("expected connected"); return }
        #expect(mouse.hidID == 1)
        #expect(mouse.family.id == "prime_wireless_wireless")
        #expect(mouse.model.mouse == "prime_mini_wireless")
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func otherInterfacesAndUnknownProductsAreIgnored() async throws {
        let transport = SimulatedHIDTransport()
        transport.plug(info(id: 1, pid: 0x1848, iface: 0), connection: SimulatedHIDConnection())   // wrong interface
        transport.plug(info(id: 2, pid: 0x1848, iface: nil), connection: SimulatedHIDConnection()) // unknown interface
        transport.plug(info(id: 3, pid: 0xFFFF, iface: 3), connection: SimulatedHIDConnection())   // unknown product
        transport.plug(info(id: 4, pid: 0x184A, iface: 3), connection: SimulatedHIDConnection())   // the one that counts
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .connected(let mouse)? = await events.next() else { Issue.record("expected connected"); return }
        #expect(mouse.hidID == 4)
        #expect(mouse.family.id == "prime_wireless_wired")
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func unplugEmitsDisconnectedAndClosesTheConnection() async throws {
        let transport = SimulatedHIDTransport()
        let connection = SimulatedHIDConnection()
        transport.plug(info(id: 7, pid: 0x1848, iface: 3), connection: connection)
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        _ = await events.next()
        transport.unplug(id: 7)
        guard case .disconnected(let id)? = await events.next() else { Issue.record("expected disconnected"); return }
        #expect(id == 7)
        #expect(await connection.isClosed)
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func openFailureIsReportedNotSwallowed() async throws {
        let transport = SimulatedHIDTransport()
        transport.setOpenFails(true)
        transport.plug(info(id: 9, pid: 0x1848, iface: 3), connection: SimulatedHIDConnection())
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .openFailed(let failed, _)? = await events.next() else { Issue.record("expected openFailed"); return }
        #expect(failed.id == 9)
        await manager.stop()
    }

    @Test func wiredBeatsDongleWhenBothArePresent() async throws {
        let catalog = try ProfileCatalog.load()
        func mouse(_ id: UInt64, _ pid: Int) throws -> ConnectedMouse {
            let match = try #require(catalog.match(vendorID: 0x1038, productID: pid))
            let device = MouseDevice(
                family: match.family, model: match.model, connection: SimulatedHIDConnection(),
                encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
            )
            return ConnectedMouse(hidID: id, family: match.family, model: match.model, device: device)
        }
        let dongle = try mouse(1, 0x1848)
        let cable = try mouse(2, 0x184A)
        #expect(ActiveMousePolicy.choose(from: []) == nil)
        #expect(ActiveMousePolicy.choose(from: [dongle])?.hidID == 1)
        #expect(ActiveMousePolicy.choose(from: [dongle, cable])?.hidID == 2)
        #expect(ActiveMousePolicy.choose(from: [cable, dongle])?.hidID == 2)
        #expect(ActiveMousePolicy.choose(from: [cable])?.hidID == 2)
        // Cable pulled out: the caller passes only the dongle, and the dongle is chosen again.
        #expect(ActiveMousePolicy.choose(from: [dongle])?.hidID == 1)
    }
}
