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
}
