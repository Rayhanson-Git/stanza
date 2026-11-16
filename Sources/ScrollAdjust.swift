import AppKit
import SwiftUI

/// Turning a scroll (mouse wheel or two-finger swipe) into a slider change.
enum ScrollAdjust {
    /// A trackpad swipe of this many points, or this many wheel notches, crosses the whole range.
    private static let pointsPerRange = 400.0, notchesPerRange = 40.0

    /// How far `event` moves a slider whose range is `span` wide: up or right is more, as the hand moves, whatever the
    /// system's natural-scrolling setting. Zero for an event with no movement.
    static func change(for event: NSEvent, span: Double) -> Double {
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        // Natural scrolling flips the vertical delta; undo that so a physical move up always means bigger.
        let raw = horizontal ? -Double(event.scrollingDeltaX) : Double(event.scrollingDeltaY)
        let hand = event.isDirectionInvertedFromDevice ? -raw : raw
        return hand * span / (event.hasPreciseScrollingDeltas ? pointsPerRange : notchesPerRange)
    }
}

extension View {
    /// Lets the mouse wheel or a trackpad swipe move a slider while the pointer is over it.
    func adjustsWithScroll(_ value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        background(ScrollCatcher(value: value, range: range))
    }
}

/// Watches scroll events inside its own bounds without taking clicks or drags from the slider it sits behind.
private struct ScrollCatcher: NSViewRepresentable {
    let value: Binding<Double>
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = { event in
            let next = value.wrappedValue + ScrollAdjust.change(for: event, span: range.upperBound - range.lowerBound)
            value.wrappedValue = min(max(next, range.lowerBound), range.upperBound)
        }
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stopWatching() }
}

private final class CatcherView: NSView {
    var onScroll: ((NSEvent) -> Void)?
    private var monitor: Any?
    private var ownsGesture = false

    /// Clicks and drags go straight to the slider in front.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window, event.window === window else { return event }
            // Only the part of the slider that can be seen counts, not one scrolled away inside a panel.
            let inside = visibleRect.contains(convert(event.locationInWindow, from: nil))
            // A trackpad swipe belongs to wherever it began, so a page flicked under a resting pointer keeps its
            // momentum instead of nudging the slider; a mouse wheel has no phases and goes by where the pointer is.
            if event.phase == .began || event.phase == .mayBegin { ownsGesture = inside }
            let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            guard isGesture ? ownsGesture : inside else { return event }
            onScroll?(event)
            return nil
        }
    }

    func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
