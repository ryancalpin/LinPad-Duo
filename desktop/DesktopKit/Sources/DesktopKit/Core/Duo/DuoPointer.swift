import Perception
import SwiftUI
import UIKit

/// The pointer the on-screen trackpad drives (laptop pose, or the phone as a monitor's
/// trackpad). It lives in desktop coordinates and is drawn by `DuoPointerOverlay`.
///
/// Over a Linux window it sends real pointer events (motion, buttons, scrolling) through
/// the bridge, the same path a hardware mouse takes. Over the desktop's own controls
/// (panels, docks, title-bar buttons, built-in apps) a click presses the control under
/// the pointer through iOS's accessibility interface, the way Voice Control and Switch
/// Control press buttons; anything that isn't a control brings its window to the front.
@Perceptible @MainActor
final class DuoVirtualPointer {
    private enum Button {
        static let left: UInt32 = 0x110
        static let right: UInt32 = 0x111
    }

    private(set) var location = CGPoint(x: 200, y: 200)
    private(set) var isShown = false
    @PerceptionIgnored weak var controller: DesktopController?
    @PerceptionIgnored private var hoveredSurface: UInt32?
    @PerceptionIgnored private var heldButton: (button: UInt32, surface: UInt32)?
    @PerceptionIgnored private var scrollSurface: UInt32?

    /// Trackpad speed: a fast swipe moves the pointer further than a slow one.
    static func accelerated(_ delta: CGSize) -> CGSize {
        let speed = hypot(delta.width, delta.height)
        let gain = min(1.2 + speed / 14, 3.2)
        return CGSize(width: delta.width * gain, height: delta.height * gain)
    }

    func show() {
        guard let size = controller?.windowManager.desktopSize, size.width > 0 else { return }
        if !isShown { location = CGPoint(x: size.width / 2, y: size.height / 2) }
        isShown = true
    }

    func hide() {
        if let held = heldButton { controller?.linux?.pointerButton(held.surface, .zero, button: held.button, pressed: false) }
        heldButton = nil
        if hoveredSurface != nil { controller?.linux?.pointerLeave() }
        hoveredSurface = nil
        isShown = false
    }

    func move(by delta: CGSize) {
        guard let size = controller?.windowManager.desktopSize, size.width > 0 else { return }
        show()
        let step = Self.accelerated(delta)
        location = CGPoint(x: min(max(location.x + step.width, 0), size.width - 1),
                           y: min(max(location.y + step.height, 0), size.height - 1))
        deliverMotion()
    }

    func click(right: Bool = false) {
        show()
        let button = right ? Button.right : Button.left
        guard let (surface, point) = linuxTarget() else {
            if right || !activateControlUnderPointer() { focusWindowUnderPointer() }
            return
        }
        focusWindowUnderPointer()
        controller?.linux?.pointerMotion(surface, point)
        controller?.linux?.pointerButton(surface, point, button: button, pressed: true)
        controller?.linux?.pointerButton(surface, point, button: button, pressed: false)
    }

    /// Tap and then drag: the left button stays down until `endDrag`.
    func beginDrag() {
        show()
        guard let (surface, point) = linuxTarget() else { return }
        focusWindowUnderPointer()
        heldButton = (Button.left, surface)
        controller?.linux?.pointerButton(surface, point, button: Button.left, pressed: true)
    }

    func endDrag() {
        guard let held = heldButton else { return }
        heldButton = nil
        let point = surfacePoint(in: held.surface) ?? .zero
        controller?.linux?.pointerButton(held.surface, point, button: held.button, pressed: false)
    }

    /// Two-finger scrolling: content follows the fingers, as on a real trackpad.
    func scroll(by fingerDelta: CGSize) {
        show()
        guard let (surface, point) = linuxTarget() else { return }
        scrollSurface = surface
        controller?.linux?.pointerMotion(surface, point)
        controller?.linux?.pointerAxis(surface, dx: -fingerDelta.width, dy: -fingerDelta.height, source: .finger)
    }

    func endScroll() {
        guard let surface = scrollSurface else { return }
        scrollSurface = nil
        controller?.linux?.pointerAxisStop(surface)
    }

    // MARK: Targets

    private func deliverMotion() {
        if let held = heldButton {
            // Dragging keeps sending to the surface the press went to, as a real grab does.
            if let point = surfacePoint(in: held.surface) { controller?.linux?.pointerMotion(held.surface, point) }
            return
        }
        if let (surface, point) = linuxTarget() {
            hoveredSurface = surface
            controller?.linux?.pointerMotion(surface, point)
        } else if hoveredSurface != nil {
            hoveredSurface = nil
            controller?.linux?.pointerLeave()
        }
    }

    /// The Linux surface (toplevel or popup) under the pointer, and the point in its own
    /// coordinates; nil over anything else.
    private func linuxTarget() -> (UInt32, CGPoint)? {
        guard let reference = controller?.input.referenceView, let window = reference.window else { return nil }
        let point = reference.convert(location, to: window)
        var view = window.hitTest(point, with: nil)
        while let current = view, !(current is LinuxSurfaceView) { view = current.superview }
        guard let surfaceView = view as? LinuxSurfaceView else { return nil }
        return (surfaceView.surfaceID, window.convert(point, to: surfaceView))
    }

