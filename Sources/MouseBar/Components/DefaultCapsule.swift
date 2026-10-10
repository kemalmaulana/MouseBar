import SwiftUI

/// Marks a setting MouseBar has never set: the mouse can't report its value, so the UI shows the factory default.
struct DefaultCapsule: View {
    var body: some View {
        Text("Default")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .help("The mouse can't report its settings. This shows the factory default; changing it writes it to the mouse.")
            .accessibilityLabel("Factory default, not set by MouseBar")
    }
}
