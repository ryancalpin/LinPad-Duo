import Perception
import SwiftUI
import UIKit

/// The places the desktop can appear, each with its own size for Linux apps (plan Phase 3).
enum DuoScreenProfile: String, CaseIterable, Identifiable, Sendable {
    /// An iPad or a phone without a hinge: Linux apps stay as they always were.
    case standard
    case outerScreen
    case innerFlat
    /// One half of the inner screen in book pose.
    case bookHalf
    /// The top half of the inner screen in laptop pose.
    case laptopTop
    case externalDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .outerScreen: "Outer screen"
        case .innerFlat: "Inner screen"
        case .bookHalf: "Book pose (each half)"
        case .laptopTop: "Laptop pose (top half)"
        case .externalDisplay: "Monitor"
        }
    }

    /// Smaller than 100% fits more of a Linux app on a small area; larger makes it easier to read.
    var defaultPercent: Double {
        switch self {
        case .standard, .innerFlat, .externalDisplay: 100
        case .outerScreen: 85
        case .bookHalf: 80
        case .laptopTop: 90
        }
    }

    static func forPose(_ pose: DuoPose) -> DuoScreenProfile {
        switch pose {
        case .noHinge: .standard
        case .closed, .tent: .outerScreen
        case .flat: .innerFlat
        case .book: .bookHalf
        case .laptop: .laptopTop
        }
    }
}

/// How big Linux apps are drawn: one Linux pixel is `zoom` points. A zoom below 1 gives the
/// app more pixels than the window has points (it lays out as on a bigger screen and the
/// picture is drawn smaller), above 1 the opposite. The app is told its new size, so it
/// redraws at once, sharp, with no restart: the window's content is what is scaled, not a
/// picture of it. ishwl keeps rendering at its own output scale (2x by default), so text
/// stays crisp down to about 50%.
///
/// The zoom is the screen profile's percentage, times the iPhone's text size (Settings ›
/// Display & Brightness › Text Size) when "Follow text size" is on, times the app's own
/// percentage. On an iPad or with Settings › iPhone Duo › "Size Linux apps" off it is only
/// the app's own percentage, which defaults to 100%.
@Perceptible @MainActor
final class DuoScaling {
    static let shared = DuoScaling()
    static let percentRange: ClosedRange<Double> = 50...160
    static let followsTextSizeKey = "duo.scale.followsTextSize"
    private static let appOverridesKey = "duo.scale.apps"
    static let changedNotification = Notification.Name("DuoScalingChanged")

    private(set) var profile = DuoScreenProfile.standard
    /// Bumped on every change, so views that only read zoom values re-render.
    private(set) var revision = 0
    @PerceptionIgnored private let defaults: UserDefaults
    @PerceptionIgnored private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observers.append(NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        })
    }

    func setProfile(_ profile: DuoScreenProfile) {
        guard profile != self.profile else { return }
        self.profile = profile
        changed()
    }

    // MARK: Settings

    func percent(for profile: DuoScreenProfile) -> Double {
        defaults.object(forKey: Self.key(profile)) as? Double ?? profile.defaultPercent
    }

    func setPercent(_ value: Double, for profile: DuoScreenProfile) {
        defaults.set(Self.clamped(value), forKey: Self.key(profile))
        changed()
    }

    var followsTextSize: Bool {
        get { defaults.object(forKey: Self.followsTextSizeKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.followsTextSizeKey)
            changed()
        }
    }

    /// Per-app percentages, by desktop app id ("linux:code").
    var appPercents: [String: Double] {
        defaults.dictionary(forKey: Self.appOverridesKey) as? [String: Double] ?? [:]
    }

    func appPercent(for appID: String) -> Double {
        appPercents[appID] ?? 100
    }

    func setAppPercent(_ value: Double?, for appID: String) {
        var all = appPercents
        all[appID] = value.map(Self.clamped).flatMap { $0 == 100 ? nil : $0 }
        defaults.set(all, forKey: Self.appOverridesKey)
        changed()
    }

    /// A setting the zoom depends on changed elsewhere (Settings › iPhone Duo).
    func refresh() {
        changed()
    }

    func resetAll() {
        for profile in DuoScreenProfile.allCases { defaults.removeObject(forKey: Self.key(profile)) }
        defaults.removeObject(forKey: Self.appOverridesKey)
        defaults.removeObject(forKey: Self.followsTextSizeKey)
        changed()
    }

    // MARK: The zoom

    /// The scale for a Linux app's windows right now.
    func zoom(forAppID appID: String) -> CGFloat {
        var percent = appPercent(for: appID)
        if profile != .standard && DuoSettings.isOn(DuoSettings.autoScaleKey, in: defaults) {
            percent *= self.percent(for: profile) / 100
            if followsTextSize { percent *= Self.textSizeFactor(UIApplication.shared.preferredContentSizeCategory) }
        }
        return CGFloat(min(max(percent, 40), 200) / 100)
    }

    /// The iPhone's text size, relative to the default ("Large").
    static func textSizeFactor(_ category: UIContentSizeCategory) -> Double {
        switch category {
        case .extraSmall: 0.85
        case .small: 0.9
        case .medium: 0.95
        case .large: 1
        case .extraLarge: 1.1
        case .extraExtraLarge: 1.2
        case .extraExtraExtraLarge: 1.3
        case .accessibilityMedium: 1.4
        case .accessibilityLarge: 1.5
        case .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge: 1.6
        default: 1
        }
    }

    private static func key(_ profile: DuoScreenProfile) -> String { "duo.scale.\(profile.rawValue)" }

    private static func clamped(_ value: Double) -> Double {
        min(max(value.rounded(), percentRange.lowerBound), percentRange.upperBound)
    }

    private func changed() {
        revision += 1
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }
}

