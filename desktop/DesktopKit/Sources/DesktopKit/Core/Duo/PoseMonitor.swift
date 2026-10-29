import Perception
import SwiftUI
import UIKit

/// How the phone is held, as the desktop cares about it.
public enum DuoPose: String, CaseIterable, Sendable {
    /// No hinge (an iPad, an ordinary iPhone): nothing changes.
    case noHinge
    /// Shut; LinPad is on the outer screen.
    case closed
    /// Fully open, the inner screen in one piece.
    case flat
    /// Partly open in portrait, like a book: the fold runs top to bottom.
    case book
    /// Partly open in landscape, like a laptop: the fold runs left to right.
    case laptop
    /// Partly open and standing on its edges, showing the outer screen.
    case tent

    public var title: String {
        switch self {
        case .noHinge: "No hinge"
        case .closed: "Closed"
        case .flat: "Flat"
        case .book: "Book"
        case .laptop: "Laptop"
        case .tent: "Tent"
        }
    }

    /// LinPad is on the small outer screen.
    var isOuterScreen: Bool { self == .closed || self == .tent }
    /// The fold splits the inner screen.
    var isFolded: Bool { self == .book || self == .laptop }
}

/// One shared service that knows how the phone is folded (plan Phase 2). The desktop feeds
/// it the hinge, the fold region and the size of its window; everything else observes
/// `pose`. On a device without a hinge it stays `.noHinge` and nothing reacts.
///
/// Jitter: the system's hinge status already has its own thresholds, so a new pose only has
/// to hold for `settleDelay` before it counts. Moving to or from the outer screen is a
/// different screen, not a reading, and applies at once.
@Perceptible @MainActor
public final class PoseMonitor {
    /// A partial fold must hold this long before the layout follows it.
    static let settleDelay: Duration = .milliseconds(350)
    /// The outer screen's short side is 1398 pixels and the inner's 1878; a window narrower
    /// than this many pixels is on the outer screen.
    static let outerScreenPixelLimit: CGFloat = 1640

    public private(set) var pose = DuoPose.noHinge
    /// The latest hinge reading, unsmoothed (debug overlay, hinge effects).
    private(set) var hinge: DuoHingeReading?
    /// Where the fold crosses the whole window, in window coordinates.
    private(set) var foldInWindow: CGRect?
    private(set) var windowSize: CGSize = .zero
    /// Whether this device has a hinge at all (iOS reported one at least once).
    private(set) var hasHinge = false

    @PerceptionIgnored private var windowScale: CGFloat = 3
    @PerceptionIgnored private var settleTask: Task<Void, Never>?
    @PerceptionIgnored private var observers: [@MainActor (DuoPose, DuoPose) -> Void] = []

    public init() {}

    /// Called with the old and new pose after every change.
    func observe(_ observer: @escaping @MainActor (DuoPose, DuoPose) -> Void) {
        observers.append(observer)
    }

    // MARK: Inputs

    func hingeChanged(_ reading: DuoHingeReading?) {
        hinge = reading
        if reading != nil { hasHinge = true }
        evaluate()
    }

    func foldChanged(_ frame: CGRect?) {
        foldInWindow = frame
        evaluate()
    }

    func windowChanged(size: CGSize, scale: CGFloat) {
        windowSize = size
        if scale > 0 { windowScale = scale }
        evaluate()
    }

    // MARK: Deciding

    /// The window is on the small outer screen.
    var isOnOuterScreen: Bool {
        guard hasHinge, windowSize.width > 0 else { return false }
        return min(windowSize.width, windowSize.height) * windowScale < Self.outerScreenPixelLimit
    }

    private var candidate: DuoPose {
        guard hasHinge else { return .noHinge }
        let status = hinge?.status ?? .unknown
        if isOnOuterScreen {
            return status == .partiallyOpen ? .tent : .closed
        }
        if status == .partiallyOpen || foldInWindow != nil {
            if let fold = foldInWindow {
                return fold.height > fold.width ? .book : .laptop
            }
            return windowSize.height >= windowSize.width ? .book : .laptop
        }
        return .flat
    }

    private func evaluate() {
        let next = candidate
        settleTask?.cancel()
        guard next != pose else { return }
        let changesScreen = next.isOuterScreen != pose.isOuterScreen || pose == .noHinge || next == .noHinge
        if changesScreen {
            apply(next)
            return
        }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, self.candidate == next else { return }
            self.apply(next)
        }
    }

    private func apply(_ next: DuoPose) {
        let previous = pose
        withAnimation(DesktopMotion.tile) { pose = next }
        for observer in observers { observer(previous, next) }
    }

    /// "Book · 112° · partially open" for the debug overlay.
    var summary: String {
        var parts = [pose.title]
        if let hinge {
            parts.append("\(Int(hinge.angleDegrees.rounded()))°")
            parts.append(hinge.status.rawValue)
        } else if pose != .noHinge {
            parts.append("no reading yet")
        }
        if let fold = foldInWindow {
            parts.append("fold \(Int(fold.minX)),\(Int(fold.minY)) \(Int(fold.width))×\(Int(fold.height))")
        }
        parts.append("\(Int(windowSize.width))×\(Int(windowSize.height)) pt")
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// Feeds the pose monitor from the view that fills the window.
    func duoPoseTracking(_ monitor: PoseMonitor) -> some View {
        duoHingeChanges { monitor.hingeChanged($0) }
            .duoFoldChanges { monitor.foldChanged($0) }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChangeCompat(of: proxy.size, initial: true) { _, size in
                            monitor.windowChanged(size: size, scale: UIScreen.main.scale)
                        }
                }
                .accessibilityHidden(true)
            }
    }
}

/// Settings › iPhone Duo › "Show pose": what PoseMonitor thinks, at the top of the screen.
struct DuoPoseOverlay: View {
    let monitor: PoseMonitor
    @Environment(\.desktopTheme) private var theme

    var body: some View {
        WithPerceptionTracking {
            Text(monitor.summary)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(.top, 4)
                .allowsHitTesting(false)
                .accessibilityLabel("Pose: \(monitor.summary)")
        }
    }
}