    private func surfacePoint(in surfaceID: UInt32) -> CGPoint? {
        guard let reference = controller?.input.referenceView,
              let view = controller?.linux?.surface(withID: surfaceID)?.view, view.window != nil else { return nil }
        return reference.convert(location, to: view)
    }

    /// Presses the button (or other control) under the pointer with `accessibilityActivate()`,
    /// public UIKit API that SwiftUI answers for its buttons, toggles and tap gestures.
    private func activateControlUnderPointer() -> Bool {
        guard let reference = controller?.input.referenceView, let window = reference.window else { return false }
        let windowPoint = reference.convert(location, to: window)
        let screenPoint = UIAccessibility.convertToScreenCoordinates(CGRect(origin: location, size: .zero), in: reference).origin
        var view = window.hitTest(windowPoint, with: nil)
        // The hit view itself, or the nearest container above it that lists accessibility elements.
        while let current = view {
            if let element = Self.deepestElement(at: screenPoint, in: current, depth: 0), element.accessibilityActivate() {
                return true
            }
            view = current.superview
        }
        return false
    }

    /// The innermost accessibility element whose frame holds the point, searching the
    /// container's elements topmost (last) first.
    private static func deepestElement(at point: CGPoint, in container: NSObject, depth: Int) -> NSObject? {
        guard depth < 24 else { return nil }
        let children: [NSObject]
        if let elements = container.accessibilityElements as? [NSObject] {
            children = elements
        } else {
            let count = container.accessibilityElementCount()
            children = count == NSNotFound || count <= 0 ? []
                : (0..<count).compactMap { container.accessibilityElement(at: $0) as? NSObject }
        }
        for child in children.reversed() where child.accessibilityFrame.contains(point) {
            if let deeper = deepestElement(at: point, in: child, depth: depth + 1) { return deeper }
            if child.isAccessibilityElement { return child }
        }
        return nil
    }

    private func focusWindowUnderPointer() {
        guard let manager = controller?.windowManager else { return }
        let target = manager.visibleStack().first { manager.displayFrame(for: $0).contains(location) }
        if let target, target.id != manager.focusedWindowID { manager.focus(target.id) }
    }
}

/// The trackpad pointer, drawn over the desktop area.
struct DuoPointerOverlay: View {
    let pointer: DuoVirtualPointer

    var body: some View {
        WithPerceptionTracking {
            if pointer.isShown {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 1.5)
                    // The arrow's tip is the point.
                    .position(x: pointer.location.x + 7, y: pointer.location.y + 11)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One-finger moves the pointer, a tap clicks, a two-finger tap right-clicks, two fingers
/// scroll, and tap-then-drag holds the button (selecting text, dragging windows' contents).
struct DuoTrackpad: UIViewRepresentable {
    let pointer: DuoVirtualPointer

    func makeUIView(context: Context) -> TrackpadView {
        TrackpadView(pointer: pointer)
    }

    func updateUIView(_ uiView: TrackpadView, context: Context) {}

    /// Raw touches rather than gesture recognizers: a trackpad has to tell a tap from a
    /// move from a two-finger scroll at once, without waiting for one gesture to fail.
    final class TrackpadView: UIView {
        private static let tapTime: TimeInterval = 0.25
        private static let tapSlop: CGFloat = 8
        /// A second touch this soon after a tap starts a drag.
        private static let dragWindow: TimeInterval = 0.3

        private let pointer: DuoVirtualPointer
        private var active: Set<UITouch> = []
        private var began = Date.distantPast
        private var travelled: CGFloat = 0
        private var mostTouches = 0
        private var lastCentroid = CGPoint.zero
        private var lastTap = Date.distantPast
        private var isDragging = false
        private var isScrolling = false

        init(pointer: DuoVirtualPointer) {
            self.pointer = pointer
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isAccessibilityElement = true
            accessibilityLabel = "Trackpad"
            accessibilityHint = "Move one finger to move the pointer, tap to click, tap with two fingers to right-click."
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        private var centroid: CGPoint {
            let points = active.map { $0.location(in: self) }
            guard !points.isEmpty else { return .zero }
            return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                           y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let wasIdle = active.isEmpty
            active.formUnion(touches)
            lastCentroid = centroid
            mostTouches = max(mostTouches, active.count)
            guard wasIdle else { return }
            began = Date()
            travelled = 0
            mostTouches = active.count
            if active.count == 1 && Date().timeIntervalSince(lastTap) < Self.dragWindow {
                isDragging = true
                pointer.beginDrag()
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            let now = centroid
            let delta = CGSize(width: now.x - lastCentroid.x, height: now.y - lastCentroid.y)
            lastCentroid = now
            travelled += hypot(delta.width, delta.height)
            if active.count >= 2 && !isDragging {
                isScrolling = true
                pointer.scroll(by: delta)
            } else if active.count == 1 && !isScrolling {
                pointer.move(by: delta)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches, cancelled: true)
        }

        private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
            active.subtract(touches)
            lastCentroid = centroid
            guard active.isEmpty else { return }
            let wasTap = !cancelled && Date().timeIntervalSince(began) < Self.tapTime && travelled < Self.tapSlop
            if isDragging {
                pointer.endDrag()
            } else if isScrolling {
                pointer.endScroll()
            } else if wasTap {
                pointer.click(right: mostTouches >= 2)
                if mostTouches == 1 { lastTap = Date() }
            }
            isDragging = false
            isScrolling = false
            mostTouches = 0
        }
    }
}
