import SwiftUI
import MouseCore

/// The Buttons tab: diagram on the left, numbered list with friendly names and action menus on the right.
struct ButtonsEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var selected: String?

    private var mapping: ButtonMapping {
        if case .buttons(let m)? = currentValue(spec, model) { return m }
        return ButtonMapping()
    }

    private var buttons: [ButtonSpec] { spec.buttons ?? [] }

    private func set(_ button: ButtonSpec, to token: String) {
        var assignments = mapping.assignments
        if token == "default" {
            assignments.removeValue(forKey: button.name.lowercased())
        } else {
            assignments[button.name.lowercased()] = token
        }
        model.submit(spec.key, .buttons(ButtonMapping(assignments: assignments)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            MouseDiagram(buttons: buttons, mapping: mapping, selected: $selected)
                .frame(width: 130)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(Array(buttons.enumerated()), id: \.element.name) { index, button in
                    let key = button.name.lowercased()
                    HStack(spacing: Theme.Space.s) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(selected == key ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15)))
                            .accessibilityHidden(true)
                        Text(ButtonNames.name(button.name))
                        Spacer()
                        ButtonActionMenu(
                            spec: spec, button: button,
                            token: mapping.assignments[key] ?? "default",
                            layouts: model.layouts
                        ) { set(button, to: $0) }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, Theme.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == key ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selected = key }
                }
                Button("Restore defaults") {
                    model.submit(spec.key, .buttons(ButtonMapping()))
                }
                .frame(minHeight: Theme.minHitTarget)
                .padding(.top, Theme.Space.s)
            }
        }
    }
}
