import Perception
import SwiftUI
import UIKit

/// One key of the deck's keyboard: a Linux evdev code for Linux windows, and the text it
/// types into the desktop's own text views (the built-in Terminal) when no Linux window
/// has focus.
struct DuoKey: Identifiable, Hashable {
    enum Modifier: String, Hashable { case shift, control, alt, meta }

    enum Kind: Hashable {
        case character(String, shifted: String)
        case special(String, text: String?)
        case modifier(Modifier)
        case function
        case backspace
    }

    let code: UInt32
    let kind: Kind
    var width: CGFloat = 1
    var functionCode: UInt32? = nil
    var functionLabel: String? = nil

    var id: String { "\(code)-\(label(shifted: false, function: false))" }

    func label(shifted: Bool, function: Bool) -> String {
        if function, let functionLabel { return functionLabel }
        switch kind {
        case .character(let plain, let upper): return shifted ? upper : plain
        case .special(let title, _): return title
        case .modifier(let modifier):
            switch modifier {
            case .shift: return "⇧"
            case .control: return "ctrl"
            case .alt: return "alt"
            case .meta: return "super"
            }
        case .function: return "fn"
        case .backspace: return "⌫"
        }
    }

    static func char(_ code: UInt32, _ plain: String, _ shifted: String, f: (UInt32, String)? = nil) -> DuoKey {
        DuoKey(code: code, kind: .character(plain, shifted: shifted), functionCode: f?.0, functionLabel: f?.1)
    }

    static func special(_ code: UInt32, _ title: String, text: String?, width: CGFloat = 1) -> DuoKey {
        DuoKey(code: code, kind: .special(title, text: text), width: width)
    }

    static func modifier(_ code: UInt32, _ modifier: Modifier, width: CGFloat = 1) -> DuoKey {
        DuoKey(code: code, kind: .modifier(modifier), width: width)
    }

    /// Linux evdev codes (linux/input-event-codes.h) for a US layout. ishwl turns them into
    /// characters with the layout chosen in Settings › Keyboard Shortcuts.
    static let rows: [[DuoKey]] = [
        [special(1, "esc", text: "\u{1b}"),
         char(2, "1", "!", f: (59, "F1")), char(3, "2", "@", f: (60, "F2")), char(4, "3", "#", f: (61, "F3")),
         char(5, "4", "$", f: (62, "F4")), char(6, "5", "%", f: (63, "F5")), char(7, "6", "^", f: (64, "F6")),
         char(8, "7", "&", f: (65, "F7")), char(9, "8", "*", f: (66, "F8")), char(10, "9", "(", f: (67, "F9")),
         char(11, "0", ")", f: (68, "F10")), char(12, "-", "_", f: (87, "F11")), char(13, "=", "+", f: (88, "F12")),
         DuoKey(code: 14, kind: .backspace, width: 1.4)],
        [special(15, "tab", text: "\t", width: 1.3),
         char(16, "q", "Q"), char(17, "w", "W"), char(18, "e", "E"), char(19, "r", "R"), char(20, "t", "T"),
         char(21, "y", "Y"), char(22, "u", "U"), char(23, "i", "I"), char(24, "o", "O"), char(25, "p", "P"),
         char(26, "[", "{"), char(27, "]", "}"), char(43, "\\", "|")],
        [modifier(29, .control, width: 1.5),
         char(30, "a", "A"), char(31, "s", "S"), char(32, "d", "D"), char(33, "f", "F"), char(34, "g", "G"),
         char(35, "h", "H"), char(36, "j", "J"), char(37, "k", "K"), char(38, "l", "L"), char(39, ";", ":"),
         char(40, "'", "\""), special(28, "return", text: "\n", width: 1.7)],
        [modifier(42, .shift, width: 1.9),
         char(44, "z", "Z"), char(45, "x", "X"), char(46, "c", "C"), char(47, "v", "V"), char(48, "b", "B"),
         char(49, "n", "N"), char(50, "m", "M"), char(51, ",", "<"), char(52, ".", ">"), char(53, "/", "?"),
         special(103, "↑", text: "\u{1b}[A"), special(111, "del", text: "\u{1b}[3~")],
        [DuoKey(code: 0, kind: .function, width: 1.1), modifier(56, .alt, width: 1.1), modifier(125, .meta, width: 1.3),
         char(41, "`", "~"), char(57, " ", " ").with(width: 4.4),
         special(102, "home", text: "\u{1b}[H", width: 1.1), special(107, "end", text: "\u{1b}[F", width: 1.1),
         special(105, "←", text: "\u{1b}[D"), special(108, "↓", text: "\u{1b}[B"), special(106, "→", text: "\u{1b}[C")],
    ]

    func with(width: CGFloat) -> DuoKey {
        var key = self
        key.width = width
        return key
    }
}

/// Modifier state for the deck's keyboard: a tap latches a modifier for the next key, a
/// second tap locks it, a third releases it, like an iPhone's Shift key.
@Perceptible @MainActor
final class DuoKeyboardModel {
    enum State { case off, latched, locked }

