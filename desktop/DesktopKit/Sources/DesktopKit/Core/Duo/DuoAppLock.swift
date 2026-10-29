import LocalAuthentication
import Perception
import SwiftUI
import UIKit

/// Settings › Safety and Battery › "Require Face ID" (plan Phase 11). LinPad covers itself
/// the moment it leaves the screen (so the app switcher shows nothing) and asks for Face ID,
/// Touch ID or the passcode when it comes back and when it starts. Linux keeps running
/// underneath the whole time; only the screen is locked.
@Perceptible @MainActor
final class DuoAppLock {
    private(set) var isLocked = DuoSettings.isOn(DuoSettings.appLockKey)
    private(set) var failure: String?
    private(set) var isAuthenticating = false
    @PerceptionIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfEnabled() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unlockIfLocked() }
        })
    }

    private var isEnabled: Bool { DuoSettings.isOn(DuoSettings.appLockKey) }

    func lockIfEnabled() {
        // The Face ID sheet itself makes the app resign active; that must not lock again.
        guard isEnabled, !isAuthenticating else { return }
        isLocked = true
    }

    /// The setting was turned off: nothing to unlock.
    func settingChanged() {
        if !isEnabled { isLocked = false }
    }

    func unlockIfLocked() {
        guard isLocked, isEnabled, !isAuthenticating else {
            if !isEnabled { isLocked = false }
            return
        }
        let context = LAContext()
        var error: NSError?
        // deviceOwnerAuthentication falls back to the passcode, so a failed Face ID never locks
        // anyone out of their own app.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode is set on the phone: there is nothing to check against.
            isLocked = false
            return
        }
        isAuthenticating = true
        failure = nil
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock LinPad") { success, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                isAuthenticating = false
                if success {
                    isLocked = false
                } else {
                    failure = error?.localizedDescription
                }
            }
        }
    }
}

/// What covers LinPad while it is locked.
struct DuoAppLockView: View {
    let lock: DuoAppLock

    var body: some View {
        WithPerceptionTracking {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 44))
                    Text("LinPad is locked").font(.title2.weight(.semibold))
                    if let failure = lock.failure {
                        Text(failure).font(.callout).foregroundStyle(.white.opacity(0.7))
                    }
                    Button("Unlock") { lock.unlockIfLocked() }
                        .buttonStyle(.borderedProminent)
                        .disabled(lock.isAuthenticating)
                        .accessibilityIdentifier("duo.appLock.unlock")
                }
                .foregroundStyle(.white)
            }
            .transition(.opacity)
        }
    }
}
