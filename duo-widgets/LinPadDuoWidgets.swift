import ActivityKit
import SwiftUI
import WidgetKit

// LinPad Duo's widget extension: the Live Activity for long Linux jobs (Dynamic Island and
// Lock Screen) and a Home Screen widget with shortcuts into LinPad. DUO-SETUP.md, "Adding
// the widget extension", says how to add this file to a widget target in Xcode. It also needs
// app/Desktop/LinuxJobAttributes.swift in its target.

@main
struct LinPadDuoWidgets: WidgetBundle {
    var body: some Widget {
        LinPadShortcutsWidget()
        if #available(iOS 16.2, *) {
            LinuxJobLiveActivity()
        }
    }
}

// MARK: - Live Activity

@available(iOS 16.2, *)
struct LinuxJobLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LinuxJobAttributes.self) { context in
            LockScreenJobView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(LinuxJobLinks.open)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(context.state.state))
                        .font(.title2)
                        .foregroundStyle(jobTint(context.state.state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context)
                        .font(.callout.monospacedDigit())
                        .frame(maxWidth: 70, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let progress = context.state.progress {
                            ProgressView(value: progress).tint(jobTint(context.state.state))
                        }
                        if !context.state.detail.isEmpty {
                            Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(context.state.state)).foregroundStyle(jobTint(context.state.state))
            } compactTrailing: {
                if let progress = context.state.progress, context.state.state == "running" {
                    Text("\(Int((progress * 100).rounded()))%").font(.caption.monospacedDigit())
                } else {
                    elapsed(context).font(.caption.monospacedDigit()).frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: symbol(context.state.state)).foregroundStyle(jobTint(context.state.state))
            }
            .widgetURL(LinuxJobLinks.open)
        }
    }

    @ViewBuilder
    private func elapsed(_ context: ActivityViewContext<LinuxJobAttributes>) -> some View {
        if context.state.state == "running" {
            Text(context.attributes.started, style: .timer)
        } else {
            Text(context.state.state == "done" ? "Done" : "Failed")
        }
    }
}

private func symbol(_ state: String) -> String {
    switch state {
    case "done": "checkmark.circle.fill"
    case "failed": "xmark.octagon.fill"
    default: "terminal"
    }
}

private func jobTint(_ state: String) -> Color {
    switch state {
    case "done": .green
    case "failed": .red
    default: .blue
    }
}

@available(iOS 16.1, *)
private struct LockScreenJobView: View {
    let attributes: LinuxJobAttributes
    let state: LinuxJobAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol(state.state)).foregroundStyle(jobTint(state.state))
                Text(attributes.title).font(.headline).lineLimit(1)
                Spacer()
                if state.state == "running" {
                    Text(attributes.started, style: .timer).font(.callout.monospacedDigit()).multilineTextAlignment(.trailing)
                } else {
                    Text(state.state == "done" ? "Done" : "Failed").font(.callout)
                }
            }
            if let progress = state.progress, state.state == "running" {
                ProgressView(value: progress).tint(.blue)
            }
            if !state.detail.isEmpty {
                Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Home Screen widget

struct LinPadShortcutsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LinPadShortcuts", provider: ShortcutsProvider()) { _ in
            ShortcutsWidgetView()
        }
        .configurationDisplayName("LinPad")
        .description("Start your dev setup, open a terminal or jump to a workspace.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ShortcutsEntry: TimelineEntry {
    let date = Date()
}

private struct ShortcutsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortcutsEntry { ShortcutsEntry() }
    func getSnapshot(in context: Context, completion: @escaping (ShortcutsEntry) -> Void) { completion(ShortcutsEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortcutsEntry>) -> Void) {
        completion(Timeline(entries: [ShortcutsEntry()], policy: .never))
    }
}

/// The links match DuoAction's (desktop/DesktopKit/Sources/DesktopKit/Core/Duo/DuoActions.swift).
private struct ShortcutsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "terminal").font(.title)
                    Spacer()
                    Text("LinPad").font(.headline)
                    Text("Dev setup").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(URL(string: "linpad://duo/dev-setup"))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LinPad").font(.headline)
                    HStack(spacing: 8) {
                        button("Dev setup", "hammer", "linpad://duo/dev-setup")
                        button("Terminal", "terminal", "linpad://duo/terminal")
                    }
                    HStack(spacing: 8) {
                        button("Workspace 1", "1.square", "linpad://duo/workspace/1")
                        button("Workspace 2", "2.square", "linpad://duo/workspace/2")
                    }
                }
            }
        }
        .widgetBackground()
    }

    private func button(_ title: String, _ symbol: String, _ link: String) -> some View {
        Link(destination: URL(string: link)!) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1)))
        }
    }
}

private extension View {
    /// iOS 17 wants a container background; iOS 16 ignores it.
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            padding()
        }
    }
}
