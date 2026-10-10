import SwiftUI
import MouseCore

/// LED color: system color well, six preset swatches, and the hex code.
struct ColorEditor: View {
    let model: AppModel
    let spec: SettingSpec

    private var color: MouseCore.RGBColor {
        if case .color(let c)? = currentValue(spec, model) { return c }
        return MouseCore.RGBColor(r: 255, g: 0, b: 0)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ColorPicker("LED color", selection: Binding(
                get: { color.swiftUIColor },
                set: { if let rgb = MouseCore.RGBColor(color: $0) { model.submit(spec.key, .color(rgb)) } }
            ), supportsOpacity: false)
            .labelsHidden()
            LEDSwatches(selected: color) { model.submit(spec.key, .color($0)) }
            Spacer()
            Text("#" + color.hexString.uppercased())
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel("Hex code \(color.hexString.uppercased())")
        }
    }
}
