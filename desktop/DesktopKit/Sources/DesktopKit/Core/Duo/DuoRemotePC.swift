import Foundation
import Perception
import Security
import SwiftUI

/// "Run on my PC" (plan Phase 12): long commands go over SSH to Ryan's always-on Linux
/// computer and run there inside tmux, so they finish whatever iOS does to LinPad. Their
/// output is fetched again from the PC when asked, or when LinPad comes back to the front.
///
/// The PC's address, user and port are kept in the iOS Keychain. No password is stored
/// anywhere: "Set Up Key" makes an SSH key in Linux (~/.ssh/id_ed25519, readable only by
/// its owner, as SSH requires) and copies its public half to the PC once, after asking for
/// the PC's password in a terminal.
@Perceptible @MainActor
final class DuoRemotePC {
    struct Connection: Codable, Equatable {
        var host = ""
        var user = ""
        var port = 22

        var isValid: Bool {
            Self.isSafe(host) && Self.isSafe(user) && (1...65535).contains(port)
        }

        /// Letters, digits, dots, dashes and underscores (and ":" for IPv6): nothing a shell
        /// could read as anything else.
        static func isSafe(_ value: String) -> Bool {
            !value.isEmpty && value.count <= 253
                && value.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil
                && !value.hasPrefix("-")
        }

        var target: String { "\(user)@\(host)" }
    }

    struct RemoteJob: Codable, Identifiable, Equatable {
        enum Status: String, Codable { case running, finished, unknown }
        let id: String
        let command: String
        let sent: Date
        var status: Status = .running
        var exitCode: Int?
        var output = ""
        var session: String { "linpad-\(id)" }
    }

    private static let jobsKey = "duo.remotePC.jobs"
    private static let keychainService = "LinPadDuo.RemotePC"

    var connection: Connection
    private(set) var jobs: [RemoteJob]
    private(set) var isBusy = false
    var message: String?
    @PerceptionIgnored private weak var controller: DesktopController?
    @PerceptionIgnored private var observer: NSObjectProtocol?

    init(controller: DesktopController) {
        self.controller = controller
        connection = Self.loadConnection() ?? Connection()
        jobs = (UserDefaults.standard.data(forKey: Self.jobsKey))
            .flatMap { try? JSONDecoder().decode([RemoteJob].self, from: $0) } ?? []
        observer = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.jobs.contains(where: { $0.status == .running }) else { return }
                Task { await self.refresh(announce: true) }
            }
        }
    }

    private var host: (any LinuxHost)? { controller?.host }

    // MARK: Connection (Keychain)

    func saveConnection() {
        guard connection.isValid else {
            message = "Check the PC's address and user name: letters, digits, dots and dashes only."
            return
        }
        Self.storeConnection(connection)
        message = "Saved in the iPhone's Keychain."
    }

    private static func keychainQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: "connection"]
    }

    private static func storeConnection(_ connection: Connection) {
        guard let data = try? JSONEncoder().encode(connection) else { return }
        SecItemDelete(keychainQuery() as CFDictionary)
        var item = keychainQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func loadConnection() -> Connection? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Connection.self, from: data)
    }

    // MARK: SSH

    /// `ssh` with the saved connection; BatchMode so it fails instead of asking for a password.
    private func ssh(_ remoteCommand: String) -> String {
        "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -p \(connection.port) "
            + "\(connection.target.shellQuoted) \(remoteCommand.shellQuoted)"
    }

    private static let ensureClient = "command -v ssh >/dev/null 2>&1 || apk add -q openssh-client >/dev/null 2>&1"

    /// Opens a terminal that makes the key (if there is none) and copies it to the PC; the
    /// PC asks for its password there, once.
    func setUpKey() {
        guard connection.isValid else { return saveConnection() }
        saveConnection()
        let target = connection.target.shellQuoted
        controller?.runCommand("""
            \(Self.ensureClient); [ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519; \
            cat ~/.ssh/id_ed25519.pub | ssh -o StrictHostKeyChecking=accept-new -p \(connection.port) \(target) \
            'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' \
            && echo 'Key set up. LinPad can now send jobs to your PC.'
            """)
    }

    /// Starts the command on the PC in its own tmux session, which stays after it ends so
    /// its output and exit code can be read later.
    func send(_ command: String) async {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host, connection.isValid, !command.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        let job = RemoteJob(id: String(Int(Date().timeIntervalSince1970)), command: command, sent: Date())
        let remote = "tmux new-session -d -s \(job.session) \(("sh -c " + command.shellQuoted).shellQuoted) "
            + "&& tmux set-option -t \(job.session) remain-on-exit on"
        let result = await host.run("\(Self.ensureClient); \(ssh(remote))")
        if result.succeeded {
            jobs.insert(job, at: 0)
            save()
            message = "Started on your PC."
        } else {
            message = Self.explain(result)
        }
    }

    /// Fetches each running job's state and the end of its output.
    func refresh(announce: Bool = false) async {
        guard let host, connection.isValid, !jobs.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        for index in jobs.indices where jobs[index].status != .finished || jobs[index].output.isEmpty {
            let session = jobs[index].session
            let remote = """
                tmux list-panes -t \(session) -F '#{pane_dead} #{pane_dead_status}' 2>/dev/null | head -1; \
                echo __LINPAD_OUTPUT__; tmux capture-pane -p -t \(session) -S -200 2>/dev/null
                """
            let result = await host.run(ssh(remote))
            guard result.succeeded || !result.stdout.isEmpty else {
                message = Self.explain(result)
                return
            }
            let parts = result.stdout.components(separatedBy: "__LINPAD_OUTPUT__\n")
            let state = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ") ?? []
            let wasRunning = jobs[index].status == .running
            if state.first == "1" {
                jobs[index].status = .finished
                jobs[index].exitCode = state.count > 1 ? Int(state[1]) : nil
            } else if state.first == "0" {
                jobs[index].status = .running
            } else {
                jobs[index].status = .unknown
            }
            jobs[index].output = parts.count > 1 ? parts[1].trimmingCharacters(in: .newlines) : ""
            if announce && wasRunning && jobs[index].status == .finished {
                let code = jobs[index].exitCode.map { $0 == 0 ? "finished" : "failed (exit \($0))" } ?? "finished"
                controller?.notify("PC job \(jobs[index].command.prefix(40)) \(code).")
            }
        }
        save()
    }

    /// The job's tmux session in a terminal, live.
    func attach(_ job: RemoteJob) {
        controller?.runCommand("ssh -t -p \(connection.port) \(connection.target.shellQuoted) tmux attach -t \(job.session)")
    }

    /// Forgets the job here and closes its tmux session on the PC.
    func remove(_ job: RemoteJob) async {
        jobs.removeAll { $0.id == job.id }
        save()
        if let host { _ = await host.run(ssh("tmux kill-session -t \(job.session) 2>/dev/null; true")) }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(jobs.prefix(20))), forKey: Self.jobsKey)
    }

    private static func explain(_ result: CommandResult) -> String {
        let text = (result.stderr + result.stdout).lowercased()
        if text.contains("permission denied") { return "The PC refused the key. Tap Set Up Key first." }
        if text.contains("could not resolve") || text.contains("timed out") || text.contains("no route") {
            return "Couldn't reach the PC. Is it on, and on the same network (or reachable over the internet)?"
        }
        if text.contains("tmux") && text.contains("not found") { return "Install tmux on the PC first (for example: sudo apt install tmux)." }
        return result.failureDescription
    }
}

