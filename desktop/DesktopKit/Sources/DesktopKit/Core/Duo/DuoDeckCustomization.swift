import Foundation
import Perception
import SwiftUI

/// Something a customizable deck button does: the twelve function-row keys and the bottom
/// bar's buttons (Settings › Laptop Keyboard).
enum DuoDeckAction: Codable, Hashable, Identifiable {
    case none
    // The phone and the desktop
    case brightnessDown, brightnessUp, overview, launcher, commandMenu, dictation, doNotDisturb, lockScreen
    // Sound
    case previousTrack, playPause, nextTrack, mute, volumeDown, volumeUp
    // Keys
    case returnKey, escapeKey, tabKey, interrupt, pasteText, undo, redo
    // Apps
    case terminal, files, settings
    /// Any app in the launcher, by its desktop id ("linux:code", "browser").
    case app(String)

    var id: String {
        if case .app(let appID) = self { return "app:" + appID }
        return "\(self)"
    }

    /// Everything except per-app buttons, in the order the pickers list them.
    static let builtIn: [DuoDeckAction] = [
        .none,
        .terminal, .files, .settings,
        .launcher, .overview, .commandMenu, .dictation, .doNotDisturb, .lockScreen,
        .brightnessDown, .brightnessUp,
        .previousTrack, .playPause, .nextTrack, .mute, .volumeDown, .volumeUp,
        .returnKey, .escapeKey, .tabKey, .interrupt, .pasteText, .undo, .redo,
    ]

    @MainActor
    func title(in controller: DesktopController?) -> String {
        switch self {
        case .none: "Nothing"
        case .brightnessDown: "Brightness down"
        case .brightnessUp: "Brightness up"
        case .overview: "Show all windows"
        case .launcher: "Apps (search)"
        case .commandMenu: "Command Menu"
        case .dictation: "Dictate"
        case .doNotDisturb: "Do Not Disturb"
        case .lockScreen: "Lock the desktop"
        case .previousTrack: "Previous track"
        case .playPause: "Play or pause"
        case .nextTrack: "Next track"
        case .mute: "Mute"
        case .volumeDown: "Volume down"
        case .volumeUp: "Volume up"
        case .returnKey: "Return"
        case .escapeKey: "Escape"
        case .tabKey: "Tab"
        case .interrupt: "Stop command (Ctrl-C)"
        case .pasteText: "Type the iPhone's clipboard"
        case .undo: "Undo"
        case .redo: "Redo"
        case .terminal: "Terminal"
        case .files: "Files"
        case .settings: "Settings"
        case .app(let appID): controller?.launcherApps.first { $0.id == appID }?.name ?? appID
        }
    }

    @MainActor
    func symbol(in controller: DesktopController?) -> String {
        switch self {
        case .none: "circle.dashed"
        case .brightnessDown: "sun.min"
        case .brightnessUp: "sun.max"
        case .overview: "rectangle.3.group"
        case .launcher: "magnifyingglass"
        case .commandMenu: "command"
        case .dictation: "mic"
        case .doNotDisturb: "moon"
        case .lockScreen: "lock"
        case .previousTrack: "backward.end.fill"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.end.fill"
        case .mute: "speaker.slash"
        case .volumeDown: "speaker.wave.1"
        case .volumeUp: "speaker.wave.3"
        case .returnKey: "return"
        case .escapeKey: "escape"
        case .tabKey: "arrow.right.to.line"
        case .interrupt: "stop.circle"
        case .pasteText: "doc.on.clipboard"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .terminal: "apple.terminal"
        case .files: "folder"
        case .settings: "gearshape"
        case .app(let appID): controller?.launcherApps.first { $0.id == appID }?.symbol ?? "app"
        }
    }
}

/// The deck's customizable parts, saved in UserDefaults: what each function-row key and
/// bottom-bar button does, and how the microphone button works. The keyboard/trackpad
/// switch and the letter keys themselves stay put, so the deck can't be left without a
/// way to type or point.
@Perceptible @MainActor
final class DuoDeckLayout {
    static let shared = DuoDeckLayout()
    static let storageKey = "duo.deck.layout"
    static let barSlots = 3

