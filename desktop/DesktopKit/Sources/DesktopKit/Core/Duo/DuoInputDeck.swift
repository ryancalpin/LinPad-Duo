import Perception
import SwiftUI

/// A keyboard and trackpad drawn on the screen (plan Phase 4): the bottom half in laptop
/// pose, and the whole phone while a monitor shows the desktop (Phase 9). Each half hides
/// itself when the real thing is connected.
struct DuoInputDeck: View {
    let controller: DesktopController
    let showsKeyboard: Bool
    let showsTrackpad: Bool
    @Environment(\.desktopTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width > proxy.size.height * 1.3
            Group {
                if wide {
                    HStack(spacing: 8) {
                        if showsKeyboard { DuoKeyboardView(model: controller.duoKeyboard) }
                        if showsTrackpad {
                            trackpad.frame(width: showsKeyboard ? proxy.size.width * 0.3 : nil)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        if showsTrackpad { trackpad }
                        if showsKeyboard {
                            DuoKeyboardView(model: controller.duoKeyboard)
                                .frame(height: showsTrackpad ? proxy.size.height * 0.45 : nil)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(theme.panelBackground.opacity(1).ignoresSafeArea())
        .onAppear { controller.duoPointer.show() }
        .onDisappear { controller.duoPointer.hide() }
    }

    private var trackpad: some View {
        DuoTrackpad(pointer: controller.duoPointer)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.titleBarActive))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.separator, lineWidth: 1))
            .overlay(alignment: .bottom) {
                Text("Trackpad")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .padding(6)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                let fold = foldFrame(in: proxy.size)
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

    /// The fold from iOS, or the middle of the screen if iOS has not reported one.
    private func foldFrame(in size: CGSize) -> CGRect {
        if let fold = controller.pose.foldInWindow, fold.width > fold.height, fold.minY > 100 {
            return fold
        }
        return CGRect(x: 0, y: (size.height / 2).rounded(), width: size.width, height: 0)
    }
}
