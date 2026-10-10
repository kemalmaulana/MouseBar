import SwiftUI
import MouseCore

extension CheckStepID {
    var symbol: String {
        switch self {
        case .preflight: "checklist"
        case .batteryCable: "cable.connector"
        case .batteryDongle: "antenna.radiowaves.left.and.right"
        case .ledColor: "lightbulb.fill"
        case .pollingRate: "speedometer"
        case .buttons: "computermouse.fill"
        case .dpiPreset: "cursorarrow.motionlines"
        case .savePersistence: "memorychip"
        case .wakeReapply: "power"
        }
    }
}

/// The current step: symbol, title, and the phase's interaction area.
struct CheckStepCard: View {
    let runner: CheckRunner

    private var step: CheckStepID {
        let all = CheckStepID.allCases
        return all[min(runner.stepIndex, all.count - 1)]
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: step.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(step.title)
                .font(.title3.weight(.semibold))
            phaseBody
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var phaseBody: some View {
        switch runner.phase {
        case .instructions(let text, _):
            Text(text).font(.callout)
        case .working(let text):
            ProgressView(text)
        case .question(let text):
            VStack(spacing: Theme.Space.l) {
                Text(text).font(.callout)
                HStack(spacing: Theme.Space.m) {
                    Button("No") { runner.answer(false) }
                        .controlSize(.large)
                    Button("Yes") { runner.answer(true) }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                }
            }
        case .measure(let text, let seconds):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                CaptureArea(mode: .measure(seconds: seconds), runner: runner)
                    .id(runner.phaseToken)
            }
        case .keyPress(let text):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                CaptureArea(mode: .key(keyCode: CheckRunner.f18KeyCode), runner: runner)
                    .id(runner.phaseToken)
            }
        case .waiting(let text, let until):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("\(max(0, Int(until.timeIntervalSince(context.date)))) s left")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        default:
            EmptyView()
        }
    }
}

/// A dashed box with the capture view inside and a live readout.
struct CaptureArea: View {
    let mode: EventCaptureBox.Mode
    let runner: CheckRunner
    @State private var live: Double?

    private var isMeasure: Bool {
        if case .measure = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius).fill(.quaternary)
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            EventCaptureBox(
                mode: mode,
                onTimestamps: { runner.submit(timestamps: $0) },
                onKey: { runner.keyPressed() },
                onLive: { live = $0 }
            )
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: isMeasure ? "arrow.triangle.2.circlepath" : "keyboard")
                    .font(.title2)
                Text(isMeasure ? (live.map { String(format: "%.0f events/s", $0) } ?? "Move the mouse here")
                               : "Press side button 4 here")
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMeasure ? "Capture area. Move the mouse in circles here." : "Capture area. Press side button 4 here.")
    }
}
