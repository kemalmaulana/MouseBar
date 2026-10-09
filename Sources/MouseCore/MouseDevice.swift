/// One connected mouse. Actors are re-entrant, so every public command runs under a FIFO lock:
/// commands never overlap, and each keeps the 50 ms spacing rivalcfg uses. A battery query holds
/// the lock from flush to reply, so no other command can steal or flush its answer.
public actor MouseDevice {
    public static let commandDelay: Duration = .milliseconds(50)
    public static let replyTimeout: Duration = .milliseconds(200)

    public let family: DeviceFamily
    public let model: DeviceModel
    private let connection: any HIDConnection
    private let encoder: SettingEncoder
    private let sleeper: any Sleeper
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        family: DeviceFamily,
        model: DeviceModel,
        connection: any HIDConnection,
        encoder: SettingEncoder,
        sleeper: any Sleeper
    ) {
        self.family = family
        self.model = model
        self.connection = connection
        self.encoder = encoder
        self.sleeper = sleeper
    }

    /// Encodes and sends one setting. Encoding errors are thrown before anything is written.
    public func apply(_ key: String, _ value: SettingValue) async throws {
        try await exclusive {
            guard let spec = family.setting(key) else { throw MouseCoreError.unknownSetting(key) }
            let payload = try encoder.encode(spec, value: value)
            try await send(payload, readback: spec.readbackLength)
        }
    }

    /// Persists the current configuration in the mouse's internal memory.
    public func save() async throws {
        try await exclusive {
            guard let save = family.saveCommand else { return }
            try await send(Bytes.u8(save.command), readback: save.readbackLength)
        }
    }

    /// `nil` means no usable answer (asleep, out of range, garbage); callers must not show 0%.
    public func readBattery() async throws -> BatteryReading? {
        try await exclusive {
            guard let battery = family.battery else { return nil }
            await connection.flushInput()
            try await send(Bytes.u8(battery.command), readback: 0)
            guard let reply = try await connection.read(
                length: max(battery.responseLength, 2), timeout: Self.replyTimeout
            ) else { return nil }
            return BatteryDecoder.decode(decoder: battery.decoder, reply: reply)
        }
    }

    public func close() async {
        await connection.close()
    }

    /// FIFO async mutex. Ownership is handed straight to the next waiter on release, so the busy
    /// flag stays set while anyone is queued and callers run in arrival order.
    private func exclusive<T>(_ body: () async throws -> T) async rethrows -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        defer {
            if waiters.isEmpty {
                isBusy = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        return try await body()
    }

    /// Callers must hold `exclusive`.
    private func send(_ payload: [UInt8], readback: Int) async throws {
        do {
            try await connection.write(payload)
        } catch {
            await sleeper.sleep(for: Self.commandDelay)
            try await connection.write(payload)
        }
        await sleeper.sleep(for: Self.commandDelay)
        if readback > 0 {
            _ = try? await connection.read(length: readback, timeout: Self.replyTimeout)
        }
    }
}
