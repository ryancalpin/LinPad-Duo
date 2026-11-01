import XCTest
@testable import DesktopKit

@MainActor
final class DuoTypingFocusTests: XCTestCase {
    private let typingA = DuoTypingSignal(isTyping: true, target: "field:a")
    private let typingB = DuoTypingSignal(isTyping: true, target: "field:b")
    private let idleWindow = DuoTypingSignal(isTyping: false, target: "window:1")
    private let idleOther = DuoTypingSignal(isTyping: false, target: "window:2")

    private func settle() async throws { try await Task.sleep(for: .milliseconds(120)) }

    func testTypingShowsTheKeyboardAtOnce() {
        let focus = DuoTypingFocus(hideDelay: .milliseconds(50))
        XCTAssertFalse(focus.showsKeyboard)
        focus.update(typingA)
        XCTAssertTrue(focus.showsKeyboard)
    }

    func testStoppingHidesItAfterTheDelay() async throws {
        let focus = DuoTypingFocus(hideDelay: .milliseconds(50))
        focus.update(typingA)
        focus.update(idleWindow)
        XCTAssertTrue(focus.showsKeyboard, "waits before hiding")
        try await settle()
        XCTAssertFalse(focus.showsKeyboard)
    }

    func testMovingBetweenFieldsDoesNotFlicker() async throws {
        let focus = DuoTypingFocus(hideDelay: .milliseconds(50))
        focus.update(typingA)
        focus.update(idleWindow)
        focus.update(typingB)
        try await settle()
        XCTAssertTrue(focus.showsKeyboard)
    }

    func testButtonOpensItUntilTheFocusMoves() async throws {
        let focus = DuoTypingFocus(hideDelay: .milliseconds(50))
        focus.update(idleWindow)
        focus.toggleKeyboard()
        XCTAssertTrue(focus.showsKeyboard)
        focus.update(idleWindow)
        try await settle()
        XCTAssertTrue(focus.showsKeyboard, "same target: the override holds")
        focus.update(idleOther)
        try await settle()
        XCTAssertFalse(focus.showsKeyboard, "new target: automatic again")
    }

    func testButtonClosesItWhileTyping() {
        let focus = DuoTypingFocus(hideDelay: .milliseconds(50))
        focus.update(typingA)
        focus.toggleKeyboard()
        XCTAssertFalse(focus.showsKeyboard, "a manual close is immediate")
        focus.update(typingA)
        XCTAssertFalse(focus.showsKeyboard)
        focus.update(typingB)
        XCTAssertTrue(focus.showsKeyboard)
    }

    func testSignalFromAnEditingField() {
        let field = ObjectIdentifier(NSObject())
        let signal = DuoTypingSignal.make(editingField: field, focusedWindowID: UUID(), focusedAppID: AppID.files,
                                          focusedLinuxSurface: nil, textInputSurface: nil)
        XCTAssertTrue(signal.isTyping)
    }

    func testSignalFromTerminalAndLinuxTextBoxes() {
        let window = UUID()
        let terminal = DuoTypingSignal.make(editingField: nil, focusedWindowID: window, focusedAppID: AppID.terminal,
                                            focusedLinuxSurface: nil, textInputSurface: nil)
        XCTAssertTrue(terminal.isTyping)
        let box = DuoTypingSignal.make(editingField: nil, focusedWindowID: window, focusedAppID: LinuxAppID.prefix + "firefox",
                                       focusedLinuxSurface: 7, textInputSurface: 7)
        XCTAssertTrue(box.isTyping)
        let page = DuoTypingSignal.make(editingField: nil, focusedWindowID: window, focusedAppID: LinuxAppID.prefix + "firefox",
                                        focusedLinuxSurface: 7, textInputSurface: nil)
        XCTAssertFalse(page.isTyping)
        XCTAssertNotEqual(box.target, page.target, "leaving a text box counts as the focus moving")
        let nothing = DuoTypingSignal.make(editingField: nil, focusedWindowID: nil, focusedAppID: nil,
                                           focusedLinuxSurface: nil, textInputSurface: nil)
        XCTAssertEqual(nothing, DuoTypingSignal())
    }
}
