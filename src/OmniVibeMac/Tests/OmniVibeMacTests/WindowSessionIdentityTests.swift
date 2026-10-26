import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class WindowSessionIdentityTests: XCTestCase {
    private let boot = "A8E43814-3C43-4419-A135-51C938E34F89"
    private let otherBoot = "C5B12342-870E-49DD-A4FB-93B19E054D28"
    private let seconds: Int64 = 1_792_407_353

    private func stable(uid: UInt32 = 501, uuid: String? = nil, audit: UInt32 = 100_029) -> String {
        WindowSessionIdentity.token(userID: uid, bootUUID: uuid ?? boot, auditSessionID: audit)!
    }

    private func identity(session: String?, number: UInt32 = 8627, pid: Int32 = 66656,
                          start: Date? = Date(timeIntervalSince1970: 1_792_834_858),
                          bundle: String? = "com.apple.Terminal", title: String = "Project") -> WindowIdentity {
        WindowIdentity(processID: pid, processStartedAt: start, bundleIdentifier: bundle,
            applicationName: "Terminal", title: title, platformWindowNumber: number, platformSessionID: session)
    }

    func testStableTokenContainsOnlyUserBootUUIDAndAuditSession() {
        XCTAssertEqual(stable(), "v2:501:\(boot):100029")
        XCTAssertEqual(WindowSessionIdentity.token(userID: 501, bootUUID: boot.lowercased(), auditSessionID: 100_029), stable())
        // Wall-clock boot seconds have no effect on already stable identities.
        for shiftedSeconds: Int64? in [nil, 0, seconds, seconds + 3600] {
            XCTAssertTrue(WindowSessionIdentity.matches(saved: stable(), current: stable(), legacyBootSeconds: shiftedSeconds))
        }
    }

    func testTokenCreationFailsClosedWhenRequiredBootOrAuditMetadataIsMissing() {
        for uuid: String? in [nil, "", "not-a-uuid", "00000000-0000-0000-0000-000000000000", boot + "\n"] {
            XCTAssertNil(WindowSessionIdentity.token(userID: 501, bootUUID: uuid, auditSessionID: 100_029))
        }
        XCTAssertNil(WindowSessionIdentity.token(userID: 501, bootUUID: boot, auditSessionID: 0))
        XCTAssertNil(WindowSessionIdentity.token(userID: 501, bootUUID: boot, auditSessionID: UInt32.max))
    }

    func testLegacyMicrosecondDriftCanMigrateOnlyWithinTheExactBootSecondsUserAndAudit() {
        for usec in [0, 589_002, 803_811, 999_999] {
            XCTAssertTrue(WindowSessionIdentity.matches(saved: "501:\(seconds):\(usec):100029", current: stable(),
                legacyBootSeconds: seconds))
        }
        for old in ["502:\(seconds):803811:100029", "501:\(seconds):803811:100030",
                    "501:\(seconds - 1):803811:100029", "501:\(seconds + 1):803811:100029"] {
            XCTAssertFalse(WindowSessionIdentity.matches(saved: old, current: stable(), legacyBootSeconds: seconds))
        }
    }

    func testDifferentStableBootUserOrAuditNeverUsesLegacyCompatibility() {
        for changed in [stable(uid: 502), stable(uuid: otherBoot), stable(audit: 100_030)] {
            XCTAssertFalse(WindowSessionIdentity.matches(saved: stable(), current: changed, legacyBootSeconds: seconds))
        }
        XCTAssertTrue(WindowSessionIdentity.matches(saved: stable().lowercased(), current: stable(), legacyBootSeconds: nil))
    }

    func testLegacyMigrationRequiresAvailableExactSecondsAndRejectsMalformedTokens() {
        let old = "501:\(seconds):803811:100029"
        for unavailable: Int64? in [nil, 0, -1, seconds - 1] {
            XCTAssertFalse(WindowSessionIdentity.matches(saved: old, current: stable(), legacyBootSeconds: unavailable))
        }
        for malformed in ["", "501:\(seconds)::100029", "501:\(seconds):-1:100029",
                          "501:\(seconds):1000000:100029", "501:\(seconds):1:0",
                          "501:\(seconds):1:4294967295", "501:\(seconds):1:100029:extra",
                          "+501:\(seconds):1:100029", "501:9223372036854775808:1:100029",
                          "v2:501:invalid:100029"] {
            XCTAssertFalse(WindowSessionIdentity.matches(saved: malformed, current: stable(), legacyBootSeconds: seconds))
        }
        XCTAssertFalse(WindowSessionIdentity.matches(saved: nil, current: stable(), legacyBootSeconds: seconds))
        XCTAssertFalse(WindowSessionIdentity.matches(saved: old, current: nil, legacyBootSeconds: seconds))
        XCTAssertFalse(WindowSessionIdentity.matches(saved: "v2:501:invalid:100029", current: "v2:501:invalid:100029",
            legacyBootSeconds: seconds))
    }

    func testStableTokensCannotDowngradeToLegacyOrDifferentOpaqueSessionValues() {
        XCTAssertFalse(WindowSessionIdentity.matches(saved: stable(), current: "501:\(seconds):803811:100029", legacyBootSeconds: seconds))
        XCTAssertFalse(WindowSessionIdentity.matches(saved: stable(), current: "opaque-session", legacyBootSeconds: seconds))
        XCTAssertFalse(WindowSessionIdentity.matches(saved: "501:\(seconds):803811:100029",
            current: "501:\(seconds):589002:100029", legacyBootSeconds: seconds))
    }

    func testVerifiedAliasMigratesTheTokenWhileRetainingTheSavedWindowUUID() throws {
        let saved = identity(session: "501:\(seconds):803811:100029", title: "Old title")
        let current = identity(session: stable(), title: "Renamed while closed")
        let migrated = try XCTUnwrap(WindowReconnectionMatcher.alias(saved: saved, current: current,
            sessionID: stable(), legacyBootSeconds: seconds))
        XCTAssertEqual(migrated.id, saved.id)
        XCTAssertEqual(migrated.platformSessionID, stable())
        XCTAssertEqual(migrated.title, current.title)
        XCTAssertEqual(migrated.platformWindowNumber, saved.platformWindowNumber)
        XCTAssertNotEqual(current.id, saved.id)
    }

    func testLegacyCompatibilityCannotBypassAnyProcessOrCGIdentityGuard() {
        let saved = identity(session: "501:\(seconds):803811:100029")
        let changes = [identity(session: stable(), number: 8626), identity(session: stable(), pid: 66657),
                       identity(session: stable(), start: Date(timeIntervalSince1970: 1_792_834_859)),
                       identity(session: stable(), start: nil), identity(session: stable(), bundle: "com.example.Other"),
                       identity(session: stable(uid: 502)), identity(session: stable(audit: 100_030))]
        for current in changes {
            XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: current,
                sessionID: stable(), legacyBootSeconds: seconds))
        }
        var missingNumber = saved; missingNumber.platformWindowNumber = nil
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: missingNumber, current: identity(session: stable()),
            sessionID: stable(), legacyBootSeconds: seconds))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: identity(session: stable()),
            sessionID: stable(), legacyBootSeconds: nil))
    }

    func testStableAliasRetainsStrictBootUUIDAndDoesNotNeedLegacyClockMetadata() {
        let saved = identity(session: stable())
        XCTAssertNotNil(WindowReconnectionMatcher.alias(saved: saved, current: identity(session: stable()),
            sessionID: stable(), legacyBootSeconds: nil))
        XCTAssertNil(WindowReconnectionMatcher.alias(saved: saved, current: identity(session: stable(uuid: otherBoot)),
            sessionID: stable(uuid: otherBoot), legacyBootSeconds: seconds))
    }
}
