import Perception
import SwiftUI

/// Tent pose (plan Phase 7): the phone stands on its edges and the outer screen faces the
/// room, so it shows a status board instead of the desktop: the time, CPU and memory, and
/// long jobs (`notify-phone`, builds, Claude Code). A tap hides it until the pose changes.
struct DuoTentBoard: View {
    let controller: DesktopController
    let dismiss: () -> Void
    private let jobs = DuoJobCenter.shared

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { proxy in
                let wide = proxy.size.width > proxy.size.height
                ZStack {
                    Color.black.ignoresSafeArea()
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 28) {
                                VStack(alignment: .leading, spacing: 18) { clock; meters }
                                    .frame(maxWidth: proxy.size.width * 0.45, alignment: .leading)
                                jobList
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 22) { clock; meters; jobList }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            }
            .task { await controller.systemMonitor.poll(controller.host) }
            .task {
                while !Task.isCancelled {
                    await jobs.refreshDetected()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint("Tap to show the desktop")
        }
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 64, weight: .thin, design: .rounded).monospacedDigit())
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var meters: some View {
        VStack(alignment: .leading, spacing: 10) {
            meter("CPU", controller.systemMonitor.cpuUsage)
            meter("Memory", controller.systemMonitor.memoryUsage)
        }
    }

    private func meter(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "…").font(.headline.monospacedDigit())
            }
            ProgressView(value: value ?? 0).tint(value ?? 0 > 0.85 ? .orange : .green)
        }
        .accessibilityElement(children: .combine)
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jobs").font(.title2.weight(.semibold))
            if jobs.jobs.isEmpty && jobs.detected.isEmpty {
                Text("Nothing running. Start one with\nnotify-phone run \"Build\" -- make")
                    .font(.callout.monospaced())
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(jobs.jobs.prefix(5)) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: job.state == .running ? "gearshape.2" : job.state == .done ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(job.state == .failed ? .red : job.state == .done ? .green : .white)
                        Text(job.title).font(.headline).lineLimit(1)
                        Spacer()
                        Text(job.started, style: .timer).font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                            .opacity(job.isRunning ? 1 : 0)
                    }
                    if job.isRunning {
                        if let progress = job.progress { ProgressView(value: progress).tint(.blue) }
                    }
                    if !job.detail.isEmpty {
                        Text(job.detail).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(jobs.detected.prefix(4)) { process in
                HStack {
                    Image(systemName: process.name == "Claude Code" ? "sparkles" : "hammer")
                    Text(process.name).font(.headline)
                    Spacer()
                    Text(Duration.seconds(process.seconds), format: .time(pattern: .hourMinuteSecond))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
