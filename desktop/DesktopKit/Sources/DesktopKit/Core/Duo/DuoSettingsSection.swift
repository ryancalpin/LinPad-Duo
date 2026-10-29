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
                row("Outer screen: one window at a time", $outerScreenMode, id: "outerScreen",
                    "When the phone closes, each window fills the small screen; the button in the corner lists them to switch. Linux keeps running, and opening the phone puts every window back.")
                row("Book pose: two sides", $bookSplit, id: "bookSplit",
                    "Half-open like a book, each half of the screen holds its own windows and nothing sits across the fold. Drag a window by its title bar to either side; the button on the fold swaps them.")
                row("Tent pose status board", $tentBoard, id: "tentBoard",
                    "Standing up like a tent, the outer screen shows the time, CPU and memory, and long jobs: anything started with notify-phone, builds and Claude Code. Tap it to see the desktop.")
            }
            DuoScaleSettings()
                .onChangeCompat(of: autoScale) { _, _ in DuoScaling.shared.refresh() }
            SettingsSection(title: "Phone Features", symbol: "iphone") {
                row("Controllers type keys", $controllerKeys, id: "controllerKeys",
                    "A game controller presses keys in the focused Linux app: the D-pad and left stick are the arrow keys, A is Space, B is Escape, X is Return, Y is Tab, the shoulders are Page Up and Down, the triggers Shift and Ctrl.")
                row("Use a USB-C monitor", $externalDisplay, id: "externalDisplay",
                    "A connected monitor shows the whole desktop, at its own size (Screen Sizes › Monitor), and the phone becomes its keyboard and trackpad. Off, the monitor mirrors the phone.")
                if DuoDisplayRouter.shared.hasExternalDisplay && !DuoDisplayRouter.shared.isOnExternalDisplay {
                    Button("Show on Monitor") { DuoDisplayRouter.shared.moveToExternal() }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                }
                row("Live Activities for long jobs", $liveActivities, id: "liveActivities",
                    "Jobs started with notify-phone show their progress in the Dynamic Island and on the Lock Screen; tap one to come back to LinPad. Try: notify-phone run \"Build\" -- make")
                row("Shortcuts, Siri and widgets", $shortcuts, id: "shortcuts",
                    "The Shortcuts app, Siri, the Action button and LinPad's Home Screen widget can open a workspace, open a terminal, run a script, or start your dev setup (~/.config/linpad/dev-setup.sh).")
                row("On-device AI (ask)", $onDeviceAI, id: "onDeviceAI",
                    "In a terminal, ask \"a question\" answers with Apple's on-device model, with no internet. Needs Apple Intelligence on, and LinPad in front while it answers.")
            }
            .onChangeCompat(of: externalDisplay) { _, on in
                if on { DuoDisplayRouter.shared.moveToExternal() } else { DuoDisplayRouter.shared.moveToPhone() }
            }
            if let controller { DuoUSBSettingsSection(host: controller.host) }
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
