import SwiftUI
import MouseCore

/// Six preset LED colors as round, labelled swatch buttons.
struct LEDSwatches: View {
    static let presets: [(name: String, color: MouseCore.RGBColor)] = [
        ("Red", MouseCore.RGBColor(r: 255, g: 0, b: 0)),
        ("Orange", MouseCore.RGBColor(r: 255, g: 128, b: 0)),
        ("Green", MouseCore.RGBColor(r: 0, g: 255, b: 0)),
        ("Cyan", MouseCore.RGBColor(r: 0, g: 229, b: 255)),
        ("Blue", MouseCore.RGBColor(r: 0, g: 64, b: 255)),
        ("White", MouseCore.RGBColor(r: 255, g: 255, b: 255)),
    ]

    let selected: MouseCore.RGBColor?
    let onPick: (MouseCore.RGBColor) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Self.presets, id: \.name) { preset in
                let isSelected = selected == preset.color
                Button {
                    onPick(preset.color)
                } label: {
                    Circle()
                        .fill(preset.color.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1)
                        )
                        .frame(width: Theme.minHitTarget, height: Theme.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(isSelected ? "\(preset.name), selected" : preset.name)
            }
        }
    }
}