    enum MicMode: String, Codable, CaseIterable, Identifiable {
        /// Tap to start listening, tap again to type what was heard.
        case tap
        /// Hold to talk, let go to type; slide up to keep listening hands-free, slide left to cancel.
        case hold

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tap: "Tap to start and stop"
            case .hold: "Hold to talk"
            }
        }
    }

    private struct Stored: Codable {
        var functionRow: [DuoDeckAction]
        var leftButtons: [DuoDeckAction]
        var rightButtons: [DuoDeckAction]
        var micMode: MicMode
    }

    static let defaultFunctionRow: [DuoDeckAction] = [
        .brightnessDown, .brightnessUp, .overview, .launcher, .dictation, .doNotDisturb,
        .previousTrack, .playPause, .nextTrack, .mute, .volumeDown, .volumeUp,
    ]
    static let defaultLeft: [DuoDeckAction] = [.terminal, .files, .none]
    static let defaultRight: [DuoDeckAction] = [.returnKey, .commandMenu, .none]

    var functionRow: [DuoDeckAction] { didSet { save() } }
    var leftButtons: [DuoDeckAction] { didSet { save() } }
    var rightButtons: [DuoDeckAction] { didSet { save() } }
    var micMode: MicMode { didSet { save() } }

    @PerceptionIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        functionRow = Self.padded(stored?.functionRow ?? Self.defaultFunctionRow, to: 12, with: Self.defaultFunctionRow)
        leftButtons = Self.padded(stored?.leftButtons ?? Self.defaultLeft, to: Self.barSlots, with: Self.defaultLeft)
        rightButtons = Self.padded(stored?.rightButtons ?? Self.defaultRight, to: Self.barSlots, with: Self.defaultRight)
        micMode = stored?.micMode ?? .hold
    }

    /// A saved list of the wrong length (from an older version) is cut or filled from the defaults.
    private static func padded(_ list: [DuoDeckAction], to count: Int, with fallback: [DuoDeckAction]) -> [DuoDeckAction] {
        (0..<count).map { $0 < list.count ? list[$0] : fallback[$0] }
    }

    func reset() {
        functionRow = Self.defaultFunctionRow
        leftButtons = Self.defaultLeft
        rightButtons = Self.defaultRight
        micMode = .hold
    }

    private func save() {
        let stored = Stored(functionRow: functionRow, leftButtons: leftButtons, rightButtons: rightButtons, micMode: micMode)
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.storageKey)
    }
}

/// Settings › Laptop Keyboard: the microphone button, the bottom bar and the function row.
struct DuoDeckSettingsSection: View {
    let controller: DesktopController?
    @Environment(\.desktopTheme) private var theme
    private let layout = DuoDeckLayout.shared
    @State private var showsFunctionRow = false

    var body: some View {
        WithPerceptionTracking {
            SettingsSection(title: "Laptop Keyboard", symbol: "keyboard") {
                Text("The on-screen keyboard in laptop pose, and on the phone while the desktop is on a monitor. Touch and hold a bottom-bar button on the keyboard to come here.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsRow(title: "Microphone button") {
                    Picker("Microphone button", selection: Binding(tracking: { layout.micMode }, set: { layout.micMode = $0 })) {
                        ForEach(DuoDeckLayout.MicMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("settings.deck.micMode")
                }
                Text(layout.micMode == .hold
                     ? "Hold the mic and speak; let go and the words are typed. Slide up to lock it on and keep talking hands-free (tap to finish), or slide left to cancel."
                     : "Tap the mic and speak; tap again and the words are typed.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ThemedSeparator()
                Text("Bottom bar, left of the mic").font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                ForEach(0..<DuoDeckLayout.barSlots, id: \.self) { slot in
                    picker("Button \(slot + 1)", Binding(tracking: { layout.leftButtons[slot] }, set: { layout.leftButtons[slot] = $0 }))
                }
                Text("Bottom bar, right of the mic").font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                ForEach(0..<DuoDeckLayout.barSlots, id: \.self) { slot in
                    picker("Button \(slot + 1)", Binding(tracking: { layout.rightButtons[slot] }, set: { layout.rightButtons[slot] = $0 }))
                }
                ThemedSeparator()
                DisclosureGroup("Function row (F1–F12)", isExpanded: $showsFunctionRow) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What each key does while the F1–F12 switch is off. With it on, or with fn, they are F1–F12.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(0..<12, id: \.self) { index in
                            picker("F\(index + 1)", Binding(tracking: { layout.functionRow[index] }, set: { layout.functionRow[index] = $0 }))
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
                .tint(theme.primaryText)
                HStack {
                    Spacer()
                    Button("Reset Keyboard") { layout.reset() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(theme.accent)
                }
            }
        }
    }

    /// Built-in actions, then every app in the launcher.
    private var choices: [DuoDeckAction] {
        let apps = (controller?.launcherApps ?? [])
            .filter { $0.id != AppID.settings && $0.id != AppID.files }
            .map { DuoDeckAction.app($0.id) }
        return DuoDeckAction.builtIn + apps
    }

    private func picker(_ title: String, _ selection: Binding<DuoDeckAction>) -> some View {
        SettingsRow(title: title) {
            Picker(title, selection: selection) {
                ForEach(choices + (choices.contains(selection.wrappedValue) ? [] : [selection.wrappedValue])) { action in
                    Label(action.title(in: controller), systemImage: action.symbol(in: controller)).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
