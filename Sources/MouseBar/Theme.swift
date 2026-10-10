import SwiftUI
import MouseCore

/// Design tokens (docs/superpowers/specs/2026-10-10-ui-refinement-design.md, section 2).
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let radius: CGFloat = 10
    static let windowPadding: CGFloat = 20
    static let minHitTarget: CGFloat = 28
    static let animation: Animation = .easeInOut(duration: 0.22)

    /// Battery level tint. Never the only signal: always shown with a symbol and the percentage or a word.
    static func batteryColor(level: Int?) -> Color {
        guard let level else { return .secondary }
        if level < 15 { return .red }
        if level <= 40 { return .orange }
        return .green
    }

    enum Symbol {
        static let charging = "bolt.fill"
        static let cable = "cable.connector"
        static let dongle = "antenna.radiowaves.left.and.right"
        static let asleep = "moon.zzz.fill"
        static let low = "battery.0percent"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "xmark.octagon.fill"
        static let info = "info.circle.fill"
        static let pass = "checkmark.circle.fill"
        static let fail = "xmark.circle.fill"
        static let skipped = "minus.circle"
        static let notRun = "circle.dashed"
        static let mouse = "computermouse"
    }
}

extension View {
    /// The theme's transition animation, or none when Reduce Motion is on.
    func themedAnimation<V: Equatable>(_ value: V, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? nil : Theme.animation, value: value)
    }
}
