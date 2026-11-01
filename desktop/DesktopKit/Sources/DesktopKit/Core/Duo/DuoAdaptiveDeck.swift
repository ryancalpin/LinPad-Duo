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

/// The shortcut row: every button the same width, filling the row. Its natural width is every
/// button at the widest one's width, so ViewThatFits can tell when the words won't fit.
private struct DuoShortcutRowLayout: Layout {
    let spacing: CGFloat
    /// The icons-only row, the last resort: it squeezes rather than overflow a very narrow deck.
    let shrinks: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let count = CGFloat(subviews.count)
        let natural = (sizes.map(\.width).max() ?? 0) * count + spacing * max(count - 1, 0)
        let width = proposal.width.map { shrinks ? $0 : max($0, natural) } ?? natural
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let count = CGFloat(subviews.count)
        let width = max((bounds.width - spacing * (count - 1)) / count, 0)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
        }
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
            // The closure runs outside this view's tracking, so it gets its own.
            GeometryReader { proxy in
                WithPerceptionTracking {
                    let spacing: CGFloat = 6
                    let available = max(proxy.size.height - 12 - Self.rowHeight - spacing, 0)
                    // The small pad keeps at least 80 pt; the keys give way first.
                    let smallPad = min(max(available * 0.38, Self.minimumPad), available)
                    let keyboardHeight = max(available - smallPad - spacing, 0)
                    let padHeight = keysShown ? smallPad : available
                    VStack(spacing: 0) {
                        shortcutRow(keysShown: keysShown)
                            .frame(height: Self.rowHeight)
                            .padding(.bottom, spacing)
                        // The keys slide down out of the shortcut row. Their slot grows with them
                        // and clips them, so they never pass over the hinge or the top screen;
                        // only the keys, since the mic's slide hints draw above the pad.
                        ZStack(alignment: .top) {
                            if keysShown {
                                DuoKeyboardView(model: controller.duoKeyboard)
                                    .frame(height: keyboardHeight)
                                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: keysShown ? keyboardHeight : 0, alignment: .top)
                        .clipped()
                        .padding(.bottom, keysShown ? spacing : 0)
                        padRow(height: padHeight, width: proxy.size.width - 20, compact: keysShown)
                            .frame(height: padHeight)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    // Reduce Motion: a quick cross-fade (as WindowView does) instead of the slide.
                    .animation(reduceMotion ? .easeInOut(duration: 0.12) : DesktopMotion.standard, value: keysShown)
                }
            }
            .onChangeCompat(of: controller.duoTypingSignal, initial: true) { _, signal in
                controller.duoTypingFocus.update(signal)
            }
        }
    }

    // MARK: Shortcut row

    private func shortcutRow(keysShown: Bool) -> some View {
        // A narrow deck drops every word at once and keeps the icons, so the row stays even.
        ViewThatFits(in: .horizontal) {
            shortcutButtons(keysShown: keysShown, showsWords: true)
            shortcutButtons(keysShown: keysShown, showsWords: false)
        }
    }

    private func shortcutButtons(keysShown: Bool, showsWords: Bool) -> some View {
        let keyboard = controller.duoKeyboard
        return DuoShortcutRowLayout(spacing: 6, shrinks: !showsWords) {
            shortcut("esc", symbol: nil, label: "Escape") { keyboard.perform(.escapeKey) }
            shortcut("Search", symbol: "magnifyingglass", showsWords: showsWords) { keyboard.perform(.launcher) }
            shortcut("All Windows", symbol: "rectangle.3.group", showsWords: showsWords) { keyboard.perform(.overview) }
            shortcut("Undo", symbol: "arrow.uturn.backward", showsWords: showsWords) { keyboard.perform(.undo) }
            shortcut("Redo", symbol: "arrow.uturn.forward", showsWords: showsWords) { keyboard.perform(.redo) }
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
                          showsWords: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                // A key with no icon (esc, fn) always keeps its word.
                if let title, showsWords || symbol == nil { Text(title).lineLimit(1) }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : DuoDeckColors.label)
            .padding(.horizontal, 8)
            .frame(minWidth: Self.rowHeight, maxWidth: .infinity, minHeight: Self.rowHeight)
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
                // The mic sits at the deck's left edge: it slides right, over the pad, to cancel.
                DuoMicButton(dictation: controller.duoDictation, mode: layout.micMode, size: DuoAdaptiveColumns.button,
                             cancelDirection: .right)
                ForEach(Array(fit.left.enumerated()), id: \.offset) { _, action in sideButton(action) }
            }
            // Over the pad, so the mic and its "Slide to cancel" stay visible as they slide.
            .zIndex(1)
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
