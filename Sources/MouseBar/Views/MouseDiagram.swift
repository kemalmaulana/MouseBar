import SwiftUI
import MouseCore

/// A top-down mouse outline with a numbered marker on each button. Clicking a marker selects its row.
struct MouseDiagram: View {
    let buttons: [ButtonSpec]
    let mapping: ButtonMapping
    @Binding var selected: String?

    /// Marker positions in unit coordinates of the diagram (x right, y down).
    private static let positions: [String: CGPoint] = [
        "button1": CGPoint(x: 0.30, y: 0.20),
        "button2": CGPoint(x: 0.70, y: 0.20),
        "button3": CGPoint(x: 0.50, y: 0.21),
        "scrollup": CGPoint(x: 0.50, y: 0.08),
        "scrolldown": CGPoint(x: 0.50, y: 0.34),
        "button6": CGPoint(x: 0.50, y: 0.46),
        "button5": CGPoint(x: 0.07, y: 0.40),
        "button4": CGPoint(x: 0.07, y: 0.55),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                outline(in: size)
                ForEach(Array(buttons.enumerated()), id: \.element.name) { index, button in
                    let key = button.name.lowercased()
                    if let point = Self.positions[key] {
                        marker(number: index + 1, key: key, button: button)
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                }
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
    }

    private func outline(in size: CGSize) -> some View {
        let body = CGRect(x: size.width * 0.12, y: 0, width: size.width * 0.76, height: size.height)
        return ZStack {
            RoundedRectangle(cornerRadius: body.width * 0.48)
                .strokeBorder(.secondary, lineWidth: 1.5)
                .frame(width: body.width, height: body.height)
                .position(x: body.midX, y: body.midY)
            Path { path in
                path.move(to: CGPoint(x: body.midX, y: 0))
                path.addLine(to: CGPoint(x: body.midX, y: size.height * 0.40))
                path.move(to: CGPoint(x: body.minX + 6, y: size.height * 0.40))
                path.addLine(to: CGPoint(x: body.maxX - 6, y: size.height * 0.40))
            }
            .stroke(.secondary.opacity(0.6), lineWidth: 1)
            Capsule()
                .fill(.quaternary)
                .frame(width: size.width * 0.09, height: size.height * 0.16)
                .position(x: body.midX, y: size.height * 0.21)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: size.width * 0.06, height: size.height * 0.10)
                .position(x: body.minX + 2, y: size.height * 0.40)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: size.width * 0.06, height: size.height * 0.10)
                .position(x: body.minX + 2, y: size.height * 0.55)
        }
        .accessibilityHidden(true)
    }

    private func marker(number: Int, key: String, button: ButtonSpec) -> some View {
        let isSelected = selected == key
        let action = mapping.assignments[key] ?? "default"
        let actionText = action == "default"
            ? "default, \(ButtonNames.actionName(button.defaultAction))"
            : ButtonNames.actionName(action)
        return Button {
            selected = key
        } label: {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                .frame(width: Theme.minHitTarget, height: Theme.minHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Button \(number), \(ButtonNames.name(button.name)), mapped to \(actionText)")
    }
}
