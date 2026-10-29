import Foundation
import OSLog
import Perception
import SwiftUI

/// Settings › Safety and Battery › "Heat and battery guard" (plan Phase 11). When the
/// phone runs hot or Low Power Mode is on, the busiest Linux programs get the lowest
/// priority (renice 19); when iOS says the phone is critically hot, they are paused
/// (SIGSTOP). Everything is put back once the phone cools down or Low Power Mode is off.
/// Linux's own session (ishwl, sound, D-Bus, terminals) is never touched.
@Perceptible @MainActor
final class DuoGuard {
    enum Level: Int, Comparable, Sendable {
        case normal
        case slowed
        case paused

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct BusyProcess: Identifiable, Equatable, Sendable {
        let id: Int32
        let name: String
        /// Share of one CPU core over the last sample, 0...1 (can exceed 1 with threads).
        let cpu: Double
    }

    static let sampleInterval: Duration = .seconds(15)
    /// A program using more than this share of a core counts as busy.
    static let busyThreshold = 0.05
    static let pauseThreshold = 0.2
    /// Never slowed or paused: the desktop session itself.
    static let protectedNames: Set<String> = [
        "init", "ishwl", "ishwl-session", "Xwayland", "pulseaudio", "dbus-daemon", "foot", "footclient",
        "sh", "ash", "bash", "busybox", "ps", "cat", "sleep", "linpad-lifecycle", "notify-phone", "ask",
    ]
    private static let logger = Logger(subsystem: "DesktopKit", category: "DuoGuard")

    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var level = Level.normal
    private(set) var busiest: [BusyProcess] = []
    private(set) var lastChecked: Date?

    @PerceptionIgnored private var host: (any LinuxHost)?
    @PerceptionIgnored private var observers: [NSObjectProtocol] = []
    @PerceptionIgnored private var loop: Task<Void, Never>?
    @PerceptionIgnored private var reniced: Set<Int32> = []
    @PerceptionIgnored private var stopped: Set<Int32> = []

