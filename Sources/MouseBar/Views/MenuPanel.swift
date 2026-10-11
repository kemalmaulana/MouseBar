import SwiftUI
import MouseCore

/// The menu bar dropdown: mouse and connection, battery gauge, quick controls, banners, save feedback, actions.
struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
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
            if model.mice.count > 1 {
                mousePicker
            } else {
                Text(model.displayName ?? "Mouse")
                    .font(.headline)
                    .lineLimit(1)
            }
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

    /// Shown only when more than one physical mouse is connected: the name of the active one opens the list.
    private var mousePicker: some View {
        Menu {
            Picker("Mouse", selection: Binding(
                get: { model.activeMouseID ?? "" },
                set: { model.selectMouse($0) }
            )) {
                ForEach(model.mice) { mouse in
                    Text(mouse.name).tag(mouse.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(model.displayName ?? "Mouse")
                .font(.headline)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(minHeight: Theme.minHitTarget)
        .disabled(model.isCheckRunning)
        .accessibilityLabel("Active mouse: \(model.displayName ?? "none")")
        .help("Choose which mouse MouseBar controls")
    }

    private var battery: some View {
        let state = model.battery
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
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
                        set: { new in
                            // Re-picking the shown value is not a change: don't write it.
                            if case .choice(let shown)? = currentValue(spec, model), shown == new { return }
                            model.submit(spec.key, .choice(new))
                        }
                    )) {
                        ForEach(spec.choices ?? [], id: \.key) { choice in
                            Text(ValueFormat.choice(key: spec.key, choice.key)).tag(choice.key)
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
                        .frame(minHeight: Theme.minHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("LED color \(current.map { "#" + $0.hexString.uppercased() } ?? "not set")")
                    .popover(isPresented: $showColors, arrowEdge: .bottom) {
                        LEDSwatches(selected: current) { model.submit(spec.key, .color($0)) }
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
                Button {
                    openWindow(id: "hardware-check")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("Hardware Check…").frame(minHeight: Theme.minHitTarget).contentShape(Rectangle())
                }
                Spacer()
                Button {
                    // A menu bar app must activate first, or the Settings window opens behind other apps.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Text("Settings…").frame(minHeight: Theme.minHitTarget).contentShape(Rectangle())
                }
                .keyboardShortcut(",")
            }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit MouseBar").frame(minHeight: Theme.minHitTarget).contentShape(Rectangle())
            }
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
            return parts.isEmpty ? "Battery OK" : parts.joined(separator: " · ")
        }
    }
}
