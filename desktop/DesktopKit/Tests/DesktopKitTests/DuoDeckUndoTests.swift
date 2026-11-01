import XCTest
@testable import DesktopKit

@MainActor
final class DuoDeckUndoTests: XCTestCase {
    func testUndoAndRedoArePickable() {
        XCTAssertTrue(DuoDeckAction.builtIn.contains(.undo))
        XCTAssertTrue(DuoDeckAction.builtIn.contains(.redo))
        XCTAssertEqual(DuoDeckAction.undo.title(in: nil), "Undo")
        XCTAssertEqual(DuoDeckAction.redo.title(in: nil), "Redo")
        XCTAssertEqual(DuoDeckAction.undo.symbol(in: nil), "arrow.uturn.backward")
        XCTAssertEqual(DuoDeckAction.redo.symbol(in: nil), "arrow.uturn.forward")
    }

    func testUndoSurvivesSaving() throws {
        let data = try JSONEncoder().encode([DuoDeckAction.undo, .redo])
        XCTAssertEqual(try JSONDecoder().decode([DuoDeckAction].self, from: data), [.undo, .redo])
    }

    func testTerminalAppsAreRecognized() {
        XCTAssertTrue(DuoKeyboardModel.isTerminal(appID: AppID.terminal))
        XCTAssertTrue(DuoKeyboardModel.isTerminal(appID: LinuxAppID.prefix + "foot"))
        XCTAssertTrue(DuoKeyboardModel.isTerminal(appID: LinuxAppID.prefix + "footclient"))
        XCTAssertFalse(DuoKeyboardModel.isTerminal(appID: LinuxAppID.prefix + "firefox"))
        XCTAssertFalse(DuoKeyboardModel.isTerminal(appID: AppID.files))
    }

    /// Guest programs that ish-terminal runs under their own app id (the Document Scanner).
    func testProgramsRunInTheTerminalAreRecognized() {
        XCTAssertTrue(DuoKeyboardModel.runsInTerminal(
            command: "ish-terminal --app-id=linpad-scan --title=\"Document Scanner\" linpad-scan"))
        XCTAssertTrue(DuoKeyboardModel.runsInTerminal(command: "/usr/bin/ish-terminal"))
        XCTAssertFalse(DuoKeyboardModel.runsInTerminal(command: "firefox-esr"))
        XCTAssertFalse(DuoKeyboardModel.runsInTerminal(command: "ish-terminal-helper"))
        XCTAssertFalse(DuoKeyboardModel.runsInTerminal(command: ""))

        let controller = DesktopController(host: MockLinuxHost(latency: .zero), apps: BuiltinApps.all())
        XCTAssertTrue(controller.isTerminal(appID: AppID.terminal), "the app id check still applies")
        XCTAssertFalse(controller.isTerminal(appID: LinuxAppID.prefix + "linpad-scan"), "no Linux session, no entries")
    }
}
