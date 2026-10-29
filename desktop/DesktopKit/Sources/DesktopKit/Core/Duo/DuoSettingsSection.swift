import Perception
import SwiftUI

/// Settings › iPhone Duo: a switch for each fold and phone feature, with what it does.
struct DuoSettingsSection: View {
    let controller: DesktopController?
    @Environment(\.desktopTheme) private var theme
    @AppStorage(DuoSettings.poseOverlayKey) private var showsPose = false
    @AppStorage(DuoSettings.autoScaleKey) private var autoScale = true
    @AppStorage(DuoSettings.laptopDeckKey) private var laptopDeck = true
    @AppStorage(DuoSettings.outerScreenModeKey) private var outerScreenMode = true
    @AppStorage(DuoSettings.bookSplitKey) private var bookSplit = true
    @AppStorage(DuoSettings.tentBoardKey) private var tentBoard = true
    @AppStorage(DuoSettings.controllerKeysKey) private var controllerKeys = true
    @AppStorage(DuoSettings.externalDisplayKey) private var externalDisplay = true
    @AppStorage(DuoSettings.liveActivitiesKey) private var liveActivities = true
    @AppStorage(DuoSettings.shortcutsKey) private var shortcuts = true
    @AppStorage(DuoSettings.onDeviceAIKey) private var onDeviceAI = true
    @AppStorage(DuoSettings.heatGuardKey) private var heatGuard = true
    @AppStorage(DuoSettings.appLockKey) private var appLock = false
    @AppStorage(DuoSettings.pencilKey) private var pencil = true
    @AppStorage(DuoSettings.continuedJobsKey) private var continuedJobs = false

    var body: some View {
        WithPerceptionTracking {
            SettingsSection(title: "iPhone Duo", symbol: "rectangle.split.2x1") {
                if let controller {
                    SettingsRow(title: "Pose now") {
                        Text(controller.pose.pose.title)
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
                            .accessibilityIdentifier("settings.duo.pose")
                    }
                }
                row("Show pose and hinge angle", $showsPose, id: "poseOverlay",
                    "A small label at the top of the screen with what LinPad thinks the phone is doing. For testing.")
                ThemedSeparator()
                Text("Folding").font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                row("Size Linux apps for each screen", $autoScale, id: "autoScale",
                    "Linux apps get bigger or smaller to suit the outer screen, the inner screen, each half of the fold and a monitor. Adjust each one under Screen Sizes below.")
                row("Laptop pose keyboard and trackpad", $laptopDeck, id: "laptopDeck",
                    "Half-open in landscape, the bottom half becomes a keyboard and trackpad for the desktop on the top half. With a keyboard attached only the trackpad shows; with a keyboard and mouse, neither.")
            }
            DuoScaleSettings()
                .onChangeCompat(of: autoScale) { _, _ in DuoScaling.shared.refresh() }
        }
    }

    private func row(_ title: String, _ value: Binding<Bool>, id: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsRow(title: title) {
                Toggle(title, isOn: value)
                    .labelsHidden()
                    .tint(theme.accent)
                    .accessibilityIdentifier("settings.duo.\(id)")
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
