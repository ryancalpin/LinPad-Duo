import SwiftUI

/// The desktop's reactions to the iPhone Duo's poses (Core/Duo).
extension DesktopController {
    /// Called once from `init`.
    func startDuo() {
        duoPointer.controller = self
        duoKeyboard.controller = self
        DuoDisplayRouter.shared.controller = self
        pose.observe { [weak self] _, _ in self?.duoPoseChanged() }
        duoPoseChanged()
        DuoControllerKeys.shared.start(controller: self)
    }

    /// Once Linux has booted: the Duo's Linux commands and the job list.
    func startDuoServices() {
        Task { await DuoGuestTools.install(on: host) }
        let jobs = DuoJobCenter.shared
        jobs.onLeftoverJobs = { [weak self] leftovers in
            let names = leftovers.map { "“\($0.title)”" }.joined(separator: ", ")
            self?.notify("\(names) stopped when iOS closed LinPad. Start \(leftovers.count == 1 ? "it" : "them") again; your windows are back where they were.",
                         action: DesktopToast.Action(title: "OK") {}, lifetime: .seconds(30))
        }
        DuoAskService.shared.start(guestRoot: (host as? any LinuxGraphicsHost)?.guestRootURL)
        jobs.onTick.append { DuoAskService.shared.poll() }
        jobs.start(host: host)
        DuoActions.shared.desktopIsReady(self)
        duoGuard.start(host: host)
        Task { [weak self] in
            while !Task.isCancelled {
                await self?.warnIfRemoteLoginRuns()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    /// LinPad ships no SSH server; one the user installed and started is worth a warning,
    /// once per launch: anyone on the same network who knows a password can then log in.
    private func warnIfRemoteLoginRuns() async {
        guard !duoWarnedAboutRemoteLogin else { return }
        let result = await host.run("pidof sshd dropbear >/dev/null 2>&1")
        guard result.succeeded else { return }
        duoWarnedAboutRemoteLogin = true
        notify("Remote login (SSH) is running in Linux. Anyone on your Wi-Fi who knows a password can log in. Stop it with: rc-service sshd stop",
               action: DesktopToast.Action(title: "OK") {}, lifetime: .seconds(30))
    }

    /// The place the desktop is shown right now, for Linux app sizes.
    var duoScreenProfile: DuoScreenProfile {
        DuoDisplayRouter.shared.isOnExternalDisplay ? .externalDisplay : DuoScreenProfile.forPose(pose.pose)
    }

    func duoPoseChanged() {
        DuoScaling.shared.setProfile(duoScreenProfile)
        updatePoseLayout()
    }

    /// Outer screen: one window at a time (Phase 5). Book pose: two sides (Phase 6).
    /// Anything else: the normal desktop. Called on pose, fold, size and setting changes.
    func updatePoseLayout() {
        let manager = windowManager
        let layout: PoseLayout?
        // On a monitor the fold says nothing about where windows should go.
        guard !DuoDisplayRouter.shared.isOnExternalDisplay else { return manager.setPoseLayout(nil) }
        switch pose.pose {
        case .closed, .tent:
            layout = DuoSettings.isOn(DuoSettings.outerScreenModeKey) ? .single : nil
        case .book:
            layout = DuoSettings.isOn(DuoSettings.bookSplitKey) ? bookSides(in: manager.desktopSize) : nil
        case .flat, .laptop, .noHinge:
            layout = nil
        }
        manager.setPoseLayout(layout)
    }

    /// The halves of the desktop either side of the fold, or of its middle when iOS has not
    /// said where the fold is.
    private func bookSides(in size: CGSize) -> PoseLayout? {
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = windowManager.desktopGlobalOrigin
        var gapStart = (size.width / 2).rounded()
        var gapEnd = gapStart
        if let fold = pose.foldInWindow, fold.height > fold.width {
            gapStart = min(max(fold.minX - origin.x, 0), size.width)
            gapEnd = min(max(fold.maxX - origin.x, gapStart), size.width)
        }
        let gap = windowManager.innerGap
        let leading = CGRect(x: 0, y: 0, width: max(gapStart - gap, 0), height: size.height)
        let trailingX = gapEnd + gap
        let trailing = CGRect(x: trailingX, y: 0, width: max(size.width - trailingX, 0), height: size.height)
        guard leading.width >= 120, trailing.width >= 120 else { return nil }
        return .sides(leading: leading, trailing: trailing)
    }
}
