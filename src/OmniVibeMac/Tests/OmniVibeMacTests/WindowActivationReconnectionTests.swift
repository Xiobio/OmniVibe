import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WindowActivationReconnectionTests: XCTestCase {
    private let boot = "A8E43814-3C43-4419-A135-51C938E34F89"
    private let start = Date(timeIntervalSince1970: 1_792_834_858)
    private let seconds: Int64 = 1_792_407_353
    private var session: String { WindowSessionIdentity.token(userID: 501, bootUUID: boot, auditSessionID: 100_029)! }
    private var saved: WindowIdentity {
        WindowIdentity(processID: 66656, processStartedAt: start, bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal", title: "Opaque user title", platformWindowNumber: 8627, platformSessionID: session)
    }
    private var process: WindowActivationProcess {
        WindowActivationProcess(processID: 66656, startedAt: start, bundleIdentifier: "com.apple.Terminal", userID: 501, terminated: false)
    }
    private func cg(_ number: UInt32 = 8627, pid: Int32 = 66656, layer: Int = 0) -> WindowServerCandidate {
        WindowServerCandidate(number: number, processID: pid, title: nil,
            frame: WindowFrame(x: 20, y: 40, width: 800, height: 600), layer: layer)
    }
    private func allowed(_ window: WindowIdentity? = nil, owner: WindowActivationProcess? = nil,
                         currentSession: String? = nil, uid: UInt32 = 501, server: [WindowServerCandidate]? = nil) -> Bool {
        WindowActivationReconnectionGuard.permits(window ?? saved, process: owner ?? process,
            currentSession: currentSession ?? session, currentUserID: uid, serverWindows: server ?? [cg()], legacyBootSeconds: seconds)
    }

    func testExactLiveOwnerAndSavedCGAllowOnlyPreparationWithoutDependingOnTitle() {
        XCTAssertTrue(allowed())
        var renamed = saved; renamed.title = "Different title while closed"
        XCTAssertTrue(allowed(renamed))
        XCTAssertTrue(allowed(server: [cg(), cg(9999)]))
    }

    func testAbsentAmbiguousWrongOwnerAndNonordinaryCGWindowsRejectWake() {
        XCTAssertFalse(allowed(server: []))
        XCTAssertFalse(allowed(server: [cg(), cg()]))
        XCTAssertFalse(allowed(server: [cg(pid: 66657)]))
        XCTAssertFalse(allowed(server: [cg(layer: 3)]))
        XCTAssertFalse(WindowActivationReconnectionGuard.permits(saved, process: process,
            currentSession: session, currentUserID: 501, serverWindows: nil, legacyBootSeconds: seconds))
    }

    func testProcessReuseTerminationAndAnotherUserRejectWake() {
        let changes = [
            WindowActivationProcess(processID: 66657, startedAt: start, bundleIdentifier: "com.apple.Terminal", userID: 501, terminated: false),
            WindowActivationProcess(processID: 66656, startedAt: start.addingTimeInterval(1), bundleIdentifier: "com.apple.Terminal", userID: 501, terminated: false),
            WindowActivationProcess(processID: 66656, startedAt: start, bundleIdentifier: "com.example.Other", userID: 501, terminated: false),
            WindowActivationProcess(processID: 66656, startedAt: start, bundleIdentifier: "com.apple.Terminal", userID: 502, terminated: false),
            WindowActivationProcess(processID: 66656, startedAt: start, bundleIdentifier: "com.apple.Terminal", userID: nil, terminated: false),
            WindowActivationProcess(processID: 66656, startedAt: start, bundleIdentifier: "com.apple.Terminal", userID: 501, terminated: true)
        ]
        for changed in changes { XCTAssertFalse(allowed(owner: changed)) }
        XCTAssertFalse(allowed(uid: 502))
    }

    func testMissingProcessStartBundleOrWindowTokenRejectWake() {
        var missing = saved; missing.processStartedAt = nil
        XCTAssertFalse(allowed(missing))
        missing = saved; missing.bundleIdentifier = nil
        XCTAssertFalse(allowed(missing))
        missing = saved; missing.bundleIdentifier = ""
        XCTAssertFalse(allowed(missing))
        missing = saved; missing.platformWindowNumber = nil
        XCTAssertFalse(allowed(missing))
        missing = saved; missing.platformWindowNumber = 0
        XCTAssertFalse(allowed(missing))
        missing = saved; missing.processID = 0
        XCTAssertFalse(allowed(missing))
    }

    func testCurrentSessionNeedsTheSameStableBootUserAndAudit() {
        let changed = [
            WindowSessionIdentity.token(userID: 501, bootUUID: "C5B12342-870E-49DD-A4FB-93B19E054D28", auditSessionID: 100_029)!,
            WindowSessionIdentity.token(userID: 501, bootUUID: boot, auditSessionID: 100_030)!,
            WindowSessionIdentity.token(userID: 502, bootUUID: boot, auditSessionID: 100_029)!,
            "501:\(seconds):803811:100029", "opaque-session", ""
        ]
        for current in changed { XCTAssertFalse(allowed(currentSession: current)) }
        XCTAssertFalse(WindowActivationReconnectionGuard.permits(saved, process: process,
            currentSession: nil, currentUserID: 501, serverWindows: [cg()], legacyBootSeconds: seconds))
    }

    func testLegacyMigrationStillRequiresExactSecondsAndAllOtherPreconditions() {
        var old = saved; old.platformSessionID = "501:\(seconds):803811:100029"
        XCTAssertTrue(allowed(old))
        XCTAssertFalse(allowed(old, server: [cg(pid: 66657)]))
        XCTAssertFalse(WindowActivationReconnectionGuard.permits(old, process: process,
            currentSession: session, currentUserID: 501, serverWindows: [cg()], legacyBootSeconds: seconds + 1))
        XCTAssertFalse(WindowActivationReconnectionGuard.permits(old, process: process,
            currentSession: session, currentUserID: 501, serverWindows: [cg()], legacyBootSeconds: nil))
    }
}
