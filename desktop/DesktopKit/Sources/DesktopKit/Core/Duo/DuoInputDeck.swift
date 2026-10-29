import Perception
import SwiftUI

/// A MacBook-style keyboard and a trackpad drawn on the screen (plan Phase 4): the bottom
/// half in laptop pose, and the whole phone while a monitor shows the desktop (Phase 9).
///
/// Top strip: the Linux keyboard layout and the F1–F12 switch. Then the keyboard, or the
/// trackpad in its place. Bottom bar: the keyboard/trackpad switch and quick apps on the
/// left, dictation in the middle, Return and the Command Menu on the right. With a hardware
/// keyboard only the trackpad shows; with a mouse too, LinPad hides the deck altogether.
struct DuoInputDeck: View {
    let controller: DesktopController
    let showsKeyboard: Bool
    let showsTrackpad: Bool
    /// The trackpad fills the keyboard's place (the hand button switches).
    @AppStorage("duo.deck.trackpadMode") private var trackpadMode = false
    @AppStorage(LinuxKeyboardLayouts.storageKey) private var layoutID = LinuxKeyboardLayouts.automatic

    private var showsTrackpadArea: Bool { showsTrackpad && (trackpadMode || !showsKeyboard) }

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let barHeight = min(max(proxy.size.height * 0.14, 44), 64)
                let stripHeight = min(max(proxy.size.height * 0.06, 22), 30)
                VStack(spacing: 6) {
                    strip.frame(height: stripHeight)
                    Group {
                        if showsTrackpadArea {
                            trackpad
                        } else if showsKeyboard {
                            DuoKeyboardView(model: controller.duoKeyboard)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    bottomBar(height: barHeight)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(DuoDeckColors.background.ignoresSafeArea())
            .overlay(alignment: .top) { DuoDictationBubble(dictation: controller.duoDictation).offset(y: -56) }
            .environment(\.colorScheme, .dark)
            .onAppear { controller.duoPointer.show() }
            .onDisappear { controller.duoPointer.hide() }
        }
    }

    // MARK: Top strip

    private var strip: some View {
        HStack(spacing: 8) {
            chip(layoutName, symbol: "chevron.down", isOn: false) {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.shortcutsPage])
            }
            .accessibilityLabel("Keyboard layout: \(layoutName)")
            if showsKeyboard && !showsTrackpadArea {
                chip("F1–F12", symbol: nil, isOn: controller.duoKeyboard.functionKeysLocked) {
                    controller.duoKeyboard.functionKeysLocked.toggle()
                }
                .accessibilityLabel("Function keys")
                .accessibilityAddTraits(controller.duoKeyboard.functionKeysLocked ? .isSelected : [])
            }
            Spacer()
            Button {
                controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.duoPage])
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DuoDeckColors.key))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DuoDeckColors.secondary)
            .accessibilityLabel("iPhone Duo settings")
        }
    }

    private var layoutName: String {
        layoutID == LinuxKeyboardLayouts.automatic ? "Automatic" : layoutID.uppercased()
    }

    private func chip(_ title: String, symbol: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? Color.white : DuoDeckColors.accent)
            .background(Capsule().fill(isOn ? DuoDeckColors.accent : DuoDeckColors.accent.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom bar

    private func bottomBar(height: CGFloat) -> some View {
        ZStack {
            HStack {
                group {
                    if showsKeyboard && showsTrackpad {
                        barButton(trackpadMode ? "keyboard" : "hand.point.up.left",
                                  label: trackpadMode ? "Show keyboard" : "Show trackpad", isOn: trackpadMode) {
                            withAnimation(DesktopMotion.standard) { trackpadMode.toggle() }
                        }
                    }
                    barButton("apple.terminal", label: "Terminal") { controller.openLinuxApp(LinuxAppID.preferredTerminal) }
                    barButton("folder", label: "Files") { controller.open(appID: AppID.files, arguments: [:]) }
                }
                Spacer()
                group {
                    barButton("return", label: "Return") { controller.duoKeyboard.pressReturn() }
                    barButton("command", label: "Command Menu") { controller.toggleCommandMenu() }
                }
            }
            micButton(size: height)
        }
        .frame(height: height)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .padding(4)
            .background(Capsule().fill(DuoDeckColors.key.opacity(0.7)))
    }

    private func barButton(_ symbol: String, label: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 36)
                .foregroundStyle(isOn ? DuoDeckColors.accent : DuoDeckColors.label)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func micButton(size: CGFloat) -> some View {
        let listening = controller.duoDictation.isListening
        return Button { controller.duoDictation.toggle() } label: {
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(listening ? Color.red : DuoDeckColors.accent))
                .shadow(color: (listening ? Color.red : DuoDeckColors.accent).opacity(0.5), radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Stop dictation and type it" : "Dictate")
        .accessibilityIdentifier("duo.deck.dictate")
    }

    private var trackpad: some View {
        DuoTrackpad(pointer: controller.duoPointer)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DuoDeckColors.key))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .overlay(alignment: .bottom) {
                Text("One finger moves · tap clicks · two-finger tap right-clicks · two fingers scroll")
                    .font(.caption2)
                    .foregroundStyle(DuoDeckColors.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(8)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Laptop pose: the desktop on the top half, the deck on the bottom half, split at the
/// fold. The desktop keeps its identity whichever way it is laid out, so open windows,
/// terminals and Linux apps carry on untouched.
struct DuoLaptopLayout<Desktop: View>: View {
    let controller: DesktopController
    let isActive: Bool
    let showsKeyboard: Bool
    @ViewBuilder let desktop: () -> Desktop

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let fold = foldFrame(in: proxy.size, origin: proxy.frame(in: .global).origin)
                VStack(spacing: 0) {
                    desktop()
                        .frame(height: isActive ? fold.minY : proxy.size.height)
                    if isActive {
                        Color.black.frame(height: fold.height)
                        DuoInputDeck(controller: controller, showsKeyboard: showsKeyboard, showsTrackpad: true)
                            .frame(height: max(proxy.size.height - fold.maxY, 0))
                            .transition(.move(edge: .bottom))
                    }
                }
            }
        }
    }

    /// The fold from iOS (reported in window coordinates; this view starts at `origin`), or
    /// the middle of the screen if iOS has not reported one.
    private func foldFrame(in size: CGSize, origin: CGPoint) -> CGRect {
        if let fold = controller.pose.foldInWindow?.offsetBy(dx: -origin.x, dy: -origin.y),
           fold.width > fold.height, fold.minY > 100, fold.maxY < size.height - 100 {
            return fold
        }
        return CGRect(x: 0, y: (size.height / 2).rounded(), width: size.width, height: 0)
    }
}
