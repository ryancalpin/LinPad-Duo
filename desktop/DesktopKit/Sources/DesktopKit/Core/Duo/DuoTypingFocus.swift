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