/// A Linux toplevel inside its desktop window, drawn at the app's zoom. The surface view
/// keeps Linux's own coordinates: its bounds are the window's size divided by the zoom,
/// and a scale transform draws it at the window's size. UIKit hands touches to it in those
/// untransformed coordinates, so input needs no conversion.
final class LinuxZoomHostView: UIView {
    let surfaceView: LinuxSurfaceView
    let appID: String
    private var observer: NSObjectProtocol?

    init(surfaceView: LinuxSurfaceView, appID: String) {
        self.surfaceView = surfaceView
        self.appID = appID
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(surfaceView)
        observer = NotificationCenter.default.addObserver(
            forName: DuoScaling.changedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setNeedsLayout() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var zoom: CGFloat { DuoScaling.shared.zoom(forAppID: appID) }

    override func layoutSubviews() {
        super.layoutSubviews()
        if surfaceView.superview !== self { addSubview(surfaceView) }
        let zoom = self.zoom
        surfaceView.transform = .identity
        surfaceView.bounds = CGRect(origin: .zero, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        surfaceView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        surfaceView.transform = CGAffineTransform(scaleX: zoom, y: zoom)
    }
}

/// Settings › Screen Sizes.
struct DuoScaleSettings: View {
    @Environment(\.desktopTheme) private var theme
    @Environment(\.desktopController) private var controller
    private let scaling = DuoScaling.shared

    var body: some View {
        WithPerceptionTracking {
            let _ = scaling.revision
            SettingsSection(title: "Screen Sizes", symbol: "textformat.size") {
                Text("How big Linux apps are in each place. Smaller fits more on the screen; bigger is easier to read. Changes apply at once, without restarting apps.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(DuoScreenProfile.allCases.filter { $0 != .standard }) { profile in
                    slider(profile.title + (profile == scaling.profile ? " (now)" : ""),
                           value: Binding(get: { scaling.percent(for: profile) },
                                          set: { scaling.setPercent($0, for: profile) }))
                }
                SettingsRow(title: "Follow the iPhone's text size") {
                    Toggle("Follow the iPhone's text size", isOn: Binding(get: { scaling.followsTextSize },
                                                                          set: { scaling.followsTextSize = $0 }))
                        .labelsHidden()
                        .tint(theme.accent)
                }
                ThemedSeparator()
                Text("Per app").font(.subheadline.weight(.semibold)).foregroundStyle(theme.secondaryText)
                let apps = appIDs
                if apps.isEmpty {
                    Text("Open a Linux app to give it its own size.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                ForEach(apps, id: \.self) { appID in
                    slider(name(of: appID), value: Binding(get: { scaling.appPercent(for: appID) },
                                                           set: { scaling.setAppPercent($0, for: appID) }))
                }
                HStack {
                    Spacer()
                    Button("Reset Sizes") { scaling.resetAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(theme.accent)
                }
            }
        }
    }

    /// Linux apps that are open or already have their own size.
    private var appIDs: [String] {
        let open = controller?.windowManager.windows.map(\.appID).filter { $0.hasPrefix(LinuxAppID.prefix) } ?? []
        return Array(Set(open).union(scaling.appPercents.keys)).sorted { name(of: $0) < name(of: $1) }
    }

    private func name(of appID: String) -> String {
        controller?.launcherApps.first { $0.id == appID }?.name
            ?? String(appID.dropFirst(appID.hasPrefix(LinuxAppID.prefix) ? LinuxAppID.prefix.count : 0))
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int(value.wrappedValue))%").font(.callout.monospacedDigit()).foregroundStyle(theme.secondaryText)
            }
            Slider(value: value, in: DuoScaling.percentRange, step: 5)
                .tint(theme.accent)
                .accessibilityLabel(title)
        }
    }
}
