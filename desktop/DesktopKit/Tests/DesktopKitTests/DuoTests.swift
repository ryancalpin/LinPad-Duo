import UIKit
import XCTest
@testable import DesktopKit

// MARK: - notify-phone jobs

@MainActor
final class DuoJobTests: XCTestCase {
    func testParsesJobFile() throws {
        let job = try XCTUnwrap(LinuxJob.parse(id: "1-2", """
            title=Build test
            state=running
            progress=40
            detail=Linking
            started=1793294022
            updated=1793294030
            """))
        XCTAssertEqual(job.title, "Build test")
        XCTAssertEqual(job.state, .running)
        XCTAssertEqual(job.progress, 0.4)
        XCTAssertEqual(job.detail, "Linking")
        XCTAssertEqual(job.started, Date(timeIntervalSince1970: 1_793_294_022))
    }

    func testEmptyProgressAndBadFiles() {
        XCTAssertNil(LinuxJob.parse(id: "x", "title=A\nstate=done\nprogress=\nstarted=1\nupdated=2\n")?.progress)
        XCTAssertNil(LinuxJob.parse(id: "x", "garbage"))
        XCTAssertNil(LinuxJob.parse(id: "x", "title=A\nstate=paused\n"))
        XCTAssertEqual(LinuxJob.parse(id: "x", "title=a=b\nstate=failed\n")?.title, "a=b")
    }

    func testElapsedTimes() {
        XCTAssertEqual(DuoJobCenter.elapsedSeconds("01:23"), 83)
        XCTAssertEqual(DuoJobCenter.elapsedSeconds("1:02:03"), 3723)
        XCTAssertEqual(DuoJobCenter.elapsedSeconds("2-01:00:00"), 176_400)
        XCTAssertEqual(DuoJobCenter.elapsedSeconds("12m"), 720)
    }

    func testFindsLongJobsInPs() {
        let ps = """
            PID   ELAPSED COMMAND
                1  1:00:00 /sbin/init
              120    05:10 node /usr/local/bin/claude
              130    00:05 make -j4
              140    02:00 /usr/bin/make -j4 all
              150    10:00 vim notes.txt
            """
        XCTAssertEqual(DuoJobCenter.parseProcesses(ps).map(\.name), ["Claude Code", "make"])
    }
}

// MARK: - Heat guard

@MainActor
final class DuoGuardTests: XCTestCase {
    func testCPUFromProcStat() {
        let before = DuoGuard.parseStat("""
            12 (firefox-esr) S 1 12 12 0 -1 0 0 0 0 0 100 50 0 0 20 0 1 0
            13 (my prog) R 1 13 13 0 -1 0 0 0 0 0 10 10 0 0
            """)
        let after = DuoGuard.parseStat("""
            12 (firefox-esr) S 1 12 12 0 -1 0 0 0 0 0 200 90 0 0 20 0 1 0
            13 (my prog) R 1 13 13 0 -1 0 0 0 0 0 11 10 0 0
            """)
        XCTAssertEqual(before[13]?.name, "my prog")
        let busy = DuoGuard.busiest(before: before, after: after, seconds: 2)
        XCTAssertEqual(busy.first?.name, "firefox-esr")
        XCTAssertEqual(busy.first?.cpu ?? 0, 0.7, accuracy: 0.001)
    }
}

// MARK: - Widget links and keys

@MainActor
final class DuoActionTests: XCTestCase {
    func testWidgetLinks() {
        XCTAssertEqual(DuoAction(url: URL(string: "linpad://duo/workspace/2")!), .openWorkspace(2))
        XCTAssertNil(DuoAction(url: URL(string: "linpad://duo/workspace/12")!))
        XCTAssertEqual(DuoAction(url: URL(string: "linpad://duo/terminal")!), .newTerminal)
        XCTAssertEqual(DuoAction(url: URL(string: "linpad://duo/dev-setup")!), .startDevSetup)
        XCTAssertNil(DuoAction(url: URL(string: "linpad://duo/run?cmd=rm")!), "a link must never run a command")
        XCTAssertNil(DuoAction(url: URL(string: "linpad://theme/install")!))
        XCTAssertEqual(DuoAction.openWorkspace(3).url.flatMap(DuoAction.init(url:)), .openWorkspace(3))
    }

    func testKeyboardLayout() {
        let keys = DuoKey.functionRow + DuoKey.rows.flatMap { $0 } + [DuoKey.left, DuoKey.up, DuoKey.down, DuoKey.right]
        XCTAssertEqual(Set(keys.map(\.id)).count, keys.count)
        XCTAssertTrue(keys.contains { $0.code == 1 } && keys.contains { $0.code == 29 } && keys.contains { $0.code == 125 })
        XCTAssertEqual(DuoKey.char(30, "a", "A").text(shifted: true), "A")
        XCTAssertEqual(DuoKey.char(30, "a", "A").label, "A", "letters show capitals, as on a Mac")
        XCTAssertEqual(DuoKey.char(2, "1", "!").shiftedHint, "!")
        // Every row of the main block is the same width, so the keys line up.
        let widths = DuoKey.rows.dropLast().map { $0.reduce(0) { $0 + $1.width } }
            + [DuoKey.rows.last!.reduce(0) { $0 + $1.width } + DuoKey.arrowsWidth]
        for width in widths { XCTAssertEqual(width, 14.5, accuracy: 0.001) }
        XCTAssertEqual(DuoKey.functionRow.compactMap(\.functionLabel).count, 12)
    }
}

