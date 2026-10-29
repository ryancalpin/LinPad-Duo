import ActivityKit
import Foundation

/// A long Linux job as a Live Activity (Dynamic Island and Lock Screen). Shared by the app
/// (DuoLiveActivities.swift starts and updates them) and the LinPadDuoWidgets extension
/// (which draws them): add this file to both targets.
@available(iOS 16.1, *)
struct LinuxJobAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0...1, or nil when the job doesn't say how far it is.
        var progress: Double?
        var detail: String
        /// "running", "done" or "failed".
        var state: String
    }

    var jobID: String
    var title: String
    var started: Date
}

/// Where a tap on a job's Live Activity goes: LinPad, as it was.
enum LinuxJobLinks {
    static let open = URL(string: "linpad://open")!
}
