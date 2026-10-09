import Foundation
import MouseCore
import MouseHID

// hidprobe list            print every SteelSeries HID interface macOS shows for 3 seconds
// hidprobe battery         query the battery of the first supported mouse and print the raw reply
// hidprobe dpi <index>     send the default 5 presets with <index> selected (tests preset switching)

func describe(_ info: HIDDeviceInfo) -> String {
    String(format: "id=%llu vid=%04x pid=%04x iface=%@ usagePage=%04x usage=%04x product=%@",
           info.id, info.vendorID, info.productID,
           info.interfaceNumber.map(String.init) ?? "nil",
           info.usagePage, info.usage, info.product ?? "nil")
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "list"
let transport = IOHIDTransport()
let catalog = try ProfileCatalog.load()

/// First supported interface that shows up within 3 seconds.
func findMouse() async -> (info: HIDDeviceInfo, match: MatchedProfile)? {
    await withTaskGroup(of: (HIDDeviceInfo, MatchedProfile)?.self) { group in
        group.addTask {
            for await event in transport.events() {
                if case .added(let info) = event,
                   let match = catalog.match(vendorID: info.vendorID, productID: info.productID),
                   info.interfaceNumber == match.model.endpoint {
                    return (info, match)
                }
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first.map { (info: $0.0, match: $0.1) }
    }
}

switch command {
case "list":
    let task = Task {
        for await event in transport.events() {
            switch event {
            case .added(let info): print("ADDED   \(describe(info))")
            case .removed(let id): print("REMOVED id=\(id)")
            }
        }
    }
    try await Task.sleep(for: .seconds(3))
    task.cancel()

case "battery":
    guard let (info, match) = await findMouse() else {
        print("No supported mouse with the expected interface found. Run `hidprobe list` and compare.")
        exit(1)
    }
    print("using \(match.model.name)  [\(describe(info))]")
    let connection = try await transport.open(info)
    guard let battery = match.family.battery else { exit(2) }
    await connection.flushInput()
    try await connection.write(battery.command.map { UInt8($0) })
    try await Task.sleep(for: .milliseconds(50))
    if let reply = try await connection.read(length: 64, timeout: .milliseconds(200)) {
        print("raw reply: \(hexString(reply))")
        if let reading = BatteryDecoder.decode(decoder: battery.decoder, reply: reply) {
            print("battery: \(reading.level)%\(reading.isCharging ? " (charging)" : "")")
        } else {
            print("reply is not a valid battery reading")
        }
    } else {
        print("no reply within 200 ms (is the mouse awake?)")
    }
    await connection.close()

case "dpi":
    guard arguments.count > 1, let index = Int(arguments[1]) else { print("usage: hidprobe dpi <0-4>"); exit(64) }
    guard let (info, match) = await findMouse() else { print("No supported mouse found."); exit(1) }
    let connection = try await transport.open(info)
    let device = MouseDevice(
        family: match.family, model: match.model, connection: connection,
        encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: SystemSleeper()
    )
    try await device.apply(
        "sensitivity",
        .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: index)
    )
    print("sent presets 400/800/1200/2400/3200 with preset \(index) selected (no save). Move the mouse and judge the speed.")
    await device.close()

default:
    print("usage: hidprobe list | battery | dpi <index>")
    exit(64)
}
