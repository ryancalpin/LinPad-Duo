import GameController
import Perception
import SwiftUI

// USB-C devices (plan Phase 8), with public iOS APIs only. iOS gives apps a USB drive
// through the Files picker, a controller through GameController, and keyboards, mice,
// audio and Ethernet to every app on its own. It gives no app raw USB access: serial
// cables, Arduinos and printers that need their own drivers cannot reach Linux.

/// Settings › USB: connect and eject drives, see controllers, and what iOS allows.
struct DuoUSBSettingsSection: View {
    let host: any LinuxHost
    @Environment(\.desktopTheme) private var theme
    private let places = IPadPlaceStore.shared
    @State private var error: String?
    @State private var busy: String?
    private let controllers = DuoControllerKeys.shared

    var body: some View {
        WithPerceptionTracking {
            SettingsSection(title: "USB", symbol: "cable.connector") {
                if let error {
                    InlineBanner(kind: .error, message: error)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ForEach(places.usbDrives) { drive in
                    WithPerceptionTracking {
                        SettingsRow(title: drive.name) {
                            Text(isReachable(drive) ? drive.mountPoint : "Unplugged")
                                .font(.caption.monospaced())
                                .foregroundStyle(theme.secondaryText)
                            Button(busy == drive.mountPoint ? "Ejecting…" : "Eject") { eject(drive) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(busy != nil)
                                .accessibilityIdentifier("settings.usb.eject.\(drive.name)")
                        }
                    }
                }
                HStack {
                    Button("Connect Drive…") { connect() }
                        .buttonStyle(.bordered)
                        .tint(theme.accent)
                        .disabled(!(host is any HostDirectoryMounting) || busy != nil)
                        .accessibilityIdentifier("settings.usb.connect")
                    Spacer()
                }
                Text("Plug in a USB stick or drive, tap Connect Drive and pick the drive (or a folder on it) under Locations. Linux sees it at /mnt/usb and ~/USB. Eject before unplugging, so Linux has written everything.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ThemedSeparator()
                SettingsRow(title: "Controllers") {
                    Text(controllers.connectedNames.isEmpty ? "None connected" : controllers.connectedNames.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Text("Keyboards, mice, trackpads, headsets, microphones, audio interfaces, Ethernet adapters and monitors work as they do in any app. iOS does not let apps reach other USB devices directly, so serial cables, Arduinos and printers that need their own drivers can't be used from Linux.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isReachable(_ drive: IPadPlace) -> Bool {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: drive.bookmark, bookmarkDataIsStale: &stale) else { return false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func connect() {
        error = nil
        Task {
            do {
                _ = try await places.addFolder(host: host, under: IPadPlaceStore.usbMountRoot)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Writes Linux's cached data out first, then unmounts.
    private func eject(_ drive: IPadPlace) {
        error = nil
        busy = drive.mountPoint
        Task {
            _ = await host.run("sync")
            do {
                try await places.eject(drive, host: host)
            } catch {
                self.error = "\(drive.name) is still in use. Close the Linux apps or terminals using it, then eject again. (\(error.localizedDescription))"
            }
            busy = nil
        }
    }
}

/// Game controllers type keys into the focused Linux app: most Linux games and emulators
/// can be played with the keyboard, and iOS offers no way to add a Linux joystick device
/// without changing the emulator's kernel (a later, bigger job).
@Perceptible @MainActor
final class DuoControllerKeys {
    static let shared = DuoControllerKeys()

    /// Linux evdev codes.
    private enum Key {
        static let up: UInt32 = 103, down: UInt32 = 108, left: UInt32 = 105, right: UInt32 = 106
        static let space: UInt32 = 57, escape: UInt32 = 1, enter: UInt32 = 28, tab: UInt32 = 15
        static let pageUp: UInt32 = 104, pageDown: UInt32 = 109, leftShift: UInt32 = 42, leftControl: UInt32 = 29
    }

    private(set) var connectedNames: [String] = []
    @PerceptionIgnored weak var controller: DesktopController?
    @PerceptionIgnored private var observers: [NSObjectProtocol] = []
    @PerceptionIgnored private var held: Set<UInt32> = []

    func start(controller: DesktopController) {
        self.controller = controller
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        let all = GCController.controllers()
        connectedNames = all.map { $0.vendorName ?? "Controller" }
        for gamepad in all.compactMap(\.extendedGamepad) { attach(gamepad) }
    }

    private func attach(_ pad: GCExtendedGamepad) {
        func bind(_ button: GCControllerButtonInput?, _ code: UInt32) {
            button?.pressedChangedHandler = { [weak self] _, _, pressed in
                MainActor.assumeIsolated { self?.send(code, pressed: pressed) }
            }
        }
        bind(pad.dpad.up, Key.up)
        bind(pad.dpad.down, Key.down)
        bind(pad.dpad.left, Key.left)
        bind(pad.dpad.right, Key.right)
        bind(pad.buttonA, Key.space)
        bind(pad.buttonB, Key.escape)
        bind(pad.buttonX, Key.enter)
        bind(pad.buttonY, Key.tab)
        bind(pad.leftShoulder, Key.pageUp)
        bind(pad.rightShoulder, Key.pageDown)
        bind(pad.leftTrigger, Key.leftShift)
        bind(pad.rightTrigger, Key.leftControl)
        bind(pad.buttonMenu, Key.enter)
        bind(pad.buttonOptions, Key.escape)
        // The left stick works as the D-pad once pushed past halfway.
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                self?.send(Key.left, pressed: x < -0.5)
                self?.send(Key.right, pressed: x > 0.5)
                self?.send(Key.up, pressed: y > 0.5)
                self?.send(Key.down, pressed: y < -0.5)
            }
        }
    }

    private func send(_ code: UInt32, pressed: Bool) {
        guard DuoSettings.isOn(DuoSettings.controllerKeysKey), let controller, let bridge = controller.linux else { return }
        // Only changes: the stick reports continuously.
        guard pressed != held.contains(code) else { return }
        if pressed { held.insert(code) } else { held.remove(code) }
        let focused = controller.windowManager.focusedWindowID
        let surface = controller.linuxWindows.first { $0.value == focused }?.key
        bridge.key(code, pressed: pressed, focusedSurface: surface)
        controller.idle.noteActivity()
    }
}
