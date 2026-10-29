import Foundation

/// Something Shortcuts, Siri, the Action button or the Home Screen widget asks LinPad to do
/// (plan Phase 10). The app's App Intents call `DuoActions.shared.perform`; the widget
/// opens `linpad://duo/...` links, which come here too.
public enum DuoAction: Equatable, Sendable {
    /// 1-based, as people count workspaces.
    case openWorkspace(Int)
    case runCommand(String)
    case newTerminal
    /// ~/.config/linpad/dev-setup.sh if it exists, else VS Code and a terminal.
    case startDevSetup

    /// The widget's links: linpad://duo/workspace/2, linpad://duo/terminal, linpad://duo/dev-setup.
    /// Running a command is never accepted from a link, since any web page can open one.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == LinPadLink.scheme, url.host?.lowercased() == "duo" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch path.first {
        case "workspace":
            guard path.count == 2, let number = Int(path[1]), (1...WindowManager.maximumWorkspaces).contains(number) else { return nil }
            self = .openWorkspace(number)
        case "terminal": self = .newTerminal
        case "dev-setup": self = .startDevSetup
        default: return nil
        }
    }

    public var url: URL? {
        switch self {
        case .openWorkspace(let number): URL(string: "linpad://duo/workspace/\(number)")
        case .newTerminal: URL(string: "linpad://duo/terminal")
        case .startDevSetup: URL(string: "linpad://duo/dev-setup")
        case .runCommand: nil
        }
    }
}

@MainActor
public final class DuoActions {
    public static let shared = DuoActions()
    static let devSetupScript = "~/.config/linpad/dev-setup.sh"

    public enum Outcome: Sendable {
        case done
        /// Waiting for Linux to finish starting; it runs then.
        case queued
        /// Settings › iPhone Duo › "Shortcuts, Siri and widgets" is off.
        case disabled
    }

    private weak var controller: DesktopController?
    private var pending: [(DuoAction, Bool)] = []

    /// `fromLink`: the widget (or any app) opened a link, so the dev setup asks first.
    @discardableResult
    public func perform(_ action: DuoAction, fromLink: Bool = false) -> Outcome {
        guard DuoSettings.isOn(DuoSettings.shortcutsKey) else { return .disabled }
        guard let controller, controller.boot.isFinished else {
            pending.append((action, fromLink))
            return .queued
        }
        run(action, fromLink: fromLink, controller: controller)
        return .done
    }

    /// Linux has booted (startDuoServices): run what came in before.
    func desktopIsReady(_ controller: DesktopController) {
        self.controller = controller
        let waiting = pending
        pending.removeAll()
        for (action, fromLink) in waiting { run(action, fromLink: fromLink, controller: controller) }
    }

    private func run(_ action: DuoAction, fromLink: Bool, controller: DesktopController) {
        let manager = controller.windowManager
        switch action {
        case .openWorkspace(let number):
            while manager.workspaceCount < number, manager.addWorkspace() != nil {}
            manager.switchToWorkspace(min(number, manager.workspaceCount) - 1)
        case .runCommand(let command):
            controller.runCommand(command)
        case .newTerminal:
            controller.openLinuxApp(LinuxAppID.preferredTerminal)
        case .startDevSetup where fromLink:
            controller.notify("Start your dev setup?", action: DesktopToast.Action(title: "Start") { [weak self, weak controller] in
                guard let controller else { return }
                self?.run(.startDevSetup, fromLink: false, controller: controller)
            }, lifetime: .seconds(20))
        case .startDevSetup:
            Task {
                let script = Self.devSetupScript
                let exists = await controller.host.run("[ -f \(script) ]").succeeded
                if exists {
                    controller.runCommand("sh \(script)")
                } else {
                    controller.openLinuxApp(LinuxAppID.prefix + "code")
                    controller.openLinuxApp(LinuxAppID.preferredTerminal)
                    controller.notify("Opened VS Code and a terminal. To choose what starts, write \(script).")
                }
            }
        }
    }
}
