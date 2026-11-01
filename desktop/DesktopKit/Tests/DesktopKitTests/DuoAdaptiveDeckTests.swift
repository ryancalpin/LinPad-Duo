import SwiftUI
import UIKit
import XCTest
@testable import DesktopKit

@MainActor
final class DuoAdaptiveDeckTests: XCTestCase {
    private let left: [DuoDeckAction] = [.terminal, .files, .none]
    private let right: [DuoDeckAction] = [.returnKey, .commandMenu, .none]

    func testTallPadFitsEveryButton() {
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 200)
        XCTAssertEqual(fit.left, [.terminal, .files])
        XCTAssertEqual(fit.right, [.returnKey, .commandMenu])
        XCTAssertEqual(fit.overflow, [])
    }

    func testShortPadMovesButtonsIntoMore() {
        // Two 44 pt slots: the mic or "…" plus one custom button per column.
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 96)
        XCTAssertEqual(fit.left, [.terminal])
        XCTAssertEqual(fit.right, [.returnKey])
        XCTAssertEqual(fit.overflow, [.files, .commandMenu])
    }

    func testTinyPadKeepsOnlyMicAndMore() {
        let fit = DuoAdaptiveColumns.fit(left: left, right: right, height: 30)
        XCTAssertEqual(fit.left, [])
        XCTAssertEqual(fit.right, [])
        XCTAssertEqual(fit.overflow, [.terminal, .files, .returnKey, .commandMenu])
    }

    func testAdaptiveIsTheDefaultStyle() {
        XCTAssertEqual(DuoDeckStyle.allCases.first, .adaptive)
        XCTAssertEqual(DuoDeckStyle.storageKey, "duo.deck.style")
    }

    /// Renders the deck in both states to PNGs for a visual check. Opt-in, because it hosts
    /// SwiftUI in a window: set TEST_RUNNER_DECK_SNAPSHOT_DIR when running xcodebuild.
    func testSnapshots() async throws {
        guard let directory = ProcessInfo.processInfo.environment["DECK_SNAPSHOT_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_DECK_SNAPSHOT_DIR to render deck snapshots")
        }
        let controller = DesktopController(host: MockLinuxHost(latency: .zero), apps: BuiltinApps.all())
        let sizes = [("laptop", CGSize(width: 669, height: 465)), ("narrow", CGSize(width: 466, height: 300)),
                     ("monitor", CGSize(width: 669, height: 900))]
        for (name, size) in sizes {
            for typing in [false, true] {
                if controller.duoTypingFocus.showsKeyboard != typing { controller.duoTypingFocus.toggleKeyboard() }
                let host = UIHostingController(rootView: DuoAdaptiveDeck(controller: controller, showsKeyboard: true)
                    .background(DuoDeckColors.background).environment(\.colorScheme, .dark))
                let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene).map(UIWindow.init(windowScene:))
                    ?? UIWindow(frame: .zero)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(400))
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: size).image { context in
                    // Without a host app, drawHierarchy has no screen to draw from and returns
                    // false; the layer tree still holds the rendered SwiftUI.
                    if !host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true) {
                        host.view.layer.render(in: context.cgContext)
                    }
                }
                let url = URL(fileURLWithPath: directory).appendingPathComponent("deck-\(name)-\(typing ? "typing" : "idle").png")
                try XCTUnwrap(image.pngData()).write(to: url)
                window.rootViewController = nil
                window.isHidden = true
                window.windowScene = nil
            }
        }
    }
}
