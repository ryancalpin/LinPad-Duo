import Foundation
import OSLog
import Perception

/// A long Linux job announced with `notify-phone` (Core/Duo/DuoGuestTools).
public struct LinuxJob: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable {
        case running
        case done
        case failed
    }

    public let id: String
    public var title: String
    public var state: State
    /// 0...1, or nil when the job does not say how far it is.
    public var progress: Double?
    public var detail: String
    public var started: Date
    public var updated: Date

    public var isRunning: Bool { state == .running }

    /// Parses a job file: `key=value` lines, as notify-phone writes them.
    static func parse(id: String, _ text: String) -> LinuxJob? {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        guard let title = fields["title"], let state = fields["state"].flatMap(State.init(rawValue:)) else { return nil }
        func date(_ key: String) -> Date? { fields[key].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) }
        let progress = fields["progress"].flatMap(Double.init).map { min(max($0 / 100, 0), 1) }
        return LinuxJob(id: id, title: title, state: state, progress: progress, detail: fields["detail"] ?? "",
                        started: date("started") ?? Date(), updated: date("updated") ?? Date())
    }
}

/// A program that looks like a long job without having said so (a build, Claude Code),
/// found with `ps` while the tent board is up.
struct DetectedLinuxProcess: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let seconds: Int
}

/// Every job `notify-phone` announced, read from the guest's /tmp/linpad-duo/jobs every
/// two seconds. The tent board (Phase 7), Live Activities (Phase 10) and keeping jobs
/// running in other apps (Phase 12) all follow it.
@Perceptible @MainActor
public final class DuoJobCenter {
    public static let shared = DuoJobCenter()
    static let pollInterval: Duration = .seconds(2)
    /// Finished jobs stay listed this long.
    static let finishedLifetime: TimeInterval = 30 * 60
    private static let logger = Logger(subsystem: "DesktopKit", category: "DuoJobs")

    /// Newest first.
    public private(set) var jobs: [LinuxJob] = []
    private(set) var detected: [DetectedLinuxProcess] = []

    @PerceptionIgnored private var host: (any LinuxHost)?
    @PerceptionIgnored private var jobsURL: URL?
    @PerceptionIgnored private var loop: Task<Void, Never>?
    @PerceptionIgnored private var modified: [String: Date] = [:]
    @PerceptionIgnored private var observers: [@MainActor ([LinuxJob], [LinuxJob]) -> Void] = []
    /// Other guest requests read on the same tick (`ask`).
    @PerceptionIgnored var onTick: [@MainActor () async -> Void] = []
    /// Job ids this launch has already seen running; anything else running at the first
    /// read is left over from a LinPad that iOS closed (Phase 12).
    @PerceptionIgnored private var hasRead = false
    @PerceptionIgnored var onLeftoverJobs: (@MainActor ([LinuxJob]) -> Void)?

    public var runningJobs: [LinuxJob] { jobs.filter(\.isRunning) }

    /// Called with the old and new list after every change.
    public func observe(_ observer: @escaping @MainActor (_ old: [LinuxJob], _ new: [LinuxJob]) -> Void) {
        observers.append(observer)
    }

    func start(host: any LinuxHost) {
        guard loop == nil else { return }
        self.host = host
        jobsURL = (host as? any LinuxGraphicsHost)?.guestRootURL?
            .appendingPathComponent(String(DuoGuestTools.jobsDirectory.dropFirst()), isDirectory: true)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func tick() async {
        readJobs()
        for handler in onTick { await handler() }
    }

    private func readJobs() {
        guard let jobsURL else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: jobsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        var next: [String: LinuxJob] = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var present = Set<String>()
        for file in files where file.pathExtension == "job" {
            let id = file.deletingPathExtension().lastPathComponent
            present.insert(id)
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard date != modified[id] || next[id] == nil else { continue }
            modified[id] = date
            if let text = try? String(contentsOf: file, encoding: .utf8), let job = LinuxJob.parse(id: id, text) {
                next[id] = job
            }
        }
        let now = Date()
        let list = next.values
            .filter { present.contains($0.id) && ($0.isRunning || now.timeIntervalSince($0.updated) < Self.finishedLifetime) }
            .sorted { $0.started > $1.started }
        if !hasRead {
            hasRead = true
            let leftovers = list.filter(\.isRunning)
            if !leftovers.isEmpty {
                onLeftoverJobs?(leftovers)
                markCutOff(leftovers)
                return
            }
        }
        guard list != jobs else { return }
        let old = jobs
        jobs = list
        for observer in observers { observer(old, list) }
        removeOldFiles(next.values.filter { !$0.isRunning && now.timeIntervalSince($0.updated) >= Self.finishedLifetime })
    }

    /// Jobs still marked running from a LinPad that iOS closed: their programs died with it.
    private func markCutOff(_ leftovers: [LinuxJob]) {
        guard let host else { return }
        let ids = leftovers.map { $0.id.shellQuoted }.joined(separator: " ")
        Task {
            _ = await host.run("for id in \(ids); do notify-phone fail \"$id\" 'Cut off when iOS closed LinPad'; done")
            modified.removeAll()
        }
    }

    private func removeOldFiles(_ old: [LinuxJob]) {
        guard let host, !old.isEmpty else { return }
        let paths = old.map { "\(DuoGuestTools.jobsDirectory)/\($0.id).job".shellQuoted }.joined(separator: " ")
        Task { _ = await host.run("rm -f \(paths)") }
    }

    // MARK: Programs that look like long jobs

    static let longJobNames = ["claude", "make", "ninja", "cargo", "rustc", "gcc", "cc1", "cc1plus", "clang", "go",
                               "npm", "pnpm", "yarn", "gradle", "apk", "pytest", "tsc", "webpack", "vite", "meson"]

    /// One `ps` while the tent board is on screen; programs running for over 30 seconds.
    func refreshDetected() async {
        guard let host else { return }
        let result = await host.run("ps -o pid,etime,args 2>/dev/null")
        guard result.succeeded else { return }
        detected = Self.parseProcesses(result.stdout)
    }

    static func parseProcesses(_ output: String) -> [DetectedLinuxProcess] {
        output.split(separator: "\n").dropFirst().compactMap { line -> DetectedLinuxProcess? in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int(fields[0]) else { return nil }
            let seconds = elapsedSeconds(String(fields[1]))
            let words = fields[2].split(separator: " ").map { $0.split(separator: "/").last.map(String.init) ?? "" }
            guard seconds >= 30, let name = words.prefix(3).first(where: { longJobNames.contains($0) }) else { return nil }
            return DetectedLinuxProcess(id: pid, name: name == "claude" ? "Claude Code" : name, seconds: seconds)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    /// `ps` elapsed time: "MM:SS", "HH:MM:SS", "D-HH:MM:SS", or busybox's "12m"/"3h"/"2d".
    static func elapsedSeconds(_ text: String) -> Int {
        if let unit = text.last, "mhd".contains(unit), let value = Int(text.dropLast()) {
            return value * (unit == "m" ? 60 : unit == "h" ? 3600 : 86400)
        }
        var days = 0
        var clock = Substring(text)
        if let dash = text.firstIndex(of: "-") {
            days = Int(text[..<dash]) ?? 0
            clock = text[text.index(after: dash)...]
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return days * 86400 + seconds
    }
}
