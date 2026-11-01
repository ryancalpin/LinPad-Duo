import Perception
import SwiftUI
import UIKit

/// When Linux windows get the on-screen keyboard. A Linux window takes first responder on
/// every touch (it has to, for hardware keys), and iPadOS answers that with the full
/// keyboard over half the screen; on demand, the keyboard comes up only from the panel's
/// keyboard button and stays down once dismissed.
enum LinuxKeyboardMode: String, CaseIterable, Identifiable {
    case onDemand
    case automatic

    static let storageKey = "desktop.keyboard.linuxOnScreen"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDemand: "From the Panel Button"
        case .automatic: "When a Window Takes Focus"
        }
    }

    static var current: LinuxKeyboardMode {
        UserDefaults.standard.string(forKey: storageKey).flatMap(LinuxKeyboardMode.init) ?? .onDemand
    }
}

/// The Terminal's row of extra keys (Esc, Tab, Ctrl, arrows) above the on-screen keyboard.
/// It belongs to the keyboard: shown only while the on-screen keyboard is up, never with a
/// hardware keyboard, and never for Linux windows. The iSH terminal reads the same key.
enum ExtraKeysRow {
    static let storageKey = "desktop.keyboard.extraKeysRow"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

@Perceptible @MainActor
final class OnScreenKeyboard {
    static let shared = OnScreenKeyboard()

    /// The user asked for the keyboard (panel button) and has not dismissed it since.
    private(set) var isRequested = false
    /// The on-screen keyboard is currently up.
    private(set) var isVisible = false

    /// Posted when laptop pose's deck comes or goes, with `userInfo["shown"]`: the iSH
    /// terminal (app/TerminalView.m) keeps iOS's keyboard down by it too.
    static let laptopDeckDidChangeNotification = Notification.Name("DesktopLaptopDeckDidChange")
    /// Laptop pose's deck is up. It is the keyboard then, and iOS's stays down; everywhere
    /// else iOS's keyboard works as usual.
    private(set) var isLaptopDeckShown = false
    /// The desktop text field or view being edited, for the Adaptive deck.
    private(set) var editingField: ObjectIdentifier?

    /// The deck stands in for iOS's keyboard: Linux windows and the terminal don't take
    /// first responder (the deck types into them directly), and the built-in apps' text
    /// fields get an empty input view. A hardware keyboard brings no software keyboard
    /// anyway, so then nothing changes.
    var suppressesSystemKeyboard: Bool { isLaptopDeckShown && !HardwareKeyboardMonitor.isAttached }

    /// For text fields while the deck is up. A plain zero-size view: a UIInputView, even at
    /// zero height, gets iOS 27's keyboard glass at full keyboard height over the deck.
    @PerceptionIgnored private lazy var emptyInputView = UIView(frame: .zero)

