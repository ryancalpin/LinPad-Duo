import UIKit
import XCTest
import DesktopTouchSynth

/// The Duo trackpad's clicks outside Linux windows are synthesized touches (DTSTouch).
@MainActor
final class DuoPointerClickTests: XCTestCase {
    /// A synthesized touch reaches the view under it. (In a unit test UIKit has no touches
    /// event of its own yet, so the touch goes to the window directly and gesture
    /// recognizers don't see it; on a device that has been touched they do.)
    func testSynthesizedTouchReachesView() async throws {
        XCTAssertTrue(DTSTouch.isAvailable)
        final class Recorder: UIView {
            var phases: [String] = []
            override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { phases.append("began") }
            override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { phases.append("ended") }
        }
        let recorder = Recorder()
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene).map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: .zero)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        let controller = UIViewController()
        controller.view = recorder
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.rootViewController = nil
            window.isHidden = true
            window.windowScene = nil
        }
        _ = DTSTouch.tap(at: CGPoint(x: 100, y: 100), in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recorder.phases, ["began", "ended"])
    }
}
