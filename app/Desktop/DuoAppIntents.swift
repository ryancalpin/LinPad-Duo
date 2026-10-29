import AppIntents
import DesktopKit
import Foundation

// Shortcuts, Siri, the Action button and Spotlight (plan Phase 10). Each opens LinPad and
// hands the request to DesktopKit's DuoActions, which waits for Linux to finish starting if
// it has to. Settings › iPhone Duo › "Shortcuts, Siri and widgets" turns them off.

@available(iOS 16.0, *)
struct DuoIntentError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Shortcuts are turned off in LinPad: Settings › iPhone Duo › Shortcuts, Siri and widgets."
    }
}

@available(iOS 16.0, *)
struct OpenWorkspaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Open LinPad Workspace"
    static var description = IntentDescription("Opens LinPad on one of its workspaces.")
    static var openAppWhenRun = true

    @Parameter(title: "Workspace", default: 1, inclusiveRange: (1, 9))
    var workspace: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        try DesktopKitIntentRunner.run(.openWorkspace(workspace))
        return .result()
    }
}

@available(iOS 16.0, *)
struct RunLinuxScriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Script in LinPad"
    static var description = IntentDescription("Opens LinPad and runs a command or script in a terminal, for example ~/scripts/backup.sh.")
    static var openAppWhenRun = true

    @Parameter(title: "Command or script")
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult {
        try DesktopKitIntentRunner.run(.runCommand(command))
        return .result()
    }
}

@available(iOS 16.0, *)
struct StartDevSetupIntent: AppIntent {
    static var title: LocalizedStringResource = "Start My Dev Setup"
    static var description = IntentDescription("Opens LinPad and runs ~/.config/linpad/dev-setup.sh, or opens VS Code and a terminal if there is no such script.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try DesktopKitIntentRunner.run(.startDevSetup)
        return .result()
    }
}

@available(iOS 16.0, *)
@MainActor
enum DesktopKitIntentRunner {
    static func run(_ action: DuoAction) throws {
        if DuoActions.shared.perform(action) == .disabled { throw DuoIntentError() }
    }
}

@available(iOS 16.0, *)
struct LinPadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDevSetupIntent(), phrases: [
            "Start my dev setup in \(.applicationName)",
            "Start coding in \(.applicationName)",
        ])
        AppShortcut(intent: OpenWorkspaceIntent(), phrases: [
            "Open a \(.applicationName) workspace",
        ])
    }
}
