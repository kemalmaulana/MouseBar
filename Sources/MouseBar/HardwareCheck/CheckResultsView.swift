import AppKit
import SwiftUI
import MouseCore

struct CheckResultsView: View {
    let runner: CheckRunner
    let model: AppModel
    @State private var expanded: Set<CheckStepID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            CheckBanners(model: model)
            if !runner.canRerun {
                StatusBanner(style: .info, message: "Run again needs the mouse that was checked. Pick it in the menu bar panel.")
            }
            Text("Results")
                .font(.title3.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(CheckStepID.allCases, id: \.self) { step in
                        row(step)
                    }
                }
            }
            HStack {
                Button("Copy report") {
                    guard let markdown = runner.reportMarkdown else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                .disabled(runner.reportMarkdown == nil)
                Button("Reveal in Finder") {
                    if let url = runner.reportURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(runner.reportURL == nil)
            }
        }
    }

    private func row(_ step: CheckStepID) -> some View {
        let outcome = runner.outcomes[step]
        return DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(step) },
            set: { open in
                if open { expanded.insert(step) } else { expanded.remove(step) }
            }
        )) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(outcome?.detail ?? "Not run").font(.callout)
                if let raw = outcome?.rawHex {
                    Text(raw).font(.caption).monospaced().textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                resultLabel(outcome?.result)
                Text(step.title)
                Spacer()
                if step != .preflight {
                    Button {
                        runner.rerun(step)
                    } label: {
                        Text("Run again")
                            .frame(minWidth: Theme.minHitTarget, minHeight: Theme.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .controlSize(.small)
                    .disabled(runner.isRunning || !runner.canRerun)
                    .accessibilityLabel("Run \(step.title) again")
                }
            }
        }
    }

    @ViewBuilder private func resultLabel(_ result: StepResult?) -> some View {
        switch result {
        case .pass?:
            Label("Passed", systemImage: Theme.Symbol.pass).foregroundStyle(.green).labelStyle(.titleAndIcon)
        case .fail?:
            Label("Failed", systemImage: Theme.Symbol.fail).foregroundStyle(.red).labelStyle(.titleAndIcon)
        case .skipped?:
            Label("Skipped", systemImage: Theme.Symbol.skipped).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        case nil:
            Label("Not run", systemImage: Theme.Symbol.notRun).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
    }
}
