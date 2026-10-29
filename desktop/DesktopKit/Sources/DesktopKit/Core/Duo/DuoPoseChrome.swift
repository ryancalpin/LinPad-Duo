import Perception
import SwiftUI

/// The controls the Duo's pose layouts add over the desktop area: the window list on the
/// outer screen (Phase 5) and the swap button on the fold in book pose (Phase 6).
struct DuoPoseChrome: View {
    let controller: DesktopController

    var body: some View {
        WithPerceptionTracking {
            switch controller.windowManager.poseLayout {
            case .single:
                DuoOuterScreenBar(controller: controller)
            case .sides(let leading, let trailing):
                DuoFoldHandle(controller: controller, leading: leading, trailing: trailing)
            case nil:
                EmptyView()
            }
        }
    }
}

/// Outer screen: a button in the corner lists the open windows; the chosen one fills the
/// screen. Linux keeps running whatever is shown.
private struct DuoOuterScreenBar: View {
    let controller: DesktopController
    @Environment(\.desktopTheme) private var theme
    @State private var isListShown = false

    var body: some View {
        WithPerceptionTracking {
            let windows = controller.windowManager.outerScreenWindowList()
            ZStack(alignment: .bottomTrailing) {
                if isListShown {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { isListShown = false }
                        .transition(.opacity)
                    list(windows)
                        .padding(.trailing, 12)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Button {
                    withAnimation(DesktopMotion.standard) { isListShown.toggle() }
                } label: {
                    Label("\(windows.count)", systemImage: "rectangle.stack")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(theme.accent))
                        .foregroundStyle(theme.accent.readableLabel)
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityLabel("Windows: \(windows.count) open")
                .accessibilityIdentifier("duo.outerScreen.windows")
            }
        }
    }

    private func list(_ windows: [DesktopWindow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(windows) { window in
                        WithPerceptionTracking {
                            Button {
                                controller.windowManager.focus(window.id)
                                withAnimation(DesktopMotion.standard) { isListShown = false }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: window.symbol).frame(width: 22)
                                    Text(window.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if window.id == controller.windowManager.focusedWindowID {
                                        Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                    }
                                }
                                .font(.body)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            ThemedSeparator()
            HStack {
                Button("Apps") {
                    isListShown = false
                    controller.toggleLauncher()
                }
                Spacer()
                Button("New Terminal") {
                    isListShown = false
                    controller.openLinuxApp(LinuxAppID.preferredTerminal)
                }
            }
            .padding(12)
        }
        .frame(width: 280)
        .foregroundStyle(theme.primaryText)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.windowBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.separator, lineWidth: 1))
        .shadow(radius: 12)
    }
}

/// Book pose: a round button on the fold swaps the two sides.
private struct DuoFoldHandle: View {
    let controller: DesktopController
    let leading: CGRect
    let trailing: CGRect
    @Environment(\.desktopTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            Button {
                controller.windowManager.swapPoseSides()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(theme.panelBackground))
                    .overlay(Circle().stroke(theme.separator, lineWidth: 1))
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(.plain)
            .position(x: (leading.maxX + trailing.minX) / 2, y: proxy.size.height - 36)
            .accessibilityLabel("Swap sides")
            .accessibilityIdentifier("duo.book.swap")
        }
    }
}
