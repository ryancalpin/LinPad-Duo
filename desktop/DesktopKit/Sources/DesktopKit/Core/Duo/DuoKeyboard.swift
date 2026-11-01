import Perception
import SwiftUI
import UIKit

/// One key of the deck's Mac-style keyboard: a Linux evdev code (linux/input-event-codes.h)
/// for Linux windows, and the text it types into the desktop's own text views (the
/// built-in Terminal) when no Linux window has focus.
struct DuoKey: Identifiable, Hashable {
    enum Modifier: String, Hashable { case shift, control, alt, meta }

    enum Kind: Hashable {
        /// `label` is what the cap shows (capitals for letters, as on a Mac).
        case character(String, shifted: String)
        case special(text: String?)
        case modifier(Modifier)
        case function
        case capsLock
        case backspace
        /// Function-row key `n` (0…11): its action from DuoDeckLayout while the F1–F12
        /// switch is off, as on a Mac, else F1–F12.
        case functionSlot(Int)
    }

    let code: UInt32
    let kind: Kind
    var label = ""
    /// An SF Symbol drawn instead of, or above, the label.
    var symbol: String? = nil
    /// The small word under a symbol ("tab", "shift", "command").
    var caption: String? = nil
    var width: CGFloat = 1
    /// F1–F12 on the function row.
    var functionCode: UInt32? = nil
    var functionLabel: String? = nil

    var id: String { "\(code)-\(label)-\(caption ?? "")-\(symbol ?? "")" }

    static func char(_ code: UInt32, _ plain: String, _ shifted: String) -> DuoKey {
        DuoKey(code: code, kind: .character(plain, shifted: shifted), label: plain.uppercased())
    }

    static func special(_ code: UInt32, _ label: String, text: String?, symbol: String? = nil,
                        caption: String? = nil, width: CGFloat = 1) -> DuoKey {
        DuoKey(code: code, kind: .special(text: text), label: label, symbol: symbol, caption: caption, width: width)
    }

    static func modifier(_ code: UInt32, _ modifier: Modifier, symbol: String, caption: String, width: CGFloat) -> DuoKey {
        DuoKey(code: code, kind: .modifier(modifier), symbol: symbol, caption: caption, width: width)
    }

    static func slot(_ index: Int, code: UInt32) -> DuoKey {
        // F1–F10 are 59–68, F11 87, F12 88.
        DuoKey(code: code, kind: .functionSlot(index), functionCode: code, functionLabel: "F\(index + 1)")
    }

    func with(width: CGFloat) -> DuoKey {
        var key = self
        key.width = width
        return key
    }

    /// The function row, as on a MacBook: customizable actions, F1–F12 with fn or the switch.
    static let functionRow: [DuoKey] = [
        special(1, "esc", text: "\u{1b}", width: 1.4),
        slot(0, code: 59), slot(1, code: 60), slot(2, code: 61), slot(3, code: 62), slot(4, code: 63), slot(5, code: 64),
        slot(6, code: 65), slot(7, code: 66), slot(8, code: 67), slot(9, code: 68), slot(10, code: 87), slot(11, code: 88),
    ]

