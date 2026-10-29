import Foundation

/// Settings › iPhone Duo: one switch per Duo feature (UserDefaults keys, via @AppStorage).
/// Features that cost battery are off until turned on; the rest are on, and do nothing on
/// a device without a hinge.
public enum DuoSettings {
    /// The pose and hinge angle in a small label at the top of the screen (Phase 2).
    public static let poseOverlayKey = "duo.poseOverlay"
    /// Linux apps resized for the screen they are on (Phase 3).
    public static let autoScaleKey = "duo.autoScale"
    /// Laptop pose: keyboard and trackpad on the bottom half (Phase 4).
    public static let laptopDeckKey = "duo.laptopDeck"
    /// Closed: one window at a time with a window list, sized for the outer screen (Phase 5).
    public static let outerScreenModeKey = "duo.outerScreenMode"
    /// Book pose: each half of the inner screen holds its own windows (Phase 6).
    public static let bookSplitKey = "duo.bookSplit"
    /// Tent pose: clock, CPU, memory and long jobs on the outer screen (Phase 7).
    public static let tentBoardKey = "duo.tentBoard"
    /// Game controllers type keys into the focused Linux app (Phase 8).
    public static let controllerKeysKey = "duo.controllerKeys"
    /// A USB-C display shows the desktop; the phone becomes its keyboard and trackpad (Phase 9).
    public static let externalDisplayKey = "duo.externalDisplay"
    /// `notify-phone` jobs in the Dynamic Island and on the Lock Screen (Phase 10).
    public static let liveActivitiesKey = "duo.liveActivities"
    /// Shortcuts, Siri and widgets may open workspaces and run scripts (Phase 10).
    public static let shortcutsKey = "duo.shortcuts"
    /// The `ask` command answers with Apple's on-device model (Phase 10).
    public static let onDeviceAIKey = "duo.onDeviceAI"
    /// Slows Linux down when the phone is hot or in Low Power Mode (Phase 11).
    public static let heatGuardKey = "duo.heatGuard"
    /// Face ID or the passcode to open LinPad (Phase 11).
    public static let appLockKey = "duo.appLock"
    /// Apple Pencil draws and writes in Linux apps instead of scrolling (Phase 11).
    public static let pencilKey = "duo.pencil"
    /// Jobs started with `notify-phone` keep running after switching apps (Phase 12).
    public static let continuedJobsKey = "duo.continuedJobs"

    static let defaults: [String: Bool] = [
        poseOverlayKey: false,
        autoScaleKey: true,
        laptopDeckKey: true,
        outerScreenModeKey: true,
        bookSplitKey: true,
        tentBoardKey: true,
        controllerKeysKey: true,
        externalDisplayKey: true,
        liveActivitiesKey: true,
        shortcutsKey: true,
        onDeviceAIKey: true,
        heatGuardKey: true,
        appLockKey: false,
        pencilKey: true,
        continuedJobsKey: false,
    ]

    public static func isOn(_ key: String, in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: key) as? Bool ?? defaults[key] ?? false
    }
}
