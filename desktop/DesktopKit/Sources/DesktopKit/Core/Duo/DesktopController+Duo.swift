import SwiftUI

/// The desktop's reactions to the iPhone Duo's poses (Core/Duo).
extension DesktopController {
    /// Called once from `init`.
    func startDuo() {
        duoPointer.controller = self
        duoKeyboard.controller = self
        pose.observe { [weak self] _, _ in self?.duoPoseChanged() }
        duoPoseChanged()
    }

    /// The place the desktop is shown right now, for Linux app sizes.
    var duoScreenProfile: DuoScreenProfile {
        DuoScreenProfile.forPose(pose.pose)
    }

    func duoPoseChanged() {
        DuoScaling.shared.setProfile(duoScreenProfile)
    }
}
