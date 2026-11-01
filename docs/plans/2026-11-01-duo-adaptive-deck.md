# Adaptive Laptop Deck Implementation Plan

> Execute with rc-subagent-execution, task by task. Steps use `- [ ]` checkboxes.

**Goal:** Add the Adaptive deck layout from `docs/superpowers/specs/2026-11-01-duo-adaptive-deck-design.md`.
- A big trackpad while nothing is being typed.
- A keyboard plus a smaller trackpad while something is.
- A manual keyboard button.
- A Settings choice between Adaptive (the default) and Classic.

**Architecture:**
- `DuoTypingFocus` is a small state machine. It turns a `DuoTypingSignal` and keyboard-button presses into `showsKeyboard`.
  - The signal says whether a text field is being edited, a terminal is focused, or a Linux text box is focused.
- `DuoAdaptiveDeck` is a new SwiftUI view that reads `showsKeyboard`.
- `DuoInputDeck` switches between it and today's deck (Classic) on a stored `DuoDeckStyle`.

**Tech stack:**
- Swift 6, SwiftUI with Perception (`@Perceptible`, `WithPerceptionTracking`), UIKit, XCTest.
- DesktopKit Swift package at `desktop/DesktopKit`.

## Global Constraints
- Settings › Laptop Keyboard gets a Layout choice: Adaptive or Classic. Adaptive is the default; Classic is today's deck, unchanged.
- The keyboard appears automatically on text focus, plus a manual keyboard button that overrides either way.
- The override lasts until the typing target changes (a different field or window gets focus, or focus leaves); then automatic behavior resumes.
- The keyboard waits 0.3 s after focus leaves before hiding. Showing is immediate.
- Hardware keyboard attached: never show the keyboard; the ⌨︎ and fn buttons are hidden.
- Undo/Redo do nothing in the terminal (Ctrl+Z there would suspend the running program).
- 44×44 pt minimum tap targets, SF Symbols, Dynamic Type on labels (key caps keep today's sizing).
- Reduce Motion: cross-fade instead of slide. Haptics only for ⌨︎-button changes, not automatic ones.
- Builds: `cd desktop/DesktopKit && xcodebuild build -skipMacroValidation -scheme DesktopKit -destination 'generic/platform=iOS Simulator'`.
- Covering tests: `cd desktop/DesktopKit && xcodebuild test -skipMacroValidation -scheme DesktopKit -destination 'platform=iOS Simulator,id=D396AB49-CB12-4AF5-B0BC-86131B854E07' -only-testing:DesktopKitTests/<Class>`. Run in the foreground; trust `** TEST SUCCEEDED **` and the executed count, not process lists.
- Don't host `DesktopRootView` in tests: it leaks Perception "not tracked" warnings into later tests.
- Don't commit `desktop/DesktopKit/Package.resolved`; it's an unrelated local change.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branch `duo`. Don't push; the controller pushes at the end.

## File map

| File | Change |
|---|---|
| `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoDeckCustomization.swift` | Undo/Redo actions; `DuoDeckStyle`; Layout picker in `DuoDeckSettingsSection` |
| `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoKeyboard.swift` | Undo/Redo routing in `DuoKeyboardModel.perform` |
| `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoTypingFocus.swift` | New: `DuoTypingSignal`, `DuoTypingFocus`, `DesktopController.duoTypingSignal` |
| `desktop/DesktopKit/Sources/DesktopKit/Core/OnScreenKeyboard.swift` | Observable `editingField` |
| `desktop/DesktopKit/Sources/DesktopKit/Linux/LinuxGUIBridge.swift` | `textInputSurfaceID` becomes observable, readable |
| `desktop/DesktopKit/Sources/DesktopKit/Core/DesktopController.swift` | Own `duoTypingFocus` |
| `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoAdaptiveDeck.swift` | New: `DuoAdaptiveColumns`, `DuoAdaptiveDeck` |
| `desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoInputDeck.swift` | Switch Classic/Adaptive on `DuoDeckStyle` |
| `desktop/DesktopKit/Tests/DesktopKitTests/DuoDeckUndoTests.swift` | New |
| `desktop/DesktopKit/Tests/DesktopKitTests/DuoTypingFocusTests.swift` | New |
| `desktop/DesktopKit/Tests/DesktopKitTests/DuoAdaptiveDeckTests.swift` | New: column fitting and an opt-in snapshot test |

---

### Task 1: Undo and Redo deck actions

**Files:** Modify `Core/Duo/DuoDeckCustomization.swift` · Modify `Core/Duo/DuoKeyboard.swift` · Test `Tests/DesktopKitTests/DuoDeckUndoTests.swift`

**Interfaces:**
- Produces: `DuoDeckAction.undo`, `DuoDeckAction.redo`, both listed in `DuoDeckAction.builtIn`.
  - `DuoKeyboardModel.perform(.undo / .redo)`.
  - `static func DuoKeyboardModel.isTerminal(appID: String) -> Bool`, which Task 2 reuses.

- [ ] Write the failing test:

```swift
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
        XCTAssertFalse(DuoKeyboardModel.isTerminal(appID: LinuxAppID.prefix + "firefox"))
        XCTAssertFalse(DuoKeyboardModel.isTerminal(appID: AppID.files))
    }
}
```

- [ ] Run it and confirm it fails:
  - Command: `-only-testing:DesktopKitTests/DuoDeckUndoTests`.
  - Expected: a compile error, "type 'DuoDeckAction' has no member 'undo'".

- [ ] Implement:
  - **Cases.** In `DuoDeckCustomization.swift`, change the keys line to:
    - `case returnKey, escapeKey, tabKey, interrupt, pasteText, undo, redo`.
  - **Pickers.** Add `.undo, .redo` to `builtIn` right after `.pasteText`.
  - **`title(in:)`:**
    - `case .undo: "Undo"`
    - `case .redo: "Redo"`
  - **`symbol(in:)`:**
    - `case .undo: "arrow.uturn.backward"`
    - `case .redo: "arrow.uturn.forward"`
  - **Other switches:** fix any other exhaustive `switch` over `DuoDeckAction` that the compiler flags.
  - **Routing.** In `DuoKeyboard.swift`, inside `perform(_:)`, add before `case .terminal:`:

```swift
        case .undo, .redo:
            undoOrRedo(redo: action == .redo)
```

  and add to `DuoKeyboardModel` (after `perform`):

```swift
    /// Undo and Redo: Ctrl+Z and Ctrl+Shift+Z in a Linux window, the text field's own undo in
    /// the desktop's fields. Nothing in a terminal, where Ctrl+Z suspends the running program.
    private func undoOrRedo(redo: Bool) {
        guard let controller else { return }
        if let appID = controller.windowManager.focusedWindow?.appID, Self.isTerminal(appID: appID) { return }
        if linuxTarget != nil {
            modifiers[.control] = .latched
            if redo { modifiers[.shift] = .latched }
            let key = DuoKey.char(44, "z", "Z")
            press(key)
            release(key)
        } else if let manager = UIResponder.desktopCurrentFirstResponder?.undoManager {
            if redo { manager.redo() } else { manager.undo() }
        }
    }

    /// The built-in Terminal app, or foot in the Linux session.
    static func isTerminal(appID: String) -> Bool {
        appID == AppID.terminal || appID == LinuxAppID.prefix + "foot"
    }
```

  - **Check foot's id:** confirm that Linux windows for foot really get the window `appID` `"linux:foot"`.
    - Search for `LinuxAppID.prefix` in `Linux/DesktopController+Linux.swift` and wherever Linux toplevels open windows.
    - If foot's desktop id differs, use the real one and update the test.

- [ ] Run the covering tests and confirm they pass:
  - `-only-testing:DesktopKitTests/DuoDeckUndoTests`.
  - Also `-only-testing:DesktopKitTests/DuoTests`, which covers deck actions.

- [ ] Commit:
  - Message: `Deck actions: Undo and Redo (Ctrl+Z / Ctrl+Shift+Z in Linux, the field's own undo elsewhere, nothing in a terminal)`.

### Task 2: Typing focus state machine and its signals

**Files:** Create `Core/Duo/DuoTypingFocus.swift` · Modify `Core/OnScreenKeyboard.swift` · Modify `Linux/LinuxGUIBridge.swift` · Modify `Core/DesktopController.swift` · Test `Tests/DesktopKitTests/DuoTypingFocusTests.swift`

**Interfaces:**
- Consumes: `DuoKeyboardModel.isTerminal(appID:)` from Task 1.
- Produces:
  - `struct DuoTypingSignal: Equatable { var isTyping: Bool; var target: String? }`.
  - `static func make(editingField:focusedWindowID:focusedAppID:focusedLinuxSurface:textInputSurface:)`.
  - `@Perceptible @MainActor final class DuoTypingFocus`:
    - `init(hideDelay: Duration = .milliseconds(300))`
    - `private(set) var showsKeyboard: Bool`
    - `func update(_ signal: DuoTypingSignal)`
    - `func toggleKeyboard()`
  - `DesktopController.duoTypingFocus` (a `let`).
  - `DesktopController.duoTypingSignal` (computed).
  - `OnScreenKeyboard.editingField: ObjectIdentifier?`.
  - `LinuxGUIBridge.textInputSurfaceID: UInt32?` (`private(set)`, observable).

- [ ] Write the failing test:

```swift
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
```

- [ ] Run it and confirm it fails:
  - Command: `-only-testing:DesktopKitTests/DuoTypingFocusTests`.
  - Expected: a compile error, "cannot find 'DuoTypingFocus' in scope".

- [ ] Implement. Create `Core/Duo/DuoTypingFocus.swift`:

```swift
import Foundation
import Perception

/// What has focus, for the Adaptive deck's keyboard: whether it takes typing (a desktop text
/// field being edited, a terminal, a Linux text box) and a name for it, so a change of focus
/// can end a manual override.
struct DuoTypingSignal: Equatable {
    var isTyping = false
    var target: String?

    static func make(editingField: ObjectIdentifier?, focusedWindowID: UUID?, focusedAppID: String?,
                     focusedLinuxSurface: UInt32?, textInputSurface: UInt32?) -> DuoTypingSignal {
        if let editingField { return DuoTypingSignal(isTyping: true, target: "field:\(editingField)") }
        guard let focusedWindowID else { return DuoTypingSignal() }
        let linuxText = focusedLinuxSurface != nil && focusedLinuxSurface == textInputSurface
        let terminal = focusedAppID.map(DuoKeyboardModel.isTerminal(appID:)) ?? false
        return DuoTypingSignal(isTyping: linuxText || terminal,
                               target: "window:\(focusedWindowID.uuidString)" + (linuxText ? ":text" : ""))
    }
}

/// Whether the Adaptive deck shows its keyboard. It follows the typing signal, showing at
/// once when typing starts and hiding a moment after it stops, so moving between two fields
/// doesn't flicker. The keyboard button overrides it until the focus moves somewhere else.
@Perceptible @MainActor
final class DuoTypingFocus {
    private(set) var showsKeyboard = false
    @PerceptionIgnored private var signal = DuoTypingSignal()
    @PerceptionIgnored private var override: Bool?
    @PerceptionIgnored private var hideTask: Task<Void, Never>?
    @PerceptionIgnored private let hideDelay: Duration

    init(hideDelay: Duration = .milliseconds(300)) {
        self.hideDelay = hideDelay
    }

    func update(_ signal: DuoTypingSignal) {
        if signal.target != self.signal.target { override = nil }
        self.signal = signal
        apply()
    }

    /// The keyboard button: the opposite of what shows, until the focus moves.
    func toggleKeyboard() {
        override = !showsKeyboard
        apply()
    }

    private func apply() {
        hideTask?.cancel()
        hideTask = nil
        let wanted = override ?? signal.isTyping
        guard !wanted, showsKeyboard else {
            showsKeyboard = wanted
            return
        }
        // Closed with the button: at once.
        guard override == nil else {
            showsKeyboard = false
            return
        }
        hideTask = Task { [weak self, hideDelay] in
            try? await Task.sleep(for: hideDelay)
            guard !Task.isCancelled else { return }
            self?.showsKeyboard = false
        }
    }
}

extension DesktopController {
    /// What the Adaptive deck's keyboard follows.
    var duoTypingSignal: DuoTypingSignal {
        let focused = windowManager.focusedWindowID
        return DuoTypingSignal.make(
            editingField: OnScreenKeyboard.shared.editingField,
            focusedWindowID: focused,
            focusedAppID: windowManager.focusedWindow?.appID,
            focusedLinuxSurface: focused.flatMap { id in linuxWindows.first { $0.value == id }?.key },
            textInputSurface: linux?.textInputSurfaceID)
    }
}
```

  - **`OnScreenKeyboard.swift`:**
    - Add `private(set) var editingField: ObjectIdentifier?` next to `isLaptopDeckShown`, with the doc comment `/// The desktop text field or view being edited, for the Adaptive deck.`
    - In the begin-editing observer, set `self.editingField = ObjectIdentifier(responder)` *before* the `suppressesSystemKeyboard` guard. Restructure the guard so the field is recorded whether or not the placeholder is set.
    - In the end-editing observer, add `if self.editingField == ObjectIdentifier(responder) { self.editingField = nil }`.
  - **`LinuxGUIBridge.swift`:**
    - Change `@PerceptionIgnored private var textInputSurfaceID: UInt32?` to `private(set) var textInputSurfaceID: UInt32?`.
    - This makes it observable and readable. The class is `@Perceptible`.
  - **`DesktopController.swift`:** after `let duoKeyboard = DuoKeyboardModel()` (around line 96), add `let duoTypingFocus = DuoTypingFocus()`.

- [ ] Build:
  - `xcodebuild build … -destination 'generic/platform=iOS Simulator'`.
  - Expect `** BUILD SUCCEEDED **`.

- [ ] Run the covering tests and confirm they pass:
  - `-only-testing:DesktopKitTests/DuoTypingFocusTests`.
  - `-only-testing:DesktopKitTests/KeyboardAvoidanceTests`, which touches OnScreenKeyboard.

- [ ] Commit:
  - Message: `Duo: typing focus for the Adaptive deck (text fields, terminals, Linux text boxes; button override; 0.3 s hide delay)`.

### Task 3: Adaptive deck view, the Layout setting, and the Classic/Adaptive switch

**Files:** Create `Core/Duo/DuoAdaptiveDeck.swift` · Modify `Core/Duo/DuoInputDeck.swift` · Modify `Core/Duo/DuoDeckCustomization.swift` · Test `Tests/DesktopKitTests/DuoAdaptiveDeckTests.swift`

**Interfaces:**
- Consumes:
  - `DuoTypingFocus`, `DesktopController.duoTypingFocus` and `DesktopController.duoTypingSignal` (Task 2).
  - `DuoDeckAction.undo/.redo` (Task 1).
  - Existing:
    - `DuoKeyboardView(model:)`
    - `DuoMicButton(dictation:mode:size:)`
    - `DuoTrackpad(pointer:)`
    - `DuoDeckColors`
    - `DuoDeckLayout.shared` (`leftButtons`, `rightButtons`, `micMode`)
    - `DuoKeyboardModel.perform(_:)`
    - `functionKeysLocked`
    - `SettingsApp.shortcutsPage/deckPage/duoPage`
    - `LinuxKeyboardLayouts.storageKey/automatic`
    - `DesktopMotion.standard`
- Produces:
  - `enum DuoDeckStyle: String, CaseIterable, Identifiable { case adaptive, classic }` with `storageKey = "duo.deck.style"`.
  - `enum DuoAdaptiveColumns` with `static func fit(left:right:height:) -> Fit`.
  - `struct DuoAdaptiveDeck: View` with `init(controller:showsKeyboard:)`.

- [ ] Write the failing test:

```swift
import SwiftUI
import UIKit
import XCTest
@testable import DesktopKit

@MainActor
final class DuoAdaptiveDeckTests: XCTestCase {
    private let left: [DuoDeckAction] = [.terminal, .files, .none]
    private let right: [DuoDeckAction] = [.returnKey, .commandMenu, .none]

    func testTallPadFitsEveryButton() {
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 200)
        XCTAssertEqual(fit.left, [.terminal, .files])
        XCTAssertEqual(fit.right, [.returnKey, .commandMenu])
        XCTAssertEqual(fit.overflow, [])
    }

    func testShortPadMovesButtonsIntoMore() {
        // Two 44 pt slots: the mic or "…" plus one custom button per column.
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 96)
        XCTAssertEqual(fit.left, [.terminal])
        XCTAssertEqual(fit.right, [.returnKey])
        XCTAssertEqual(fit.overflow, [.files, .commandMenu])
    }

    func testTinyPadKeepsOnlyMicAndMore() {
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 30)
        XCTAssertEqual(fit.left, [])
        XCTAssertEqual(fit.right, [])
        XCTAssertEqual(fit.overflow, [.terminal, .files, .returnKey, .commandMenu])
    }

    func testAdaptiveIsTheDefaultStyle() {
        XCTAssertEqual(DuoDeckStyle.allCases.first, .adaptive)
        XCTAssertEqual(DuoDeckStyle.storageKey, "duo.deck.style")
    }

    /// Renders the deck in both states to PNGs for a visual check. Opt-in, because it hosts
    /// SwiftUI in a window: set TEST_RUNNER_DECK_SNAPSHOT_DIR when running xcodebuild.
    func testSnapshots() async throws {
        guard let directory = ProcessInfo.processInfo.environment["DECK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_DECK_SNAPSHOT_DIR to render deck snapshots")
        }
        let controller = DesktopController(host: MockLinuxHost(latency: .zero), apps: BuiltinApps.all())
        let sizes = [("laptop", CGSize(width: 951, height: 320)), ("narrow", CGSize(width: 466, height: 300)),
                     ("monitor", CGSize(width: 669, height: 900))]
        for (name, size) in sizes {
            for typing in [false, true] {
                if controller.duoTypingFocus.showsKeyboard != typing { controller.duoTypingFocus.toggleKeyboard() }
                let host = UIHostingController(rootView: DuoAdaptiveDeck(controller: controller, showsKeyboard: true)
                    .background(DuoDeckColors.background).environment(\.colorScheme, .dark))
                let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene).map(UIWindow.init(windowScene:))
                    ?? UIWindow(frame: .zero)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(400))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                }
                let url = URL(fileURLWithPath: directory).appendingPathComponent("deck-\(name)-\(typing ? "typing" : "idle").png")
                try XCTUnwrap(image.pngData()).write(to: url)
                window.rootViewController = nil
                window.isHidden = true
                window.windowScene = nil
            }
        }
    }
}
```

- [ ] Run it and confirm it fails:
  - Command: `-only-testing:DesktopKitTests/DuoAdaptiveDeckTests`.
  - Expected: a compile error, "cannot find 'DuoAdaptiveColumns' in scope".

- [ ] Implement `DuoDeckStyle`. In `DuoDeckCustomization.swift`, above `DuoDeckLayout`:

```swift
/// The deck's layout (Settings › Laptop Keyboard › Layout).
enum DuoDeckStyle: String, CaseIterable, Identifiable {
    /// A big trackpad; the keyboard slides in while something is being typed.
    case adaptive
    /// The keyboard, or the trackpad in its place; the bottom bar's hand button switches.
    case classic

    static let storageKey = "duo.deck.style"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: "Adaptive"
        case .classic: "Classic"
        }
    }

    var explanation: String {
        switch self {
        case .adaptive: "A big trackpad. The keyboard slides in when you click into a text box or the terminal; the keyboard button at the top right shows or hides it anytime."
        case .classic: "The keyboard, or the trackpad in its place. The hand button in the bottom bar switches."
        }
    }
}
```

- [ ] Implement the Settings picker. In `DuoDeckSettingsSection`:
  - **Storage:** add `@AppStorage(DuoDeckStyle.storageKey) private var style = DuoDeckStyle.adaptive`.
  - **Picker.** Insert right after the first caption `Text("The on-screen keyboard in laptop pose…")`:

```swift
                SettingsRow(title: "Layout") {
                    Picker("Layout", selection: $style) {
                        ForEach(DuoDeckStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.deck.style")
                }
                Text(style.explanation)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
```

  - **Headers:** make the two button-group headers depend on the style:
    - `style == .adaptive ? "Beside the trackpad, under the mic" : "Bottom bar, left of the mic"`.
    - `style == .adaptive ? "Beside the trackpad, above More" : "Bottom bar, right of the mic"`.

- [ ] Implement `Core/Duo/DuoAdaptiveDeck.swift`:

```swift
import Perception
import SwiftUI
import UIKit

/// How many buttons fit in each column beside the Adaptive deck's trackpad. The mic heads
/// the left column and More ends the right one; custom buttons that don't fit go in More.
enum DuoAdaptiveColumns {
    static let button: CGFloat = 44
    static let spacing: CGFloat = 8

    struct Fit: Equatable {
        var left: [DuoDeckAction]
        var right: [DuoDeckAction]
        var overflow: [DuoDeckAction]
    }

    static func fit(left: [DuoDeckAction], right: [DuoDeckAction], height: CGFloat) -> Fit {
        let slots = max(Int((height + spacing) / (button + spacing)), 1)
        let custom = slots - 1
        let leftActions = left.filter { $0 != .none }
        let rightActions = right.filter { $0 != .none }
        return Fit(left: Array(leftActions.prefix(custom)), right: Array(rightActions.prefix(custom)),
                   overflow: Array(leftActions.dropFirst(custom)) + Array(rightActions.dropFirst(custom)))
    }
}

/// The Adaptive deck (Settings › Laptop Keyboard › Layout): a big trackpad while nothing is
/// being typed, and the keyboard with a laptop-sized trackpad under it while something is
/// (DuoTypingFocus). A shortcut row runs along the top; the mic and the custom buttons sit
/// beside the trackpad, and More holds the rest.
struct DuoAdaptiveDeck: View {
    let controller: DesktopController
    /// False with a hardware keyboard: the keys never show.
    let showsKeyboard: Bool
    @AppStorage(LinuxKeyboardLayouts.storageKey) private var layoutID = LinuxKeyboardLayouts.automatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let layout = DuoDeckLayout.shared
    private static let rowHeight: CGFloat = 44
    private static let minimumPad: CGFloat = 80

    var body: some View {
        WithPerceptionTracking {
            let keysShown = showsKeyboard && controller.duoTypingFocus.showsKeyboard
            GeometryReader { proxy in
                let spacing: CGFloat = 6
                let available = max(proxy.size.height - 12 - Self.rowHeight - spacing, 0)
                // The small pad keeps at least 80 pt; the keys give way first.
                let padHeight = keysShown ? min(max(available * 0.38, Self.minimumPad), available) : available
                let keyboardHeight = max(available - padHeight - spacing, 0)
                VStack(spacing: spacing) {
                    shortcutRow(keysShown: keysShown)
                        .frame(height: Self.rowHeight)
                    if keysShown {
                        DuoKeyboardView(model: controller.duoKeyboard)
                            .frame(height: keyboardHeight)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    padRow(height: padHeight, width: proxy.size.width - 20, compact: keysShown)
                        .frame(height: padHeight)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .animation(reduceMotion ? nil : DesktopMotion.standard, value: keysShown)
            }
            .onChangeCompat(of: controller.duoTypingSignal, initial: true) { _, signal in
                controller.duoTypingFocus.update(signal)
            }
        }
    }

    // MARK: Shortcut row

    private func shortcutRow(keysShown: Bool) -> some View {
        let keyboard = controller.duoKeyboard
        return HStack(spacing: 6) {
            shortcut("esc", symbol: nil, label: "Escape") { keyboard.perform(.escapeKey) }
            shortcut("Search", symbol: "magnifyingglass") { keyboard.perform(.launcher) }
            shortcut("All Windows", symbol: "rectangle.3.group") { keyboard.perform(.overview) }
            shortcut("Undo", symbol: "arrow.uturn.backward") { keyboard.perform(.undo) }
            shortcut("Redo", symbol: "arrow.uturn.forward") { keyboard.perform(.redo) }
            if keysShown {
                shortcut("fn", symbol: nil, label: "Function keys", isOn: keyboard.functionKeysLocked) {
                    keyboard.functionKeysLocked.toggle()
                }
            }
            if showsKeyboard {
                shortcut(nil, symbol: "keyboard", label: keysShown ? "Hide keyboard" : "Show keyboard", isOn: keysShown) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    controller.duoTypingFocus.toggleKeyboard()
                }
                .accessibilityIdentifier("duo.deck.keyboardToggle")
            }
        }
    }

    private func shortcut(_ title: String?, symbol: String?, label: String? = nil, isOn: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Narrow decks drop the words and keep the icon.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    if let symbol { Image(systemName: symbol) }
                    if let title { Text(title).lineLimit(1) }
                }
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "").lineLimit(1).minimumScaleFactor(0.6) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : DuoDeckColors.label)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isOn ? DuoDeckColors.accent : DuoDeckColors.key))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Trackpad and its columns

    private func padRow(height: CGFloat, width: CGFloat, compact: Bool) -> some View {
        let fit = DuoAdaptiveColumns.fit(left: layout.leftButtons, right: layout.rightButtons, height: height)
        return HStack(spacing: 10) {
            column {
                DuoMicButton(dictation: controller.duoDictation, mode: layout.micMode, size: DuoAdaptiveColumns.button)
                ForEach(Array(fit.left.enumerated()), id: \.offset) { _, action in sideButton(action) }
            }
            trackpad(showsHint: !compact)
                .frame(maxWidth: compact ? width * 0.6 : .infinity)
            column {
                ForEach(Array(fit.right.enumerated()), id: \.offset) { _, action in sideButton(action) }
                moreMenu(overflow: fit.overflow)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: DuoAdaptiveColumns.spacing) { content() }
            .frame(width: DuoAdaptiveColumns.button)
    }

    private func sideButton(_ action: DuoDeckAction) -> some View {
        Button {
            controller.duoKeyboard.perform(action)
        } label: {
            Image(systemName: action.symbol(in: controller))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DuoDeckColors.label)
                .frame(width: DuoAdaptiveColumns.button, height: DuoAdaptiveColumns.button)
                .background(Circle().fill(DuoDeckColors.key))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title(in: controller))
        .contextMenu {
            Button {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.deckPage])
            } label: {
                Label("Customize Keyboard…", systemImage: "slider.horizontal.3")
            }
        }
    }

    private func moreMenu(overflow: [DuoDeckAction]) -> some View {
        Menu {
            Button {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.shortcutsPage])
            } label: {
                Label("Keyboard Layout: \(layoutName)", systemImage: "globe")
            }
            Button {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.deckPage])
            } label: {
                Label("Customize Keyboard…", systemImage: "slider.horizontal.3")
            }
            Button {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.duoPage])
            } label: {
                Label("iPhone Duo Settings", systemImage: "gearshape")
            }
            if !overflow.isEmpty {
                Divider()
                ForEach(Array(overflow.enumerated()), id: \.offset) { _, action in
                    Button {
                        controller.duoKeyboard.perform(action)
                    } label: {
                        Label(action.title(in: controller), systemImage: action.symbol(in: controller))
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DuoDeckColors.label)
                .frame(width: DuoAdaptiveColumns.button, height: DuoAdaptiveColumns.button)
                .background(Circle().fill(DuoDeckColors.key))
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("duo.deck.more")
    }

    private var layoutName: String {
        layoutID == LinuxKeyboardLayouts.automatic ? "Automatic" : layoutID.uppercased()
    }

    private func trackpad(showsHint: Bool) -> some View {
        DuoTrackpad(pointer: controller.duoPointer)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DuoDeckColors.key))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(alignment: .bottom) {
                if showsHint {
                    Text("One finger moves · tap clicks · two-finger tap right-clicks · two fingers scroll")
                        .font(.caption2)
                        .foregroundStyle(DuoDeckColors.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
```

- [ ] Implement the switch in `DuoInputDeck.swift`:
  - **Storage:** add `@AppStorage(DuoDeckStyle.storageKey) private var style = DuoDeckStyle.adaptive`.
  - **Rename:** today's `GeometryReader { … }` (everything inside `WithPerceptionTracking` before `.background`) becomes `private var classicDeck: some View`.
  - **New `body`:**

```swift
    var body: some View {
        WithPerceptionTracking {
            Group {
                // Adaptive needs the trackpad; with a mouse attached (monitor mode) Classic's
                // keyboard-only deck is the right one.
                if style == .adaptive && showsTrackpad {
                    DuoAdaptiveDeck(controller: controller, showsKeyboard: showsKeyboard)
                } else {
                    classicDeck
                }
            }
            .background(DuoDeckColors.background.ignoresSafeArea())
            .overlay(alignment: .top) { DuoDictationBubble(dictation: controller.duoDictation).offset(y: -56) }
            .environment(\.colorScheme, .dark)
            .onAppear { controller.duoPointer.show() }
            .onDisappear { controller.duoPointer.hide() }
        }
    }
```

  - **Doc comment:** update the struct's doc comment to say there are two layouts (Classic described as today; Adaptive in `DuoAdaptiveDeck`).

- [ ] Build:
  - `xcodebuild build … -destination 'generic/platform=iOS Simulator'`.
  - Expect `** BUILD SUCCEEDED **`.

- [ ] Run the covering tests and confirm they pass:
  - `-only-testing:DesktopKitTests/DuoAdaptiveDeckTests`.
  - `-only-testing:DesktopKitTests/DuoTests`.
  - The snapshot test is skipped here.

- [ ] Render snapshots and look at them:
  - Run `mkdir -p <scratch>/deck-shots && TEST_RUNNER_DECK_SNAPSHOT_DIR=<scratch>/deck-shots xcodebuild test … -only-testing:DesktopKitTests/DuoAdaptiveDeckTests/testSnapshots`.
  - Confirm six PNGs exist with `ls -la`, and Read each one.
  - **Check:**
    - The big pad shows when idle.
    - The keys plus a centered smaller pad show when typing.
    - The mic and More are always visible.
    - The shortcut labels drop to icons on the narrow deck, without clipping.
    - Nothing overlaps.
  - Fix and re-render until all of these hold.
- [ ] Commit:
  - Message: `Duo: Adaptive deck (big trackpad, keyboard slides in when typing) and the Classic/Adaptive setting`.

---

## Final verification (controller, after all tasks)

- **Full suite:** run it once and report the count.
  - `cd desktop/DesktopKit && xcodebuild test -skipMacroValidation -scheme DesktopKit -destination 'platform=iOS Simulator,id=D396AB49-CB12-4AF5-B0BC-86131B854E07'`
- **Signed build and install:**
  - Build with `release/duo-build-ipa.sh`, using the ASC env from the project memory.
  - Install with `release/duo-install.sh` over Wi-Fi.
- **Push:** `git push` the `duo` branch.
