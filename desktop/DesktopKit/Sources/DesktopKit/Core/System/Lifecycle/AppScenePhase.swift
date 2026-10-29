import SwiftUI
import UIKit

/// SwiftUI only reports `scenePhase` for scenes it manages. The desktop is a
/// UIHostingController in a UIKit scene, where it stayed `.background` while the app was in
/// use, so everything that pauses in the background (the panel meters, live widgets, the
/// performance overlay) never ran. This derives the phase from UIApplication instead and
/// puts it in the environment for the whole desktop.
struct AppScenePhase: ViewModifier {
    @State private var phase = Self.current

    private static var current: ScenePhase {
        switch UIApplication.shared.applicationState {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .active
        }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.scenePhase, phase)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                phase = .active
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                phase = .inactive
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                phase = .background
            }
    }
}
