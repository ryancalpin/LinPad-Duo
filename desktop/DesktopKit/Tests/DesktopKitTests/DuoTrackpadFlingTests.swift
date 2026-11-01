import CoreGraphics
import XCTest
@testable import DesktopKit

/// Two-finger flicks on the Duo trackpad keep the content gliding.
@MainActor
final class DuoTrackpadFlingTests: XCTestCase {
    private typealias Trackpad = DuoTrackpad.TrackpadView

    /// Fingers moving 10 pt every 60th of a second, lifting just after the last move.
    private func steadySamples(until end: TimeInterval) -> [(time: TimeInterval, delta: CGSize)] {
        (0..<12).map { (end - Double(11 - $0) / 60, CGSize(width: 0, height: -10)) }
    }

    func testFlickMeasuresFingerSpeed() {
        let velocity = Trackpad.flingVelocity(steadySamples(until: 100), at: 100.005)
        XCTAssertEqual(velocity.width, 0)
        XCTAssertEqual(velocity.height, -600, accuracy: 1)
        XCTAssertGreaterThan(hypot(velocity.width, velocity.height), DuoVirtualPointer.minimumFlingSpeed)
    }

    func testFingersThatStoppedBeforeLiftingDoNotFling() {
        XCTAssertEqual(Trackpad.flingVelocity(steadySamples(until: 100), at: 100.08), .zero)
        XCTAssertEqual(Trackpad.flingVelocity([], at: 100), .zero)
        XCTAssertEqual(Trackpad.flingVelocity([(100, CGSize(width: 0, height: 40))], at: 100.01), .zero)
    }

    func testGlideSlowsLikeAScrollView() {
        let start = CGSize(width: 0, height: 1000)
        XCTAssertEqual(DuoVirtualPointer.decayed(start, after: 0), start)
        let later = DuoVirtualPointer.decayed(start, after: 1)
        XCTAssertEqual(later.height, 1000 * pow(0.998, 1000), accuracy: 1)
        XCTAssertLessThan(DuoVirtualPointer.decayed(start, after: 2).height, later.height)
    }
}
