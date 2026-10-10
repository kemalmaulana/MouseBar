import SwiftUI
import MouseCore

/// "Saving to mouse…" while a save runs, "Saved to mouse" briefly afterwards, nothing otherwise.
/// A failed save is shown by AppModel as an error banner instead.
struct SaveStatusLine: View {
    let state: SaveState?

    var body: some View {
        Group {
            switch state {
            case .saving?:
                HStack(spacing: Theme.Space.xs) {
                    ProgressView().controlSize(.mini)
                    Text("Saving to mouse…")
                }
            case .saved?:
                Label("Saved to mouse", systemImage: Theme.Symbol.pass)
                    .foregroundStyle(.green)
            default:
                EmptyView()
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
