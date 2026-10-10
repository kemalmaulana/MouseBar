import SwiftUI
import MouseCore

/// The menu bar item: battery symbol, optional percentage, moon when asleep, red tint when low.
struct BatteryLabel: View {
    let state: BatteryState
    @AppStorage("showPercentage") private var showPercentage = true

    private var isLow: Bool {
        state.freshness != .disconnected && (state.level ?? 100) < 15 && state.isCharging != true
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: BatteryPresentation.symbolName(for: state))
            if state.freshness == .asleep {
                Image(systemName: Theme.Symbol.asleep)
            }
            if showPercentage, let title = BatteryPresentation.compactTitle(for: state) {
                Text(title).monospacedDigit()
            }
        }
        .foregroundStyle(isLow ? Color.red : Color.primary)
        .opacity(state.freshness == .asleep ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BatteryPresentation.detail(for: state, now: Date()))
    }
}
