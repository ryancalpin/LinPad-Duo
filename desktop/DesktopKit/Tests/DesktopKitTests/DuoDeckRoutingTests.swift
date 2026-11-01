import UIKit
import XCTest
@testable import DesktopKit

/// Where the deck's keys and actions go.
@MainActor
final class DuoDeckRoutingTests: XCTestCase {
    private func makeController() -> DesktopController {
        DesktopController(host: MockLinuxHost(latency: .zero), apps: BuiltinApps.all())
    }

    private func present(_ appID: String, in controller: DesktopController) -> DesktopWindow {
        let window = controller.windowManager.makeWindow(appID: appID, symbol: "macwindow", title: appID,
                                                         preferredSize: CGSize(width: 400, height: 300))
        controller.windowManager.present(window)
        return window
    }

    /// The launcher's search box clicked while Firefox has focus: the field gets the keys.
    /// (A unit test has no window scene, so UIKit can't find the live first responder;
    /// it is passed in.)
    func testDesktopTextFieldTakesTheKeysFromTheFocusedLinuxWindow() {
        let controller = makeController()
        let firefox = present("linux:firefox", in: controller)
        controller.linuxWindows[7] = firefox.id
        XCTAssertEqual(controller.deckLinuxTarget(firstResponder: nil), 7)
        XCTAssertEqual(controller.deckLinuxTarget(firstResponder: UIView()), 7, "not a text field")
        XCTAssertNil(controller.deckLinuxTarget(firstResponder: UITextField()), "a desktop field being edited comes first")
        XCTAssertNil(controller.deckLinuxTarget(firstResponder: UITextView()))

        _ = present("files", in: controller)
        XCTAssertNil(controller.deckLinuxTarget(firstResponder: nil), "not a Linux window")
    }
}
