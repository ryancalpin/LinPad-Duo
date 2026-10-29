import ActivityKit
import DesktopKit
import Foundation
import os

/// `notify-phone` jobs as Live Activities (plan Phase 10): each running job gets one in the
/// Dynamic Island and on the Lock Screen, updated as its progress changes and ended when it
/// finishes. The LinPadDuoWidgets extension draws them; without it iOS shows nothing, and
/// this does no harm. Settings › iPhone Duo › "Live Activities for long jobs".
@available(iOS 16.2, *)
@MainActor
final class DuoLiveActivities {
    static let shared = DuoLiveActivities()
    /// A finished job's activity stays on the Lock Screen this long.
    private static let finishedLinger: TimeInterval = 15 * 60

    private let log = Logger(subsystem: "app.ish.desktop", category: "liveActivities")
    private var activities: [String: Activity<LinuxJobAttributes>] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        // Activities from a LinPad that iOS closed: their jobs were cut off with it.
        for activity in Activity<LinuxJobAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        DuoJobCenter.shared.observe { [weak self] _, jobs in self?.sync(jobs) }
    }

    private var isEnabled: Bool {
        DuoSettings.isOn(DuoSettings.liveActivitiesKey) && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func sync(_ jobs: [LinuxJob]) {
        let byID = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, activity) in activities where byID[id] == nil {
            activities[id] = nil
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        for job in jobs {
            let content = ActivityContent(state: Self.state(for: job), staleDate: nil)
            if let activity = activities[job.id] {
                if job.isRunning {
                    Task { await activity.update(content) }
                } else {
                    activities[job.id] = nil
                    Task { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(Self.finishedLinger))) }
                }
            } else if job.isRunning && isEnabled {
                let attributes = LinuxJobAttributes(jobID: job.id, title: job.title, started: job.started)
                do {
                    activities[job.id] = try Activity.request(attributes: attributes, content: content, pushType: nil)
                } catch {
                    log.error("Live Activity for \(job.title, privacy: .public) not started: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private static func state(for job: LinuxJob) -> LinuxJobAttributes.ContentState {
        LinuxJobAttributes.ContentState(progress: job.progress, detail: job.detail, state: job.state.rawValue)
    }
}