// MARK: - Keyboard customization

@MainActor
final class DuoDeckLayoutTests: XCTestCase {
    func testDefaultsAndSaving() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DuoDeckLayoutTests"))
        defaults.removePersistentDomain(forName: "DuoDeckLayoutTests")
        let layout = DuoDeckLayout(defaults: defaults)
        XCTAssertEqual(layout.functionRow.count, 12)
        XCTAssertEqual(layout.micMode, .hold)
        XCTAssertEqual(layout.leftButtons, [.terminal, .files, .none])
        layout.rightButtons[2] = .app("linux:code")
        layout.functionRow[0] = .lockScreen
        layout.micMode = .tap
        let reloaded = DuoDeckLayout(defaults: defaults)
        XCTAssertEqual(reloaded.rightButtons[2], .app("linux:code"))
        XCTAssertEqual(reloaded.functionRow[0], .lockScreen)
        XCTAssertEqual(reloaded.micMode, .tap)
        reloaded.reset()
        XCTAssertEqual(DuoDeckLayout(defaults: defaults).functionRow, DuoDeckLayout.defaultFunctionRow)
    }

    func testEveryBuiltInActionHasAName() {
        for action in DuoDeckAction.builtIn {
            XCTAssertFalse(action.title(in: nil).isEmpty)
            XCTAssertFalse(action.symbol(in: nil).isEmpty)
        }
        XCTAssertEqual(Set(DuoDeckAction.builtIn.map(\.id)).count, DuoDeckAction.builtIn.count)
    }
}

// MARK: - Sizes and poses

@MainActor
final class DuoScalingTests: XCTestCase {
    func testZoomCombinesProfileAndApp() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DuoScalingTests"))
        defaults.removePersistentDomain(forName: "DuoScalingTests")
        defaults.set(false, forKey: DuoScaling.followsTextSizeKey)
        let scaling = DuoScaling(defaults: defaults)
        XCTAssertEqual(scaling.zoom(forAppID: "linux:code"), 1)
        scaling.setProfile(.outerScreen)
        XCTAssertEqual(scaling.zoom(forAppID: "linux:code"), 0.85, accuracy: 0.001)
        scaling.setAppPercent(80, for: "linux:code")
        XCTAssertEqual(scaling.zoom(forAppID: "linux:code"), 0.68, accuracy: 0.001)
        scaling.setProfile(.standard)
        XCTAssertEqual(scaling.zoom(forAppID: "linux:code"), 0.8, accuracy: 0.001)
    }

    func testProfilesForPoses() {
        XCTAssertEqual(DuoScreenProfile.forPose(.noHinge), .standard)
        XCTAssertEqual(DuoScreenProfile.forPose(.tent), .outerScreen)
        XCTAssertEqual(DuoScreenProfile.forPose(.book), .bookHalf)
    }

    func testWindowsReturnToTheirFramesAfterFolding() {
        let manager = WindowManager()
        manager.updateDesktopSize(CGSize(width: 1000, height: 800))
        let window = manager.makeWindow(appID: "a", symbol: "app", title: "A", preferredSize: CGSize(width: 600, height: 400))
        manager.present(window)
        window.frame = CGRect(x: 380, y: 300, width: 600, height: 400)
        manager.updateDesktopSize(CGSize(width: 466, height: 640))
        XCTAssertLessThanOrEqual(window.frame.maxX, 466 + 600)
        manager.updateDesktopSize(CGSize(width: 1000, height: 800))
        XCTAssertEqual(window.frame, CGRect(x: 380, y: 300, width: 600, height: 400))
    }

    func testBookPoseSidesLeaveFramesAlone() {
        let manager = WindowManager()
        manager.updateDesktopSize(CGSize(width: 1000, height: 800))
        let a = manager.makeWindow(appID: "a", symbol: "app", title: "A", preferredSize: CGSize(width: 400, height: 300))
        manager.present(a)
        let b = manager.makeWindow(appID: "b", symbol: "app", title: "B", preferredSize: CGSize(width: 400, height: 300))
        manager.present(b)
        let frames = (a.frame, b.frame)
        let leading = CGRect(x: 0, y: 0, width: 490, height: 800)
        let trailing = CGRect(x: 510, y: 0, width: 490, height: 800)
        manager.setPoseLayout(.sides(leading: leading, trailing: trailing))
        // The focused window on the left, the one before it on the right.
        XCTAssertEqual(manager.displayFrame(for: b), leading)
        XCTAssertEqual(manager.displayFrame(for: a), trailing)
        manager.swapPoseSides()
        XCTAssertEqual(manager.displayFrame(for: b), trailing)
        XCTAssertEqual(manager.displayFrame(for: a), leading)
        manager.setPoseLayout(nil)
        XCTAssertEqual(a.frame, frames.0)
        XCTAssertEqual(b.frame, frames.1)
    }
}
