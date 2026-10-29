import Perception
import SwiftUI
import UIKit

/// A monitor on the USB-C port (plan Phase 9). Without an external-display scene iOS just
/// mirrors the phone; with one (Info.plist, `UIWindowSceneSessionRoleExternalDisplayNonInteractive`)
/// LinPad gets the monitor to itself. The whole desktop moves there, still the same desktop
/// with every window and Linux app running, and the phone shows a keyboard and trackpad.
/// Unplugging the monitor, or "Show on iPhone", moves it back.
@Perceptible @MainActor
public final class DuoDisplayRouter {
    public static let shared = DuoDisplayRouter()

    /// The desktop's view controller, from the app's DesktopBridge.
    @PerceptionIgnored public weak var desktopViewController: UIViewController?
    @PerceptionIgnored weak var controller: DesktopController?
    public private(set) var isOnExternalDisplay = false
    /// A monitor is connected, whether or not the desktop is on it.
    public private(set) var hasExternalDisplay = false

    @PerceptionIgnored private var externalWindow: UIWindow?
    @PerceptionIgnored private weak var phoneWindow: UIWindow?
    @PerceptionIgnored private var deckController: UIViewController?

    func externalSceneConnected(_ scene: UIWindowScene) {
        hasExternalDisplay = true
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = .black
        externalWindow = window
        if DuoSettings.isOn(DuoSettings.externalDisplayKey) { moveToExternal() }
    }

    func externalSceneDisconnected() {
        moveToPhone()
        externalWindow = nil
        hasExternalDisplay = false
    }

    /// Settings › iPhone Duo › "Use a USB-C monitor" was switched, or "Show on Monitor".
    func moveToExternal() {
        guard !isOnExternalDisplay, let externalWindow, let desktop = desktopViewController,
              let phone = desktop.view.window, let controller else { return }
        phoneWindow = phone
        let deck = UIHostingController(rootView: DuoMonitorRemote(controller: controller, router: self))
        deck.view.backgroundColor = .black
        deckController = deck
        // A view controller can be the root of one window at a time: the phone takes the
        // deck first, then the monitor takes the desktop.
        phone.rootViewController = deck
        externalWindow.rootViewController = desktop
        externalWindow.isHidden = false
        isOnExternalDisplay = true
        controller.duoPoseChanged()
    }

    /// Back to the phone: "Show on iPhone", or the monitor was unplugged.
    func moveToPhone() {
        guard isOnExternalDisplay, let desktop = desktopViewController, let phone = phoneWindow else { return }
        externalWindow?.rootViewController = nil
        externalWindow?.isHidden = true
        phone.rootViewController = desktop
        deckController = nil
        isOnExternalDisplay = false
        controller?.duoPoseChanged()
        controller?.duoPointer.hide()
    }
}

/// The scene iOS creates for a connected monitor. Named for the Objective-C runtime, which
/// is how Info.plist's UISceneDelegateClassName finds it.
@objc(LinPadExternalDisplaySceneDelegate)
public final class DuoExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    public func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated { DuoDisplayRouter.shared.externalSceneConnected(scene) }
    }

    public func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated { DuoDisplayRouter.shared.externalSceneDisconnected() }
    }
}

/// The phone while the desktop is on a monitor: a trackpad and keyboard for it.
private struct DuoMonitorRemote: View {
    let controller: DesktopController
    let router: DuoDisplayRouter

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 8) {
                HStack {
                    Label("Showing on the monitor", systemImage: "display")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Show on iPhone") { router.moveToPhone() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityIdentifier("duo.monitor.back")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                if controller.keyboard.isConnected && controller.keyboard.hasPointer {
                    Spacer()
                    Text("Use your keyboard and mouse with the monitor.")
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                } else {
                    DuoInputDeck(controller: controller, showsKeyboard: !controller.keyboard.isConnected,
                                 showsTrackpad: !controller.keyboard.hasPointer)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .background { DuoKeyForwarder(controller: controller).frame(width: 1, height: 1) }
            .environment(\.colorScheme, .dark)
        }
    }
}

/// A monitor scene never has keyboard focus, so a hardware keyboard types into the phone's
/// window. This view holds the phone's first responder and sends each key to the focused
/// Linux window on the monitor.
private struct DuoKeyForwarder: UIViewRepresentable {
    let controller: DesktopController

    func makeUIView(context: Context) -> ForwarderView {
        ForwarderView(controller: controller)
    }

    func updateUIView(_ uiView: ForwarderView, context: Context) {}

    final class ForwarderView: UIView {
        private weak var controller: DesktopController?

        init(controller: DesktopController) {
            self.controller = controller
            super.init(frame: .zero)
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() } }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, pressed: true) { super.pressesBegan(presses, with: event) }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, pressed: false) { super.pressesEnded(presses, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if !forward(presses, pressed: false) { super.pressesCancelled(presses, with: event) }
        }

        private func forward(_ presses: Set<UIPress>, pressed: Bool) -> Bool {
            guard let controller, let bridge = controller.linux else { return false }
            let focused = controller.windowManager.focusedWindowID
            let surface = controller.linuxWindows.first { $0.value == focused }?.key
            var handled = false
            for press in presses {
                guard let key = press.key, let code = LinuxKeyCodes.evdev(for: key.keyCode) else { continue }
                bridge.key(code, pressed: pressed, focusedSurface: surface)
                handled = true
            }
            return handled
        }
    }
}
