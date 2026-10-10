import SwiftUI
import MouseCore

/// The Hardware Check assistant: progress header, one card per step, Skip / Cancel / Continue footer.
struct CheckWindow: View {
    let runner: CheckRunner
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsProgress: Bool {
        switch runner.phase {
        case .idle, .results: false
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                header
                Divider()
            }
            content
                .padding(Theme.windowPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedAnimation(runner.phaseToken, reduceMotion: reduceMotion)
            Divider()
            footer
                .padding(Theme.Space.l)
        }
        .frame(width: 560, height: 520)
        .overlay {
            if runner.phase == .restoring {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    ProgressView("Restoring your settings…")
                }
            }
        }
        .onDisappear { runner.cancel() }
    }

    private var header: some View {
        let total = CheckStepID.allCases.count
        return HStack(spacing: Theme.Space.xs) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index <= runner.stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Text("Step \(runner.stepIndex + 1) of \(total)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.windowPadding)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(runner.stepIndex + 1) of \(total)")
    }

    @ViewBuilder private var content: some View {
        switch runner.phase {
        case .idle:
            welcome
        case .preflight:
            CheckPreflightView(runner: runner, model: model)
        case .results:
            CheckResultsView(runner: runner)
        default:
            CheckStepCard(runner: runner)
        }
    }

    private var welcome: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Hardware Check")
                .font(.title3.weight(.semibold))
            Text("Checks that MouseBar's changes really reach your mouse: battery over the cable and the dongle, LED color, polling rate, buttons, DPI, saving, and wake. Takes about 5 minutes. Your settings are put back at the end.")
                .font(.callout)
                .multilineTextAlignment(.center)
            if model.ggWarning {
                StatusBanner(style: .warning, message: "SteelSeries GG is running and can interfere with the results. Quit it first if you can.")
            }
            if model.family == nil {
                StatusBanner(style: .info, message: "Connect your mouse with the USB cable to start.")
            }
        }
    }

    private var footer: some View {
        HStack {
            if runner.isRunning, runner.phase != .restoring {
                Button("Skip") { runner.skip() }
            }
            Spacer()
            if runner.phase != .results {
                Button("Cancel") {
                    if runner.isRunning {
                        runner.cancel()
                    } else {
                        dismissWindow(id: "hardware-check")
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(runner.phase == .restoring)
            }
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch runner.phase {
        case .idle:
            Button("Get started") { runner.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.family == nil)
        case .preflight:
            Button("Start check") { runner.beginTests() }
                .keyboardShortcut(.defaultAction)
        case .instructions(_, let title):
            Button(title) { runner.proceed() }
                .keyboardShortcut(.defaultAction)
        case .results:
            Button("Done") { dismissWindow(id: "hardware-check") }
                .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}