    /// The main block, US ANSI. ishwl turns the codes into characters with the layout chosen
    /// in Settings › Keyboard Shortcuts.
    static let rows: [[DuoKey]] = [
        [char(41, "`", "~"), char(2, "1", "!"), char(3, "2", "@"), char(4, "3", "#"), char(5, "4", "$"),
         char(6, "5", "%"), char(7, "6", "^"), char(8, "7", "&"), char(9, "8", "*"), char(10, "9", "("),
         char(11, "0", ")"), char(12, "-", "_"), char(13, "=", "+"),
         DuoKey(code: 14, kind: .backspace, symbol: "delete.left", width: 1.5)],
        [special(15, "", text: "\t", symbol: "arrow.right.to.line", caption: "tab", width: 1.5),
         char(16, "q", "Q"), char(17, "w", "W"), char(18, "e", "E"), char(19, "r", "R"), char(20, "t", "T"),
         char(21, "y", "Y"), char(22, "u", "U"), char(23, "i", "I"), char(24, "o", "O"), char(25, "p", "P"),
         char(26, "[", "{"), char(27, "]", "}"), char(43, "\\", "|")],
        [DuoKey(code: 58, kind: .capsLock, symbol: "capslock", caption: "caps lock", width: 1.8),
         char(30, "a", "A"), char(31, "s", "S"), char(32, "d", "D"), char(33, "f", "F"), char(34, "g", "G"),
         char(35, "h", "H"), char(36, "j", "J"), char(37, "k", "K"), char(38, "l", "L"), char(39, ";", ":"),
         char(40, "'", "\""), special(28, "return", text: "\n", width: 1.7)],
        [modifier(42, .shift, symbol: "shift", caption: "shift", width: 2.3),
         char(44, "z", "Z"), char(45, "x", "X"), char(46, "c", "C"), char(47, "v", "V"), char(48, "b", "B"),
         char(49, "n", "N"), char(50, "m", "M"), char(51, ",", "<"), char(52, ".", ">"), char(53, "/", "?"),
         modifier(54, .shift, symbol: "shift", caption: "shift", width: 2.2)],
        [DuoKey(code: 0, kind: .function, label: "fn"),
         modifier(29, .control, symbol: "control", caption: "control", width: 1),
         modifier(56, .alt, symbol: "option", caption: "option", width: 1),
         modifier(125, .meta, symbol: "command", caption: "command", width: 1.3),
         char(57, " ", " ").with(width: 3.9),
         modifier(126, .meta, symbol: "command", caption: "command", width: 1.3),
         modifier(100, .alt, symbol: "option", caption: "option", width: 1),
         modifier(97, .control, symbol: "control", caption: "control", width: 1)],
    ]

    /// The inverted-T arrows at the end of the bottom row.
    static let left = special(105, "", text: "\u{1b}[D", symbol: "arrowtriangle.left.fill")
    static let up = special(103, "", text: "\u{1b}[A", symbol: "arrowtriangle.up.fill")
    static let down = special(108, "", text: "\u{1b}[B", symbol: "arrowtriangle.down.fill")
    static let right = special(106, "", text: "\u{1b}[C", symbol: "arrowtriangle.right.fill")
    /// Width of the arrow cluster in key units.
    static let arrowsWidth: CGFloat = 3
}

extension DuoKey {
    func text(shifted: Bool) -> String? {
        switch kind {
        case .character(let plain, let upper): shifted ? upper : plain
        case .special(let text): text
        default: nil
        }
    }

    var isRepeatable: Bool {
        switch kind {
        case .backspace, .character: true
        case .special: [103, 105, 106, 108].contains(code)
        default: false
        }
    }

    /// The shifted character a key shows above its own (number and symbol keys).
    var shiftedHint: String? {
        guard case .character(let plain, let upper) = kind, plain.uppercased() != upper, plain != " " else { return nil }
        return upper
    }
}

/// The deck keyboard's state: sticky modifiers (a tap latches one for the next key, a
/// second tap locks it, a third releases it), caps lock, fn, and the F1–F12 switch.
@Perceptible @MainActor
final class DuoKeyboardModel {
    enum State { case off, latched, locked }

    private(set) var modifiers: [DuoKey.Modifier: State] = [:]
    private(set) var capsLock = false
    /// fn tapped: the next function-row key sends F1–F12.
    private(set) var fnLatched = false
    /// The F1–F12 switch above the keyboard.
    var functionKeysLocked = UserDefaults.standard.bool(forKey: DuoKeyboardModel.functionKeysKey) {
        didSet { UserDefaults.standard.set(functionKeysLocked, forKey: Self.functionKeysKey) }
    }
    static let functionKeysKey = "duo.deck.functionKeys"

