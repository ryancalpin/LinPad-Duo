import BackgroundTasks
import DesktopKit
import Foundation
import os
import UIKit

/// Settings › Safety and Battery › "Keep jobs running in other apps" (plan Phase 12). A job
/// started with `notify-phone` while LinPad is in front becomes a BGContinuedProcessingTask
/// (iOS 26): iOS lets the app, and with it Linux, keep running after you switch away, and
/// shows the job's progress in its own banner, where it can also be cancelled. iOS decides
/// how long this lasts; developers report these tasks pausing once the phone locks, so
/// "While jobs run" in Settings › Background covers the locked phone.
@available(iOS 26.0, *)
@MainActor
final class DuoContinuedJobs {
    static let shared = DuoContinuedJobs()

    private let log = Logger(subsystem: "app.ish.desktop", category: "continuedJobs")
    /// Job id → the system task carrying it.
    private var tasks: [String: BGContinuedProcessingTask] = [:]
    /// Jobs already submitted (once each, even if iOS refused).
    private var submitted: Set<String> = []
    private var latest: [String: LinuxJob] = [:]
    private var counter = 0
    private var started = false

    /// Info.plist's BGTaskSchedulerPermittedIdentifiers allows "<bundle id>.linuxjob.*".
    private var identifierPrefix: String { (Bundle.main.bundleIdentifier ?? "linpad") + ".linuxjob." }

    func start() {
        guard !started else { return }
        started = true
        DuoJobCenter.shared.observe { [weak self] _, jobs in self?.sync(jobs) }
    }

    private func sync(_ jobs: [LinuxJob]) {
        latest = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, task) in tasks {
            guard let job = latest[id], job.isRunning else {
                tasks[id] = nil
                task.progress.completedUnitCount = task.progress.totalUnitCount
                task.setTaskCompleted(success: latest[id]?.state == .done)
                continue
            }
            report(job, on: task)
        }
        guard DuoSettings.isOn(DuoSettings.continuedJobsKey),
              UIApplication.shared.applicationState == .active else { return }
        // A continued-processing task has to begin while the app is in front.
        for job in jobs where job.isRunning && !submitted.contains(job.id) {
            submit(job)
        }
    }

    private func submit(_ job: LinuxJob) {
        submitted.insert(job.id)
        counter += 1
        let identifier = identifierPrefix + "\(Int(Date().timeIntervalSince1970))-\(counter)"
        let jobID = job.id
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in DuoContinuedJobs.shared.began(task, jobID: jobID) }
        }
        guard registered else {
            log.error("could not register \(identifier, privacy: .public)")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: job.title,
                                                       subtitle: job.detail.isEmpty ? "Running in Linux" : job.detail)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("continued task for \(job.title, privacy: .public) not accepted: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func began(_ task: BGContinuedProcessingTask, jobID: String) {
        guard let job = latest[jobID], job.isRunning else {
            task.setTaskCompleted(success: latest[jobID]?.state == .done)
            return
        }
        tasks[jobID] = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
            // Cancelled in the system's banner, or iOS needed the resources. The Linux job
            // itself carries on as long as LinPad is allowed to run.
            Task { @MainActor in
                guard let self, let task = self.tasks.removeValue(forKey: jobID) else { return }
                task.setTaskCompleted(success: false)
            }
        }
        report(job, on: task)
    }

    /// Real progress when the job reports it. Otherwise a slow crawl towards 95% from the
    /// time it has run, since iOS ends first the tasks that show no progress at all.
    private func report(_ job: LinuxJob, on task: BGContinuedProcessingTask) {
        let fraction = job.progress ?? min(0.95, Date().timeIntervalSince(job.started) / 1200)
        task.progress.completedUnitCount = Int64((fraction * 100).rounded())
        task.updateTitle(job.title, subtitle: job.detail.isEmpty ? "Running in Linux" : job.detail)
    }
}
