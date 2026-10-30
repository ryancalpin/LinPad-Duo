import DesktopTouchSynth
import OSLog
import Perception
import SwiftUI
import UIKit
import WebKit

private let trackpadLogger = Logger(subsystem: "DesktopKit", category: "DuoTrackpad")

/// The pointer the on-screen trackpad drives (laptop pose, or the phone as a monitor's
/// trackpad). It lives in desktop coordinates and is drawn by `DuoPointerOverlay`.
///
/// Over a Linux window it sends real pointer events (motion, buttons, scrolling) through
/// the bridge, the same path a hardware mouse takes. Elsewhere a click first presses the
/// control under the pointer through iOS's accessibility interface, the way Voice Control
/// does (the panel, title-bar buttons). SwiftUI lists nothing inside scroll views that way,
/// so anything else (the launcher grid, built-in apps' lists, the terminal) gets a real
/// finger touch at the pointer (`DTSTouch`).
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
    /// Tap-then-drag outside Linux windows: a finger held down at the pointer.
    @PerceptionIgnored private var heldTouch: DTSTouch?

    /// Trackpad speed: a fast swipe moves the pointer further than a slow one.
    static func accelerated(_ delta: CGSize) -> CGSize {
        let speed = hypot(delta.width, delta.height)
        let gain = min(1.2 + speed / 14, 3.2)
        return CGSize(width: delta.width * gain, height: delta.height * gain)
    }

    /// Tests: puts the pointer at a desktop point.
    func place(at point: CGPoint) {
        isShown = true
        location = point
    }

    func show() {
        guard let size = controller?.windowManager.desktopSize, size.width > 0 else { return }
        if !isShown { location = CGPoint(x: size.width / 2, y: size.height / 2) }
        isShown = true
    }

    func hide() {
        if let held = heldButton { controller?.linux?.pointerButton(held.surface, .zero, button: held.button, pressed: false) }
        heldButton = nil
        heldTouch?.end()
        heldTouch = nil
        if hoveredSurface != nil { controller?.linux?.pointerLeave() }
        hoveredSurface = nil
        isShown = false
    }

    func move(by delta: CGSize) {
        guard let size = controller?.windowManager.desktopSize, size.width > 0 else { return }
        show()
        let step = Self.accelerated(delta)
        // The desktop starts below the panel (and beside a side dock); the pointer may go
        // up and left of it to reach them.
        let origin = controller?.windowManager.desktopGlobalOrigin ?? .zero
        location = CGPoint(x: min(max(location.x + step.width, -origin.x), size.width - 1),
                           y: min(max(location.y + step.height, -origin.y), size.height - 1))
        deliverMotion()
    }

    func click(right: Bool = false) {
        show()
        let button = right ? Button.right : Button.left
        guard let (surface, point) = linuxTarget() else {
            focusWindowUnderPointer()
            guard !right else { return }
            // Controls SwiftUI lists to accessibility (the panel, title bars) are pressed
            // directly; anything else (scroll view content, the terminal) gets a real touch.
            let path: String
            if activateControlUnderPointer() {
                path = "control"
            } else if let (window, windowPoint) = windowTarget(), DTSTouch.tap(at: windowPoint, in: window) {
                path = "touch"
            } else if clickWebView() {
                path = "web"
            } else {
                path = "nothing"
            }
            trackpadLogger.notice("click at \(self.location.debugDescription, privacy: .public): \(path, privacy: .public)")
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
        guard let (surface, point) = linuxTarget() else {
            // Elsewhere a held finger: scrolls lists, drags windows by their title bars.
            if let (window, windowPoint) = windowTarget() { heldTouch = DTSTouch.begin(at: windowPoint, in: window) }
            return
        }
        focusWindowUnderPointer()
        heldButton = (Button.left, surface)
        controller?.linux?.pointerButton(surface, point, button: Button.left, pressed: true)
    }

    func endDrag() {
        heldTouch?.end()
        heldTouch = nil
        guard let held = heldButton else { return }
        heldButton = nil
        let point = surfacePoint(in: held.surface) ?? .zero
        controller?.linux?.pointerButton(held.surface, point, button: held.button, pressed: false)
    }

    /// Two-finger scrolling: content follows the fingers, as on a real trackpad.
    func scroll(by fingerDelta: CGSize) {
        show()
        guard let (surface, point) = linuxTarget() else {
            scrollViewUnderPointer(by: fingerDelta)
            return
        }
        scrollSurface = surface
        controller?.linux?.pointerMotion(surface, point)
        controller?.linux?.pointerAxis(surface, dx: -fingerDelta.width, dy: -fingerDelta.height, source: .finger)
    }

    func endScroll() {
        guard let surface = scrollSurface else { return }
        scrollSurface = nil
        controller?.linux?.pointerAxisStop(surface)
    }

    /// Outside Linux windows: the nearest scroll view under the pointer that can move that
    /// way. SwiftUI's ScrollView and the terminal's web content are UIScrollViews.
    private func scrollViewUnderPointer(by delta: CGSize) {
        guard let reference = controller?.input.referenceView, let window = reference.window else { return }
        var view = window.hitTest(reference.convert(location, to: window), with: nil)
        let vertical = abs(delta.height) >= abs(delta.width)
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                let inset = scroll.adjustedContentInset
                let minimum = CGPoint(x: -inset.left, y: -inset.top)
                let maximum = CGPoint(x: max(minimum.x, scroll.contentSize.width - scroll.bounds.width + inset.right),
                                      y: max(minimum.y, scroll.contentSize.height - scroll.bounds.height + inset.bottom))
                if vertical ? maximum.y > minimum.y : maximum.x > minimum.x {
                    let offset = CGPoint(x: min(max(scroll.contentOffset.x - delta.width, minimum.x), maximum.x),
                                         y: min(max(scroll.contentOffset.y - delta.height, minimum.y), maximum.y))
                    scroll.setContentOffset(offset, animated: false)
                    return
                }
            }
            view = current.superview
        }
    }

    // MARK: Targets

    private func deliverMotion() {
        if let heldTouch, let (_, windowPoint) = windowTarget() {
            heldTouch.move(to: windowPoint)
            return
        }
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

    /// The pointer's window and its point in window coordinates.
    private func windowTarget() -> (UIWindow, CGPoint)? {
        guard let reference = controller?.input.referenceView, let window = reference.window else { return nil }
        return (window, reference.convert(location, to: window))
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
        // Accessibility frames are in screen coordinates. UIAccessibility.convertToScreenCoordinates
        // returned the point unchanged for this SwiftUI-hosted view, missing the panel's offset.
        let screenPoint = window.convert(windowPoint, to: window.screen.coordinateSpace)
        let hit = window.hitTest(windowPoint, with: nil)
        if let control = hit as? UIControl, control.isEnabled {
            control.sendActions(for: .touchUpInside)
            return true
        }
        // The hit view itself, or the nearest container above it that lists accessibility elements.
        var view = hit
        while let current = view {
            // The SwiftUI desktop lists one flat tree for everything, including containers
            // and plain text that don't act on activation; try each element under the point,
            // topmost first, until one does.
            for element in Self.elements(at: screenPoint, in: current) where element.accessibilityActivate() {
                trackpadLogger.notice("activated \(element.accessibilityLabel ?? "?", privacy: .public)")
                return true
            }
            view = current.superview
        }
        return false
    }

    /// The accessibility elements whose frames hold the point: innermost first within each
    /// container, and the container's elements topmost (last) first.
    private static func elements(at point: CGPoint, in container: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 24 else { return [] }
        let children: [NSObject]
        if let elements = container.accessibilityElements as? [NSObject] {
            children = elements
        } else {
            let count = container.accessibilityElementCount()
            children = count == NSNotFound || count <= 0 ? []
                : (0..<count).compactMap { container.accessibilityElement(at: $0) as? NSObject }
        }
        var found: [NSObject] = []
        for child in children.reversed() {
            let frame = child.accessibilityFrame
            if frame.contains(point) {
                found += elements(at: point, in: child, depth: depth + 1)
                if child.isAccessibilityElement { found.append(child) }
            } else if frame.isEmpty && !child.isAccessibilityElement {
                // Scrolling content (the launcher's app grid) is a container that reports
                // no frame of its own; its elements have real ones.
                found += elements(at: point, in: child, depth: depth + 1)
            }
        }
        return found
    }

    /// The terminal (and other web content) is a WKWebView, not a Linux surface: give it
    /// keyboard focus and send the click to the element under the pointer as DOM mouse
    /// events, inside hterm's iframe when it has one.
    private func clickWebView() -> Bool {
        guard let reference = controller?.input.referenceView, let window = reference.window else { return false }
        let windowPoint = reference.convert(location, to: window)
        var view = window.hitTest(windowPoint, with: nil)
        while let current = view, !(current is WKWebView) { view = current.superview }
        guard let webView = view as? WKWebView else { return false }
        let point = window.convert(windowPoint, to: webView)
        webView.becomeFirstResponder()
        webView.evaluateJavaScript(Self.webClickScript(x: point.x, y: point.y))
        return true
    }

    private static func webClickScript(x: CGFloat, y: CGFloat) -> String {
        """
        (function (x, y) {
          var doc = document, el = doc.elementFromPoint(x, y);
          while (el && el.tagName === 'IFRAME' && el.contentDocument) {
            var r = el.getBoundingClientRect();
            x -= r.left; y -= r.top;
            el.contentWindow.focus();
            doc = el.contentDocument;
            el = doc.elementFromPoint(x, y);
          }
          if (!el) return false;
          var view = doc.defaultView;
          ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (type) {
            var Ctor = type.indexOf('pointer') === 0 && view.PointerEvent ? view.PointerEvent : view.MouseEvent;
            el.dispatchEvent(new Ctor(type, {bubbles: true, cancelable: true, view: view, clientX: x, clientY: y,
                                             button: 0, buttons: /down$/.test(type) ? 1 : 0, pointerType: 'mouse'}));
          });
          if (el.focus) el.focus();
          return true;
        })(\(x), \(y));
        """
    }

    private func focusWindowUnderPointer() {
        guard let manager = controller?.windowManager else { return }
        let target = manager.visibleStack().first { manager.displayFrame(for: $0).contains(location) }
        if let target, target.id != manager.focusedWindowID { manager.focus(target.id) }
    }
}

/// The trackpad pointer. It sits over the whole desktop shell, above the panel, and maps
/// the pointer's desktop coordinates into its own through the desktop's global origin.
struct DuoPointerOverlay: View {
    let pointer: DuoVirtualPointer

    var body: some View {
        GeometryReader { proxy in
            WithPerceptionTracking {
                if pointer.isShown {
                    let desktop = pointer.controller?.windowManager.desktopGlobalOrigin ?? .zero
                    let own = proxy.frame(in: .global).origin
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 1.5)
                        // The arrow's tip is the point.
                        .position(x: pointer.location.x + desktop.x - own.x + 7,
                                  y: pointer.location.y + desktop.y - own.y + 11)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