    @PerceptionIgnored weak var controller: DesktopController?
    @PerceptionIgnored private var repeatTask: Task<Void, Never>?
    @PerceptionIgnored private var pendingRelease: (code: UInt32, modifiers: [UInt32], surface: UInt32)?

    private static let modifierCodes: [DuoKey.Modifier: UInt32] = [.shift: 42, .control: 29, .alt: 56, .meta: 125]

    func state(of modifier: DuoKey.Modifier) -> State { modifiers[modifier] ?? .off }

    var isShifted: Bool { state(of: .shift) != .off }
    var showsFunctionKeys: Bool { functionKeysLocked || fnLatched }

    func tapModifier(_ modifier: DuoKey.Modifier) {
        switch state(of: modifier) {
        case .off: modifiers[modifier] = .latched
        case .latched: modifiers[modifier] = .locked
        case .locked: modifiers[modifier] = .off
        }
    }

    /// The Linux surface that gets the keys: the focused window's, if it is a Linux window.
    private var linuxTarget: UInt32? {
        guard let controller, let focused = controller.windowManager.focusedWindowID else { return nil }
        return controller.linuxWindows.first { $0.value == focused }?.key
    }

    func press(_ key: DuoKey) {
        switch key.kind {
        case .modifier(let modifier):
            tapModifier(modifier)
            return
        case .function:
            fnLatched.toggle()
            return
        case .functionSlot(let index) where !showsFunctionKeys:
            let action = DuoDeckLayout.shared.functionRow[index]
            if action != .none { perform(action) }
            fnLatched = false
            return
        case .capsLock:
            capsLock.toggle()
            if let surface = linuxTarget, let bridge = controller?.linux {
                bridge.key(key.code, pressed: true, focusedSurface: surface)
                bridge.key(key.code, pressed: false, focusedSurface: surface)
            }
            return
        default:
            break
        }
        let held = modifiers.filter { $0.value != .off }.map(\.key)
        let code = key.functionCode.flatMap { showsFunctionKeys ? $0 : nil } ?? key.code
        if let surface = linuxTarget, let bridge = controller?.linux {
            let modifierCodes = held.compactMap { Self.modifierCodes[$0] }
            for mod in modifierCodes { bridge.key(mod, pressed: true, focusedSurface: surface) }
            bridge.key(code, pressed: true, focusedSurface: surface)
            // Linux repeats a held key itself; it is released in `release`.
            pendingRelease = (code, modifierCodes, surface)
        } else {
            var typing = Set(held)
            if capsLock, case .character(let plain, _) = key.kind, plain.count == 1, plain.lowercased() != plain.uppercased() {
                if typing.contains(.shift) { typing.remove(.shift) } else { typing.insert(.shift) }
            }
            typeIntoFirstResponder(key, modifiers: typing)
            startRepeating(key, modifiers: typing)
        }
        // A latched modifier, and fn, apply to one key.
        for (modifier, state) in modifiers where state == .latched { modifiers[modifier] = .off }
        fnLatched = false
    }

    func release(_ key: DuoKey) {
        repeatTask?.cancel()
        repeatTask = nil
        guard let pending = pendingRelease, let bridge = controller?.linux else { return }
        pendingRelease = nil
        bridge.key(pending.code, pressed: false, focusedSurface: pending.surface)
        for mod in pending.modifiers.reversed() { bridge.key(mod, pressed: false, focusedSurface: pending.surface) }
    }

    /// Sends Return to whatever has focus (the bottom bar's return button).
    func pressReturn() {
        let key = DuoKey.special(28, "return", text: "\n")
        press(key)
        release(key)
    }

    // MARK: Deck actions (function row and bottom bar)