    private(set) var modifiers: [DuoKey.Modifier: State] = [:]
    var showsFunctionKeys = false
    @PerceptionIgnored weak var controller: DesktopController?
    @PerceptionIgnored private var repeatTask: Task<Void, Never>?

    private static let modifierCodes: [DuoKey.Modifier: UInt32] = [.shift: 42, .control: 29, .alt: 56, .meta: 125]

    func state(of modifier: DuoKey.Modifier) -> State { modifiers[modifier] ?? .off }

    var isShifted: Bool { state(of: .shift) != .off }

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
            showsFunctionKeys.toggle()
            return
        default:
            break
        }
        let held = modifiers.filter { $0.value != .off }.map(\.key)
        if let surface = linuxTarget, let bridge = controller?.linux {
            let code = showsFunctionKeys ? (key.functionCode ?? key.code) : key.code
            for modifier in held { if let mod = Self.modifierCodes[modifier] { bridge.key(mod, pressed: true, focusedSurface: surface) } }
            bridge.key(code, pressed: true, focusedSurface: surface)
            // Linux repeats a held key itself; it is released in `release`.
            pendingRelease = (code, held, surface)
        } else {
            typeIntoFirstResponder(key, modifiers: Set(held))
            startRepeating(key, modifiers: Set(held))
        }
        // A latched modifier applies to one key.
        for (modifier, state) in modifiers where state == .latched { modifiers[modifier] = .off }
    }

    @PerceptionIgnored private var pendingRelease: (code: UInt32, modifiers: [DuoKey.Modifier], surface: UInt32)?

    func release(_ key: DuoKey) {
        repeatTask?.cancel()
        repeatTask = nil
        guard let pending = pendingRelease, let bridge = controller?.linux else { return }
        pendingRelease = nil
        bridge.key(pending.code, pressed: false, focusedSurface: pending.surface)
        for modifier in pending.modifiers.reversed() {
            if let mod = Self.modifierCodes[modifier] { bridge.key(mod, pressed: false, focusedSurface: pending.surface) }
        }
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
        guard let input = UIResponder.desktopCurrentFirstResponder as? UIKeyInput else { return }
        if key.kind == .backspace {
            input.deleteBackward()
            return
        }
        guard var text = key.text(shifted: modifiers.contains(.shift)) else { return }
        if modifiers.contains(.control), let scalar = text.uppercased().unicodeScalars.first,
           text.unicodeScalars.count == 1, (0x40...0x5f).contains(scalar.value) {
            // Ctrl-C is 0x03: the letter's code with bit 6 cleared, as a terminal sends it.
            text = String(UnicodeScalar(UInt8(scalar.value ^ 0x40)))
        }
        if modifiers.contains(.alt) { text = "\u{1b}" + text }
        input.insertText(text)
    }
}

extension DuoKey {
    func text(shifted: Bool) -> String? {
        switch kind {
        case .character(let plain, let upper): shifted ? upper : plain
        case .special(_, let text): text
        default: nil
        }
    }

    var isRepeatable: Bool {
        switch kind {
        case .backspace, .character: true
        case .special: [103, 105, 106, 108, 111].contains(code)
        default: false
        }
    }
}

/// The keyboard half of the deck.
struct DuoKeyboardView: View {
    let model: DuoKeyboardModel
    @Environment(\.desktopTheme) private var theme

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let rows = DuoKey.rows
                let spacing: CGFloat = 5
                let rowHeight = (proxy.size.height - spacing * CGFloat(rows.count + 1)) / CGFloat(rows.count)
                VStack(spacing: spacing) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        let units = row.reduce(0) { $0 + $1.width }
                        let unit = (proxy.size.width - spacing * CGFloat(row.count + 1)) / units
                        HStack(spacing: spacing) {
                            ForEach(row) { key in
                                DuoKeyCap(key: key, model: model)
                                    .frame(width: max(unit * key.width, 10), height: max(rowHeight, 20))
                            }
                        }
                    }
                }
                .padding(spacing)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct DuoKeyCap: View {
    let key: DuoKey
    let model: DuoKeyboardModel
    @Environment(\.desktopTheme) private var theme
    @State private var isDown = false

    var body: some View {
        WithPerceptionTracking {
            let label = key.label(shifted: model.isShifted, function: model.showsFunctionKeys)
            Text(label)
                .font(.system(size: label.count > 2 ? 13 : 18, weight: .medium))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isHighlighted ? Color.white : theme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? theme.accent : (isDown ? theme.hoverFill : theme.titleBarActive)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(theme.separator, lineWidth: 0.5))
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
                .accessibilityLabel(accessibilityName)
                .accessibilityAddTraits(.isKeyboardKey)
        }
    }

    private var isHighlighted: Bool {
        switch key.kind {
        case .modifier(let modifier): model.state(of: modifier) != .off
        case .function: model.showsFunctionKeys
        default: false
        }
    }

    private var accessibilityName: String {
        switch key.kind {
        case .character(" ", _): "space"
        case .backspace: "delete"
        default: key.label(shifted: model.isShifted, function: model.showsFunctionKeys)
        }
    }
}
