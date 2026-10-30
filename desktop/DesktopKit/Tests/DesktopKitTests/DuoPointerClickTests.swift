import SwiftUI
import UIKit
import XCTest
import DesktopTouchSynth
@testable import DesktopKit

/// The Duo trackpad presses the desktop's own controls through the accessibility tree.
/// A click must land on the control under the pointer, including in the panel above
/// the desktop area.
@MainActor
final class DuoPointerClickTests: XCTestCase {
    func testTrackpadClickPressesPanelButton() async throws {
        // Hosting the whole desktop trips Perception's "not tracked" warnings in views this
        // test doesn't exercise; they are not what it checks.
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { $0.compactDescription.contains("is not being tracked") }
        XCTExpectFailure("Perception tracking warnings from the hosted desktop", options: options)

        let controller = DesktopController(host: MockLinuxHost(latency: .zero), apps: BuiltinApps.all())
        controller.isOnboardingPresented = false
        let host = UIHostingController(rootView: DesktopRootView(controller: controller))
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene).map(UIWindow.init(windowScene:))
            ?? UIWindow(frame: .zero)
        window.frame = CGRect(x: 0, y: 0, width: 680, height: 466)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .seconds(2))
        controller.isOnboardingPresented = false
        try await Task.sleep(for: .seconds(1))

        let reference = try XCTUnwrap(controller.input.referenceView)
        let elements = (host.view.accessibilityElements ?? []).compactMap { $0 as? NSObject }
        let applications = try XCTUnwrap(elements.first { $0.accessibilityLabel == "Applications" })
        let frame = applications.accessibilityFrame
        // The panel sits above the desktop area, so the button is at a negative desktop y.
        let point = window.convert(CGPoint(x: frame.midX, y: frame.midY), to: reference)
        XCTAssertLessThan(point.y, 0)

        controller.duoPointer.place(at: point)
        controller.duoPointer.click()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(controller.isLauncherPresented, "the click should open the launcher")
    }

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
        defer { window.isHidden = true }
        XCTAssertTrue(DTSTouch.tap(at: CGPoint(x: 100, y: 100), in: window))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recorder.phases, ["began", "ended"])
    }
}
