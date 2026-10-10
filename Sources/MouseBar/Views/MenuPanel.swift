import SwiftUI
import MouseCore

/// The menu bar dropdown: mouse and connection, battery gauge, quick controls, banners, save feedback, actions.
struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showColors = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let family = model.family {
                header
                battery
                Divider()
                quickControls(family)
                    .disabled(model.isCheckRunning)
            } else {
                emptyState
            }
            banners
            SaveStatusLine(state: model.saveState)
            Divider()
            footer
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "computermouse.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.displayName ?? "Mouse")
                .font(.headline)
            Spacer()
            if let connection = model.connection {
                Label(connection.title, systemImage: connection.symbol)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Connected by \(connection.title)")
            }
        }
    }

    private var battery: some View {
        let state = model.battery
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Gauge(value: Double(state.level ?? 0), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(Theme.batteryColor(level: state.level))
                    .themedAnimation(state.level, reduceMotion: reduceMotion)
                Text(state.level.map { "\($0)%" } ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: Theme.Space.xs) {
                    if state.isCharging == true {
                        Image(systemName: Theme.Symbol.charging).accessibilityHidden(true)
                    } else if state.freshness == .asleep {
                        Image(systemName: Theme.Symbol.asleep).accessibilityHidden(true)
                    }
                    Text(Self.statusLine(state, now: context.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery: \(BatteryPresentation.detail(for: state, now: Date()))")
    }

    @ViewBuilder private func quickControls(_ family: DeviceFamily) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if model.activePresetConfirmed, family.setting("sensitivity") != nil,
               case .dpiPresets(let presets, let selected)? = model.values["sensitivity"] {
                LabeledContent("DPI") {
                    Picker("DPI", selection: Binding(
                        get: { selected ?? 0 },
                        set: { model.submit("sensitivity", .dpiPresets(presets: presets, selected: $0)) }
                    )) {
                        ForEach(presets.indices, id: \.self) { index in
                            Text("\(presets[index])").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let spec = family.setting("polling_rate") {
                LabeledContent("Polling") {
                    Picker("Polling rate", selection: Binding(
                        get: {
                            if case .choice(let c)? = model.values[spec.key] ?? DefaultSettings.value(for: spec) { return c }
                            return spec.defaultText
                        },
                        set: { model.submit(spec.key, .choice($0)) }
                    )) {
                        ForEach(spec.choices ?? [], id: \.key) { choice in
                            Text(choice.key).tag(choice.key)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let spec = family.setting("color") {
                LabeledContent("LED") {
                    let current: MouseCore.RGBColor? = {
                        if case .color(let c)? = model.values[spec.key] { return c }
                        return nil
                    }()
                    Button {
                        showColors.toggle()
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Circle()
                                .fill(current?.swiftUIColor ?? .clear)
                                .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
                                .frame(width: 16, height: 16)
                            Text(current.map { "#" + $0.hexString.uppercased() } ?? "Not set")
                                .font(.callout)
                                .monospaced()
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("LED color \(current.map { "#" + $0.hexString.uppercased() } ?? "not set")")
                    .popover(isPresented: $showColors, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            LEDSwatches(selected: current) { model.submit(spec.key, .color($0)) }
                            ColorPicker("Custom color", selection: Binding(
                                get: { current?.swiftUIColor ?? .red },
                                set: { if let rgb = MouseCore.RGBColor(color: $0) { model.submit(spec.key, .color(rgb)) } }
                            ), supportsOpacity: false)
                        }
                        .padding(Theme.Space.m)
                    }
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if model.ggWarning {
            StatusBanner(
                style: .warning,
                message: "SteelSeries GG is running and can interfere. Quit it, or uninstall it with “SteelSeries GG Uninstaller”."
            )
        }
        if let problem = model.problem {
            StatusBanner(style: .error, message: problem, onDismiss: { model.problem = nil })
        }
        if let notice = model.notice {
            StatusBanner(style: .info, message: notice, onDismiss: { model.notice = nil })
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: Theme.Symbol.mouse)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Connect your mouse")
                .font(.headline)
            Text("Plug in the USB cable or the 2.4 GHz dongle.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Button("Hardware Check…") {
                    openWindow(id: "hardware-check")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
            }
            Button("Quit MouseBar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Text

    /// "Charging · read just now", "Low · read 3 min ago", "Asleep · last 80%", "Reading battery…".
    static func statusLine(_ state: BatteryState, now: Date) -> String {
        switch state.freshness {
        case .disconnected:
            return "No mouse connected"
        case .asleep:
            return state.level.map { "Asleep · last \($0)%" } ?? "Asleep or out of range"
        case .fresh, .stale:
            guard let level = state.level else { return "Reading battery…" }
            var parts: [String] = []
            if state.isCharging == true { parts.append("Charging") }
            if level < 15 && state.isCharging != true { parts.append("Low") }
            if let read = state.lastReadAt {
                let minutes = Int(now.timeIntervalSince(read) / 60)
                parts.append(minutes < 1 ? "read just now" : "read \(minutes) min ago")
            }
            return parts.joined(separator: " · ")
        }
    }
}