    /// Stands in for the system keyboard; with zero height nothing shows, and hardware keys
    /// still arrive as presses.
    @PerceptionIgnored private lazy var placeholder: UIView = {
        // Without an explicit zero height UIKit gives a custom input view the keyboard's
        // default height, an empty keyboard-sized block that pushes windows up.
        let view = UIInputView(frame: .zero, inputViewStyle: .default)
        view.allowsSelfSizing = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 0).isActive = true
        return view
    }()

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            MainActor.assumeIsolated { self?.isVisible = frame.height > 100 }
        }
        // Text fields and views in the built-in apps: no system keyboard over the deck.
        for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let responder = note.object as? UIResponder
                MainActor.assumeIsolated {
                    guard let self, let responder else { return }
                    self.editingField = ObjectIdentifier(responder)
                    guard self.suppressesSystemKeyboard else { return }
                    self.setPlaceholder(true, on: responder)
                }
            }
        }
        for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let responder = note.object as? UIResponder
                MainActor.assumeIsolated {
                    guard let self, let responder else { return }
                    if self.editingField == ObjectIdentifier(responder) { self.editingField = nil }
                    self.setPlaceholder(false, on: responder)
                }
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isVisible = false
                // Dismissed with the keyboard's own key: stay down until asked for again.
                self.isRequested = false
            }
        }
    }

    /// The input view a Linux surface reports: nil for the system keyboard, or an empty view
    /// that keeps it down. With a hardware keyboard iPadOS shows no software keyboard anyway,
    /// only the assistant bar, which carries the IME candidates, emoji and dictation, so
    /// that case is left to the system.
    func inputView(for responder: UIResponder) -> UIView? {
        if HardwareKeyboardMonitor.isAttached || LinuxKeyboardMode.current == .automatic || isRequested { return nil }
        // The app has a text field focused (text-input-v3 enable): type into it.
        if (responder as? LinuxSurfaceView)?.surface?.textInput != nil { return nil }
        return placeholder
    }

    /// Laptop pose's deck appeared or went away.
    func setLaptopDeckShown(_ shown: Bool) {
        guard shown != isLaptopDeckShown else { return }
        isLaptopDeckShown = shown
        NotificationCenter.default.post(name: Self.laptopDeckDidChangeNotification, object: nil, userInfo: ["shown": shown])
        guard let responder = UIResponder.desktopCurrentFirstResponder else { return }
        if responder is UITextField || responder is UITextView {
            setPlaceholder(shown && suppressesSystemKeyboard, on: responder)
        } else if shown && suppressesSystemKeyboard && responder is LinuxSurfaceView {
            // Its keyboard goes away with first responder; the deck types into it anyway.
            responder.resignFirstResponder()
        }
    }

    /// The empty input view on a built-in app's text field or view, or back to the system keyboard.
    private func setPlaceholder(_ on: Bool, on responder: UIResponder) {
        let current: UIView?
        switch responder {
        case let field as UITextField: current = field.inputView
        case let view as UITextView: current = view.inputView
        default: return
        }
        // Leave a field's own custom input view (a picker) alone.
        guard on ? current == nil : current === emptyInputView else { return }
        let view = on ? emptyInputView : nil
        (responder as? UITextField)?.inputView = view
        (responder as? UITextView)?.inputView = view
        if responder.isFirstResponder { responder.reloadInputViews() }
    }

    /// Panel button: brings the keyboard up for the focused Linux window, or puts it away.
    func toggle(for controller: DesktopController) {
        guard let surface = Self.focusedSurface(in: controller) else { return }
        if isVisible {
            isRequested = false
            surface.reloadInputViews()
            surface.resignFirstResponder()
            controller.input.ensureKeyCommandsReachable()
            return
        }
        isRequested = true
        if surface.isFirstResponder {
            surface.reloadInputViews()
        } else {
            surface.becomeFirstResponder()
        }
    }

    /// The focused window's Linux surface, found in the view hierarchy.
    static func focusedSurface(in controller: DesktopController) -> LinuxSurfaceView? {
        guard let id = controller.windowManager.focusedWindowID,
              let root = controller.input.referenceView?.window else { return nil }
        var stack: [UIView] = [root]
        while let view = stack.popLast() {
            if let surface = view as? LinuxSurfaceView, surface.canBecomeFirstResponder,
               controller.input.window(containing: surface)?.id == id {
                return surface
            }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}

extension LinuxSurfaceView {
    /// iPadOS draws its shortcuts bar (undo, redo, paste) along the bottom of the screen for
    /// a text responder whose keyboard is down, right over the dock and taskbar. Linux apps
    /// have their own undo and paste, so the bar gets nothing to show and stays away; IME
    /// candidates still appear in it.
    func hideShortcutsBar() {
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
    }

    override var inputView: UIView? {
        MainActor.assumeIsolated { OnScreenKeyboard.shared.inputView(for: self) }
    }
}

extension DesktopController {
    /// Linux apps and the terminal own their ⌘ chords (they reach the app as Ctrl).
    var focusedWindowOwnsCommandKeys: Bool {
        guard let window = windowManager.focusedWindow else { return false }
        return window.appID.hasPrefix(LinuxAppID.prefix) || window.appID == AppID.terminal
    }

    /// Sends ⌘<key> to the focused Linux window as the bridge would have (left ⌘ is Ctrl).
    func forwardCommandChord(_ usage: UIKeyboardHIDUsage) {
        guard let surface = OnScreenKeyboard.focusedSurface(in: self), let bridge = surface.bridge,
              let code = LinuxKeyCodes.evdev(for: usage) else { return }
        let control = LinuxKeyCodes.leftControl
        for (key, pressed) in [(control, true), (code, true), (code, false), (control, false)] {
            bridge.key(key, pressed: pressed, focusedSurface: surface.surfaceID)
        }
    }

    /// The panel shows a keyboard button while a Linux window has focus and only the
    /// on-screen keyboard can type into it.
    var showsKeyboardButton: Bool {
        guard !keyboard.isConnected, !HardwareKeyboardMonitor.isAttached,
              let window = windowManager.focusedWindow else { return false }
        return window.appID.hasPrefix(LinuxAppID.prefix)
    }
}