    func start(host: any LinuxHost) {
        guard self.host == nil else { return }
        self.host = host
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.conditionsChanged() }
            })
        }
        conditionsChanged()
    }

    /// The setting was switched, or the phone's temperature or power mode changed.
    func conditionsChanged() {
        thermalState = ProcessInfo.processInfo.thermalState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let wanted: Level
        if !DuoSettings.isOn(DuoSettings.heatGuardKey) {
            wanted = .normal
        } else if thermalState == .critical {
            wanted = .paused
        } else if thermalState == .serious || isLowPowerMode {
            wanted = .slowed
        } else {
            wanted = .normal
        }
        guard wanted != level else { return }
        level = wanted
        Self.logger.info("guard level \(wanted.rawValue) (thermal \(self.thermalState.rawValue), low power \(self.isLowPowerMode))")
        if wanted == .normal {
            loop?.cancel()
            loop = nil
            Task { await restoreAll() }
        } else if loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.enforce()
                    try? await Task.sleep(for: Self.sampleInterval)
                }
            }
        }
    }

    var statusText: String {
        let heat = switch thermalState {
        case .nominal: "Normal temperature"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown temperature"
        }
        let power = isLowPowerMode ? " · Low Power Mode" : ""
        let action = switch level {
        case .normal: ""
        case .slowed: " · slowing busy Linux programs"
        case .paused: " · busy Linux programs paused"
        }
        return heat + power + action
    }

    /// Settings' "Check Now": which programs use the most CPU right now.
    func refreshBusiest() async {
        busiest = await sample()
        lastChecked = Date()
    }

    private func enforce() async {
        guard let host else { return }
        let processes = await sample()
        busiest = processes
        lastChecked = Date()
        let busy = processes.filter { $0.cpu >= Self.busyThreshold && !Self.protectedNames.contains($0.name) }
        let toRenice = busy.map(\.id).filter { !reniced.contains($0) }
        if !toRenice.isEmpty {
            _ = await host.run("renice -n 19 -p \(toRenice.map(String.init).joined(separator: " ")) >/dev/null 2>&1; true")
            reniced.formUnion(toRenice)
        }
        if level == .paused {
            let toStop = busy.filter { $0.cpu >= Self.pauseThreshold }.map(\.id).filter { !stopped.contains($0) }
            if !toStop.isEmpty {
                _ = await host.run("kill -STOP \(toStop.map(String.init).joined(separator: " ")) 2>/dev/null; true")
                stopped.formUnion(toStop)
            }
        } else if !stopped.isEmpty {
            await resumeStopped()
        }
    }

    private func restoreAll() async {
        await resumeStopped()
        guard let host, !reniced.isEmpty else { return }
        let pids = reniced.map(String.init).joined(separator: " ")
        reniced.removeAll()
        _ = await host.run("renice -n 0 -p \(pids) >/dev/null 2>&1; true")
    }

    private func resumeStopped() async {
        guard let host, !stopped.isEmpty else { return }
        let pids = stopped.map(String.init).joined(separator: " ")
        stopped.removeAll()
        _ = await host.run("kill -CONT \(pids) 2>/dev/null; true")
    }

    // MARK: Measuring

    /// Two reads of every /proc/<pid>/stat, two seconds apart, in one command.
    static let sampleCommand = """
        snap() { for f in /proc/[0-9]*/stat; do read -r line < "$f" 2>/dev/null && echo "$line"; done; }
        snap; echo __LINPAD_SPLIT__; sleep 2; snap
        """

    private func sample() async -> [BusyProcess] {
        guard let host else { return [] }
        let result = await host.run(Self.sampleCommand)
        let parts = result.stdout.components(separatedBy: "__LINPAD_SPLIT__")
        guard parts.count == 2 else { return [] }
        return Self.busiest(before: Self.parseStat(parts[0]), after: Self.parseStat(parts[1]), seconds: 2)
    }

    /// pid → (name, utime + stime in clock ticks) from /proc/<pid>/stat lines.
    static func parseStat(_ text: String) -> [Int32: (name: String, ticks: Double)] {
        var result: [Int32: (name: String, ticks: Double)] = [:]
        for line in text.split(separator: "\n") {
            // "123 (name with spaces) S 1 ...": the name is between the first "(" and the last ")".
            guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close,
                  let pid = Int32(line[..<open].trimmingCharacters(in: .whitespaces)) else { continue }
            let name = String(line[line.index(after: open)..<close])
            let fields = line[line.index(after: close)...].split(separator: " ")
            // After the name: state(0) ppid(1) ... utime(11) stime(12).
            guard fields.count > 12, let user = Double(fields[11]), let system = Double(fields[12]) else { continue }
            result[pid] = (name, user + system)
        }
        return result
    }

    static func busiest(before: [Int32: (name: String, ticks: Double)], after: [Int32: (name: String, ticks: Double)],
                        seconds: Double, ticksPerSecond: Double = 100) -> [BusyProcess] {
        after.compactMap { pid, now -> BusyProcess? in
            guard let then = before[pid] else { return nil }
            let cpu = max(now.ticks - then.ticks, 0) / ticksPerSecond / seconds
            return BusyProcess(id: pid, name: now.name, cpu: cpu)
        }
        .filter { $0.cpu > 0.005 }
        .sorted { $0.cpu > $1.cpu }
        .prefix(8)
        .map { $0 }
    }
}

/// Settings › Safety and Battery: the guard's state and what uses the most power.
struct DuoGuardStatus: View {
    let model: DuoGuard
    @Environment(\.desktopTheme) private var theme
    @State private var isChecking = false

    init(guard: DuoGuard) {
        model = `guard`
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(title: "Now") {
                    Text(model.statusText)
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
                if !model.busiest.isEmpty {
                    Text("Using the most power (CPU)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                    ForEach(model.busiest.prefix(5)) { process in
                        HStack {
                            Text(process.name).font(.callout.monospaced())
                            Spacer()
                            Text("\(Int((process.cpu * 100).rounded()))%").font(.callout.monospacedDigit())
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(isChecking ? "Checking…" : "Check Now") {
                        isChecking = true
                        Task {
                            await model.refreshBusiest()
                            isChecking = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(theme.accent)
                    .disabled(isChecking)
                }
            }
        }
    }
}
