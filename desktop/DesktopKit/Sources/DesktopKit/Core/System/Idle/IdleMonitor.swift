import SwiftUI
import Perception
import UIKit

/// Notes input anywhere on the desktop and, after the idle timeouts in Settings,
/// shows the screensaver and locks the screen. Never while a screen recording runs or a
/// maximized window plays media (a fullscreen video), or while Keep Awake is on.
@Perceptible @MainActor
final class IdleMonitor {
    private(set) var isScreensaverShown = false
    @PerceptionIgnored private weak var controller: DesktopController?
    @PerceptionIgnored private var lastActivity = Date()
    @PerceptionIgnored private var task: Task<Void, Never>?
    @PerceptionIgnored private var observers: [NSObjectProtocol] = []

    private static let checkInterval: Duration = .seconds(5)

    init(controller: DesktopController) {
        self.controller = controller
    }

    func start() {
        guard task == nil else { return }
        lastActivity = Date()
        #if DEBUG || DESKTOP_AUTOMATION
        // UI tests: `-desktop.screensaver.showNow YES` starts with the screensaver on.
        if UserDefaults.standard.bool(forKey: "desktop.screensaver.showNow") {
            Task { [weak self] in
                while self?.controller?.boot.isFinished == false { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(1))
                self?.showScreensaver()
            }
        }
        #endif
        let center = NotificationCenter.default
        for name in [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteActivity() }
            })
        }
        // Keep Awake also keeps the iPhone itself from dimming and auto-locking.
        Self.applyKeepAwake()
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.applyKeepAwake() }
        })
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                await self?.check()
            }
        }
    }

    private static func applyKeepAwake() {
        let keepAwake = UserDefaults.standard.bool(forKey: IdleSettings.keepAwakeKey)
        if UIApplication.shared.isIdleTimerDisabled != keepAwake { UIApplication.shared.isIdleTimerDisabled = keepAwake }
    }

    /// Any touch or click (DesktopInputCoordinator's touch-down recognizer) or key press
    /// (HardwareKeyboardMonitor).
    func noteActivity() {
        lastActivity = Date()
        if isScreensaverShown { dismissScreensaver() }
    }

    func showScreensaver() {
        controller?.dismissAllOverlays()
        withAnimation(DesktopMotion.standard) { isScreensaverShown = true }
    }

    func dismissScreensaver() {
        lastActivity = Date()
        withAnimation(DesktopMotion.standard) { isScreensaverShown = false }
    }

    private func check() async {
        guard let controller, controller.boot.isFinished, !controller.isOnboardingPresented else { return }
        let policy = IdleSettings.policy
        let idle = Date().timeIntervalSince(lastActivity)
        guard let shortest = policy.shortestTimeout, idle >= shortest else { return }
        let inhibited = await isInhibited(controller)
        let actions = policy.actions(idle: Date().timeIntervalSince(lastActivity), isLocked: controller.isLocked,
                                     isScreensaverShown: isScreensaverShown, inhibited: inhibited)
        if actions.lock { controller.lockScreen() }
        if actions.showScreensaver { showScreensaver() }
    }

    private func isInhibited(_ controller: DesktopController) async -> Bool {
        if controller.isRecordingScreen { return true }
        guard controller.windowManager.focusedWindow?.isMaximized == true else { return false }
        await controller.nowPlaying.refresh()
        return controller.nowPlaying.player?.isPlaying == true
    }
}
