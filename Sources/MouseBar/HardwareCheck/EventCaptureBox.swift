import AppKit
import SwiftUI
import MouseCore

/// Captures mouse-move timestamps (event coalescing off) or one key press while the pointer is inside it.
struct EventCaptureBox: NSViewRepresentable {
    enum Mode: Equatable {
        case measure(seconds: Double)
        case key(keyCode: UInt16)
    }

    let mode: Mode
    let onTimestamps: ([Double]) -> Void
    let onKey: () -> Void
    let onLive: (Double?) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        update(view)
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        update(view)
    }

    private func update(_ view: CaptureView) {
        view.mode = mode
        view.onTimestamps = onTimestamps
        view.onKey = onKey
        view.onLive = onLive
    }
}

final class CaptureView: NSView {
    var mode: EventCaptureBox.Mode = .measure(seconds: 3)
    var onTimestamps: (([Double]) -> Void)?
    var onKey: (() -> Void)?
    var onLive: ((Double?) -> Void)?
    private var timestamps: [Double] = []
    private var startedAt: TimeInterval?
    private var finished = false
    private var savedCoalescing: Bool?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            // Coalescing merges mouse moves; it must be off to count the mouse's real report rate.
            savedCoalescing = NSEvent.isMouseCoalescingEnabled
            NSEvent.isMouseCoalescingEnabled = false
            window.acceptsMouseMovedEvents = true
            window.makeFirstResponder(self)
        } else if let saved = savedCoalescing {
            NSEvent.isMouseCoalescingEnabled = saved
            savedCoalescing = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard case .measure(let seconds) = mode, !finished else { return }
        if startedAt == nil { startedAt = event.timestamp }
        timestamps.append(event.timestamp)
        if timestamps.count % 20 == 0 {
            onLive?(PollingRateEstimator.rate(timestamps: Array(timestamps.suffix(80))))
        }
        if let startedAt, event.timestamp - startedAt >= seconds {
            finished = true
            onTimestamps?(timestamps)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard case .key(let code) = mode, !finished, event.keyCode == code else {
            super.keyDown(with: event)
            return
        }
        finished = true
        onKey?()
    }
}