    func perform(_ action: DuoDeckAction) {
        guard let controller else { return }
        switch action {
        case .none:
            break
        case .brightnessDown, .brightnessUp:
            let screen = controller.input.referenceView?.window?.screen ?? UIScreen.main
            screen.brightness = min(max(screen.brightness + (action == .brightnessUp ? 0.0625 : -0.0625), 0), 1)
            controller.showOSD(.brightness(Double(screen.brightness)))
        case .overview:
            controller.toggleOverview()
        case .launcher:
            controller.toggleLauncher()
        case .commandMenu:
            controller.toggleCommandMenu()
        case .dictation:
            controller.duoDictation.toggle()
        case .doNotDisturb:
            controller.notifications.doNotDisturb.toggle()
            controller.notify(controller.notifications.doNotDisturb ? "Do Not Disturb is on." : "Do Not Disturb is off.")
        case .lockScreen:
            controller.lockScreen()
        case .previousTrack, .playPause, .nextTrack:
            // XF86AudioPrev / Play / Next, which Linux media players listen for.
            let code: UInt32 = action == .previousTrack ? 165 : action == .playPause ? 164 : 163
            tap(code)
        case .mute:
            guard let controls = controller.systemControls else { return }
            controls.isMuted.toggle()
            controller.showOSD(.volume(controls.isMuted ? 0 : Double(controls.volume ?? 1)))
        case .volumeDown, .volumeUp:
            guard let controls = controller.systemControls, let volume = controls.volume else { return }
            let next = min(max(volume + (action == .volumeUp ? 0.0625 : -0.0625), 0), 1)
            controls.volume = next
            if controls.isMuted && action == .volumeUp { controls.isMuted = false }
            controller.showOSD(.volume(controls.isMuted ? 0 : Double(next)))
        case .returnKey:
            pressReturn()
        case .escapeKey:
            let key = DuoKey.special(1, "esc", text: "\u{1b}")
            press(key)
            release(key)
        case .tabKey:
            let key = DuoKey.special(15, "tab", text: "\t")
            press(key)
            release(key)
        case .interrupt:
            modifiers[.control] = .latched
            let key = DuoKey.char(46, "c", "C")
            press(key)
            release(key)
        case .pasteText:
            guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
            if linuxTarget != nil, let bridge = controller.linux {
                bridge.type(text)
            } else if let input = controller.deckTextTarget {
                input.insertText(text)
            }
        case .undo, .redo:
            undoOrRedo(redo: action == .redo)
        case .terminal:
            controller.openLinuxApp(LinuxAppID.preferredTerminal)
        case .files:
            controller.open(appID: AppID.files, arguments: [:])
        case .settings:
            controller.open(appID: AppID.settings, arguments: [:])
        case .app(let appID):
            controller.open(appID: appID, arguments: [:])
        }
    }

    /// Undo and Redo: Ctrl+Z and Ctrl+Shift+Z in a Linux window, the text field's own undo in
    /// the desktop's fields. Nothing in a terminal, where Ctrl+Z suspends the running program.
    private func undoOrRedo(redo: Bool) {
        guard let controller else { return }
        if let appID = controller.windowManager.focusedWindow?.appID, Self.isTerminal(appID: appID) { return }
        if let surface = linuxTarget, let bridge = controller.linux {
            // The exact chord, whatever modifiers are latched or locked on the deck.
            let chord: [UInt32] = redo ? [29, 42, 44] : [29, 44]
            for code in chord { bridge.key(code, pressed: true, focusedSurface: surface) }
            for code in chord.reversed() { bridge.key(code, pressed: false, focusedSurface: surface) }
        } else if let manager = UIResponder.desktopCurrentFirstResponder?.undoManager {
            if redo { manager.redo() } else { manager.undo() }
        }
    }

    /// The built-in Terminal app, or foot in the Linux session (`footclient` when run by hand).
    static func isTerminal(appID: String) -> Bool {
        appID == AppID.terminal || appID == LinuxAppID.prefix + "foot" || appID == LinuxAppID.prefix + "footclient"
    }

