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
                    customButtons(layout.leftButtons)
                }
                Spacer()
                if layout.rightButtons.contains(where: { $0 != .none }) {
                    group { customButtons(layout.rightButtons) }
                }
            }
            DuoMicButton(dictation: controller.duoDictation, mode: layout.micMode, size: height)
        }
        .frame(height: height)
    }

    private let layout = DuoDeckLayout.shared

    /// The buttons chosen in Settings › Laptop Keyboard. Touch and hold one to change them.
    @ViewBuilder
    private func customButtons(_ actions: [DuoDeckAction]) -> some View {
        ForEach(Array(actions.enumerated()).filter { $0.element != .none }, id: \.offset) { _, action in
            barButton(action.symbol(in: controller), label: action.title(in: controller)) {
                controller.duoKeyboard.perform(action)
            }
            .contextMenu {
                Button {
                    controller.open(appID: AppID.settings, arguments: [SettingsApp.pageArgument: SettingsApp.deckPage])
                } label: {
                    Label("Customize Keyboard…", systemImage: "slider.horizontal.3")
                }
            }
        }
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

/// The deck's microphone. Tap mode: tap to start, tap again to type what was heard. Hold
/// mode: hold and speak, let go to type it; slide up to lock it on (then tap to finish),
/// slide left to cancel.
struct DuoMicButton: View {
    let dictation: DuoDictation
    let mode: DuoDeckLayout.MicMode
    let size: CGFloat
    static let lockDistance: CGFloat = 60
    static let cancelDistance: CGFloat = 80

    private enum Touch { case idle, tapping, holding, done }
    @State private var touch = Touch.idle
    @State private var offset: CGSize = .zero

    var body: some View {
        WithPerceptionTracking {
            let listening = dictation.isListening
            let holding = touch == .holding
            ZStack {
                if holding {
                    // Where to slide: up to lock, left to cancel.
                    VStack(spacing: 4) {
                        Image(systemName: offset.height < -Self.lockDistance * 0.6 ? "lock.fill" : "lock.open")
                        Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(DuoDeckColors.key))
                    .offset(y: -size * 1.15)
                    .transition(.opacity)
                    Label("Slide to cancel", systemImage: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(DuoDeckColors.secondary)
                        .fixedSize()
                        .offset(x: -size * 1.6)
                        .transition(.opacity)
                }
                Image(systemName: dictation.isLocked ? "lock.fill" : listening ? "waveform" : "mic.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(listening ? Color.red : DuoDeckColors.accent))
                    .shadow(color: (listening ? Color.red : DuoDeckColors.accent).opacity(0.5), radius: 8)
                    .scaleEffect(holding ? 1.15 : 1)
                    .offset(x: holding ? min(offset.width, 0) : 0, y: holding ? min(offset.height, 0) : 0)
                    .gesture(DragGesture(minimumDistance: 0).onChanged(changed).onEnded { _ in ended() })
            }
            .animation(DesktopMotion.quick, value: holding)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dictation.toggle() }
            .accessibilityIdentifier("duo.deck.dictate")
        }
    }

    private var accessibilityLabel: String {
        if dictation.isListening { return "Stop dictation and type it" }
        return mode == .hold ? "Dictate. Hold to talk" : "Dictate"
    }

    private func changed(_ value: DragGesture.Value) {
        switch touch {
        case .idle:
            // Hold mode starts listening as the finger lands; a locked mic waits for a tap.
            if mode == .hold && !dictation.isLocked && !dictation.isListening {
                touch = .holding
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dictation.begin()
            } else {
                touch = .tapping
            }
        case .holding:
            offset = value.translation
            if value.translation.height < -Self.lockDistance {
                touch = .done
                offset = .zero
                dictation.isLocked = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else if value.translation.width < -Self.cancelDistance {
                touch = .done
                offset = .zero
                dictation.cancel()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        case .tapping, .done:
            break
        }
    }

    private func ended() {
        switch touch {
        case .holding:
            dictation.release()
        case .tapping:
            dictation.toggle()
        case .idle, .done:
            break
        }
        touch = .idle
        offset = .zero
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
