import SwiftUI
import MouseCore

struct BatteryLabel: View {
    let state: BatteryState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: BatteryPresentation.symbolName(for: state))
            if let title = BatteryPresentation.compactTitle(for: state) {
                Text(title)
            }
        }
        .opacity(state.freshness == .asleep ? 0.55 : 1)
    }
}