/// Settings › Run on My PC.
struct RemotePCSettingsSection: View {
    @Perception.Bindable var remote: DuoRemotePC
    @Environment(\.desktopTheme) private var theme
    @State private var command = ""

    var body: some View {
        WithPerceptionTracking {
            SettingsSection(title: "Run on My PC", symbol: "desktopcomputer") {
                Text("Send long jobs to an always-on Linux computer. They run there in tmux, so they finish even if iOS pauses LinPad. The PC needs SSH and tmux.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                field("PC address", text: remote.binding(\.connection.host), prompt: "192.168.1.20 or mypc.local")
                field("User", text: remote.binding(\.connection.user), prompt: "ryan")
                SettingsRow(title: "Port") {
                    TextField("22", value: remote.binding(\.connection.port), format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                }
                HStack {
                    Button("Save") { remote.saveConnection() }
                    Button("Set Up Key…") { remote.setUpKey() }
                    Spacer()
                    if remote.isBusy { ProgressView().controlSize(.small) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(theme.accent)
                if let message = remote.message {
                    Text(message).font(.caption).foregroundStyle(theme.secondaryText)
                }
                ThemedSeparator()
                HStack {
                    TextField("Command to run on the PC", text: $command)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        .accessibilityIdentifier("settings.remotePC.command")
                    Button("Send") {
                        let text = command
                        Task {
                            await remote.send(text)
                            if remote.message == "Started on your PC." { command = "" }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || !remote.connection.isValid || remote.isBusy)
                }
                ForEach(remote.jobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.command).font(.callout.monospaced()).lineLimit(1)
                            Spacer()
                            Text(statusText(job)).font(.caption).foregroundStyle(theme.secondaryText)
                        }
                        if !job.output.isEmpty {
                            Text(job.output.split(separator: "\n").suffix(6).joined(separator: "\n"))
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 12) {
                            Button("Open in Terminal") { remote.attach(job) }
                            Button("Remove", role: .destructive) { Task { await remote.remove(job) } }
                        }
                        .font(.caption)
                    }
                }
                if !remote.jobs.isEmpty {
                    HStack {
                        Spacer()
                        Button("Refresh") { Task { await remote.refresh() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(remote.isBusy)
                    }
                }
            }
            .task { await remote.refresh() }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        SettingsRow(title: title) {
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 240)
        }
    }

    private func statusText(_ job: DuoRemotePC.RemoteJob) -> String {
        switch job.status {
        case .running: "Running"
        case .finished: job.exitCode.map { $0 == 0 ? "Finished" : "Failed (\($0))" } ?? "Finished"
        case .unknown: "Not found on the PC"
        }
    }
}
