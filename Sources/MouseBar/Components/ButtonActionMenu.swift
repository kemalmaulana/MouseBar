import SwiftUI
import MouseCore

/// The action menu for one button: Default, Mouse, Media, and "Keyboard key…" (a searchable popover).
struct ButtonActionMenu: View {
    let spec: SettingSpec
    let button: ButtonSpec
    /// Current token for this button, "default" when unset.
    let token: String
    let layouts: ButtonLayouts
    let onChange: (String) -> Void
    @State private var showKeys = false

    private var defaultTitle: String { "Default (\(ButtonNames.actionName(button.defaultAction)))" }
    private var currentTitle: String { token == "default" ? defaultTitle : ButtonNames.actionName(token) }

    var body: some View {
        Menu {
            Button(defaultTitle) { onChange("default") }
            Section("Mouse") {
                ForEach(ButtonNames.mouseActions(for: spec), id: \.self) { action in
                    Button(ButtonNames.actionName(action)) { onChange(action) }
                }
            }
            if spec.buttonMultimedia != nil {
                Section("Media") {
                    ForEach(layouts.multimediaKeys, id: \.self) { key in
                        Button(ButtonNames.actionName(key.lowercased())) { onChange(key.lowercased()) }
                    }
                }
            }
            if spec.buttonKeyboard != nil {
                Divider()
                Button("Keyboard key…") { showKeys = true }
            }
        } label: {
            Text(currentTitle)
        }
        .fixedSize()
        .popover(isPresented: $showKeys, arrowEdge: .trailing) {
            KeyPickerPopover(keys: layouts.keyboardKeys) { key in
                onChange(key.lowercased())
                showKeys = false
            }
        }
        .accessibilityLabel("\(ButtonNames.name(button.name)) action")
        .accessibilityValue(currentTitle)
    }
}

struct KeyPickerPopover: View {
    let keys: [String]
    let onPick: (String) -> Void
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? keys : keys.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("Search keys", text: $query)
                .textFieldStyle(.roundedBorder)
            List(filtered, id: \.self) { key in
                Button {
                    onPick(key)
                } label: {
                    Text(key)
                        .frame(maxWidth: .infinity, minHeight: Theme.minHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 220)
        }
        .padding(Theme.Space.m)
        .frame(width: 220)
    }
}
