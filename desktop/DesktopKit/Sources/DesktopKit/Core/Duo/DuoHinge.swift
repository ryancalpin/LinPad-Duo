import SwiftUI

// The only file that calls the iPhone Duo APIs of the iOS 27.1 SDK (SwiftUI's
// `onHingeChange(isEnabled:_:)` and `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)`).
// Everything else reads the plain values below, so if Apple renames something, only this
// file changes. Building without these APIs: remove `.define("LINPAD_HINGE_API")` from
// Package.swift; PoseMonitor then tells closed from open by the screen size alone.

/// What the hinge reports, in LinPad's own terms.
struct DuoHingeReading: Equatable, Sendable {
    enum Status: String, Sendable {
        case closed
        case partiallyOpen
        case fullyOpen
        case unknown
    }

    /// 180 when the phone lies flat, 0 when it is shut.
    var angleDegrees: Double
    var status: Status
}

#if LINPAD_HINGE_API
@available(iOS 27.1, *)
extension DuoHingeReading {
    init(_ hinge: DeviceHinge) {
        angleDegrees = hinge.angle.degrees
        switch hinge.status {
        case .closed: status = .closed
        case .partiallyOpen: status = .partiallyOpen
        case .fullyOpen: status = .fullyOpen
        default: status = .unknown
        }
    }
}
#endif

extension View {
    /// Reports the hinge (nil on a device without one) whenever it changes. Apple's advice
    /// is to use it for interactions and effects; layout follows the fold region instead.
    @ViewBuilder
    func duoHingeChanges(_ report: @escaping @MainActor (DuoHingeReading?) -> Void) -> some View {
        #if LINPAD_HINGE_API
        if #available(iOS 27.1, *) {
            onHingeChange { _, context in
                let reading = context.hinge.map(DuoHingeReading.init)
                Task { @MainActor in report(reading) }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Reports where the fold crosses this view, in the view's own coordinates: a tall thin
    /// rectangle in book pose, a wide flat one in laptop pose, nil while the phone is flat
    /// or closed (the fold is only an active region when the phone is partly open).
    func duoFoldChanges(_ report: @escaping @MainActor (CGRect?) -> Void) -> some View {
        background { DuoFoldReader(report: report) }
    }
}

private struct DuoFoldReader: View {
    let report: @MainActor (CGRect?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fold = Self.fold(in: proxy)
            Color.clear
                .onChangeCompat(of: fold, initial: true) { _, frame in report(frame) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func fold(in proxy: GeometryProxy) -> CGRect? {
        #if LINPAD_HINGE_API
        if #available(iOS 27.1, *) {
            // Unmirrored: the desktop's own layout does not flip for right-to-left languages.
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .first { $0.isActive }?.frame
        }
        #endif
        return nil
    }
}