    /// Presses and releases one key in the focused Linux window.
    private func tap(_ code: UInt32) {
        guard let bridge = controller?.linux else { return }
        bridge.key(code, pressed: true, focusedSurface: linuxTarget)
        bridge.key(code, pressed: false, focusedSurface: linuxTarget)
    }

    // MARK: The desktop's own text views

    private func startRepeating(_ key: DuoKey, modifiers: Set<DuoKey.Modifier>) {
        guard key.isRepeatable else { return }
        repeatTask?.cancel()
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            while !Task.isCancelled {
                self?.typeIntoFirstResponder(key, modifiers: modifiers)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func typeIntoFirstResponder(_ key: DuoKey, modifiers: Set<DuoKey.Modifier>) {
        guard let input = controller?.deckTextTarget else { return }
        if key.kind == .backspace {
            input.deleteBackward()
            return
        }
        guard var text = key.text(shifted: modifiers.contains(.shift)) else { return }
        if modifiers.contains(.control) || modifiers.contains(.meta),
           let scalar = text.uppercased().unicodeScalars.first,
           text.unicodeScalars.count == 1, (0x40...0x5f).contains(scalar.value) {
            // Ctrl-C is 0x03: the letter's code with bit 6 cleared, as a terminal sends it.
            text = String(UnicodeScalar(UInt8(scalar.value ^ 0x40)))
        }
        if modifiers.contains(.alt) { text = "\u{1b}" + text }
        input.insertText(text)
    }
}

// MARK: - Views

/// The deck's colours: a dark MacBook keyboard whatever the desktop's theme.
enum DuoDeckColors {
    static let background = Color(white: 0.07)
    static let key = Color(white: 0.19)
    static let keyPressed = Color(white: 0.33)
    static let label = Color.white
    static let secondary = Color(white: 0.62)
    static let accent = Color(red: 0.2, green: 0.47, blue: 1)
}

/// The keyboard: the function row, then five rows with the arrows at the end of the last.
struct DuoKeyboardView: View {
    let model: DuoKeyboardModel

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let spacing: CGFloat = max(4, proxy.size.width / 160)
                // The function row is shorter, as on a MacBook.
                let rowHeight = (proxy.size.height - spacing * 6) / 5.7
                VStack(spacing: spacing) {
                    row(DuoKey.functionRow, spacing: spacing, height: rowHeight * 0.7)
                    ForEach(DuoKey.rows.indices.dropLast(), id: \.self) { index in
                        row(DuoKey.rows[index], spacing: spacing, height: rowHeight)
                    }
                    row(DuoKey.rows[DuoKey.rows.count - 1], spacing: spacing, height: rowHeight, withArrows: true)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    /// Spreads a row's keys over the full width; the last row ends with the arrows.
    private func row(_ keys: [DuoKey], spacing: CGFloat, height: CGFloat, withArrows: Bool = false) -> some View {
        GeometryReader { proxy in
            let units = keys.reduce(0) { $0 + $1.width } + (withArrows ? DuoKey.arrowsWidth : 0)
            let gaps = CGFloat(keys.count - 1 + (withArrows ? 1 : 0))
            let scale = (proxy.size.width - spacing * gaps) / units
            HStack(spacing: spacing) {
                ForEach(keys) { key in
                    DuoKeyCap(key: key, model: model).frame(width: max(scale * key.width, 8), height: height)
                }
                if withArrows { arrows(width: scale * DuoKey.arrowsWidth, spacing: spacing, height: height) }
            }
        }
        .frame(height: height)
    }

    private func arrows(width: CGFloat, spacing: CGFloat, height: CGFloat) -> some View {
        let keyWidth = max((width - spacing * 2) / 3, 8)
        let half = (height - 2) / 2
        return HStack(alignment: .bottom, spacing: spacing) {
            DuoKeyCap(key: DuoKey.left, model: model).frame(width: keyWidth, height: half)
            VStack(spacing: 2) {
                DuoKeyCap(key: DuoKey.up, model: model).frame(width: keyWidth, height: half)
                DuoKeyCap(key: DuoKey.down, model: model).frame(width: keyWidth, height: half)
            }
            DuoKeyCap(key: DuoKey.right, model: model).frame(width: keyWidth, height: half)
        }
        .frame(width: width, height: height, alignment: .bottom)
    }
}

private struct DuoKeyCap: View {
    let key: DuoKey
    let model: DuoKeyboardModel
    @State private var isDown = false

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let size = min(proxy.size.height, proxy.size.width * 1.2)
                content(size: size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isDown ? DuoDeckColors.keyPressed : DuoDeckColors.key))
            .overlay(alignment: .topLeading) {
                if isLit {
                    Circle().fill(Color.green).frame(width: 5, height: 5).padding(5)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDown else { return }
                    isDown = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                    model.press(key)
                }
                .onEnded { _ in
                    isDown = false
                    model.release(key)
                })
            .accessibilityElement()
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.isKeyboardKey)
            .accessibilityAddTraits(isLit ? .isSelected : [])
        }
    }

    @ViewBuilder
    private func content(size: CGFloat) -> some View {
        let showsF = model.showsFunctionKeys
        if showsF, let functionLabel = key.functionLabel {
            Text(functionLabel).font(.system(size: size * 0.36, weight: .medium)).foregroundStyle(DuoDeckColors.label)
        } else if case .functionSlot(let index) = key.kind {
            let action = DuoDeckLayout.shared.functionRow[index]
            Image(systemName: action.symbol(in: model.controller))
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(action == .none ? DuoDeckColors.secondary.opacity(0.4) : DuoDeckColors.label)
        } else if let symbol = key.symbol {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.system(size: size * (key.caption == nil ? 0.38 : 0.3), weight: .medium))
                if let caption = key.caption, size > 30 {
                    Text(caption).font(.system(size: size * 0.18)).foregroundStyle(DuoDeckColors.secondary)
                }
            }
            .foregroundStyle(DuoDeckColors.label)
        } else if let hint = key.shiftedHint {
            VStack(spacing: 0) {
                Text(hint).font(.system(size: size * 0.24)).foregroundStyle(DuoDeckColors.secondary)
                Text(key.label).font(.system(size: size * 0.36, weight: .medium))
            }
            .foregroundStyle(DuoDeckColors.label)
        } else {
            Text(key.label)
                .font(.system(size: size * (key.label.count > 2 ? 0.26 : 0.4), weight: .medium))
                .foregroundStyle(DuoDeckColors.label)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// A modifier that is latched or locked, caps lock on, fn tapped.
    private var isLit: Bool {
        switch key.kind {
        case .modifier(let modifier): model.state(of: modifier) != .off
        case .function: model.showsFunctionKeys
        case .capsLock: model.capsLock
        default: false
        }
    }

    private var accessibilityName: String {
        if model.showsFunctionKeys, let functionLabel = key.functionLabel { return functionLabel }
        switch key.kind {
        case .character(" ", _): return "space"
        case .backspace: return "delete"
        case .functionSlot(let index): return DuoDeckLayout.shared.functionRow[index].title(in: model.controller)
        default: return key.caption ?? key.label
        }
    }
}

extension DesktopController {
    /// Where the deck and dictation type outside Linux windows: the first responder, or the
    /// focused window's own text view (the terminal), which doesn't take first responder
    /// while the deck stands in for iOS's keyboard.
    var deckTextTarget: UIKeyInput? {
        if let responder = UIResponder.desktopCurrentFirstResponder as? UIKeyInput { return responder }
        guard let id = windowManager.focusedWindowID, let root = input.referenceView?.window else { return nil }
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if let text = view as? UIKeyInput, !(view is LinuxSurfaceView), !(view is UITextField),
               !(view is UITextView), input.window(containing: view)?.id == id {
                return text
            }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}
