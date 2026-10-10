import SwiftUI

/// An inline message with an icon, a word-bearing accessibility label, an optional action and dismiss.
struct StatusBanner: View {
    enum Style { case info, warning, error }

    let style: Style
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    private var symbol: String {
        switch style {
        case .info: Theme.Symbol.info
        case .warning: Theme.Symbol.warning
        case .error: Theme.Symbol.error
        }
    }

    private var tint: Color {
        switch style {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    private var word: String {
        switch style {
        case .info: "Note"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(word)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(Theme.Space.m)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityElement(children: .contain)
    }
}
