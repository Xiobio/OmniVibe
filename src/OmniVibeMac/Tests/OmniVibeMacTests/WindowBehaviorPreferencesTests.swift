import Carbon
import Foundation
import XCTest
@testable import OmniVibeMac

final class WindowBehaviorPreferencesTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "OmniVibeWindowBehaviorTests-\(UUID())"
        let value = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }

    func testDefaultsAndEmptyJSONKeepOriginalWindowBehaviorAndExplicitNotificationOptIn() throws {
        let value = WindowBehaviorPreferences()
        XCTAssertEqual(value.layoutGap, 12)
        XCTAssertEqual(value.arrangement, .balanced)
        XCTAssertEqual(value.wakeMode, .lastPosition)
        XCTAssertTrue(value.minimizeOnCapture)
        XCTAssertTrue(value.wheelSwitchEnabled)
        XCTAssertEqual(value.wheelModifiers, UInt32(optionKey))
        XCTAssertFalse(value.shortcutsPaused)
        XCTAssertTrue(value.completionSoundEnabled)
        XCTAssertFalse(value.systemNotificationsEnabled)
        XCTAssertTrue(value.autoReconnectExisting)
        XCTAssertFalse(value.autoRestoreRecovery)
        XCTAssertTrue(value.showRecoveryOnStartup)
        XCTAssertFalse(value.hideLauncherOnArrange)
        XCTAssertEqual(value.overviewSize, .large)
        XCTAssertEqual(value.launcherExtent, 360)
        XCTAssertEqual(try JSONDecoder().decode(WindowBehaviorPreferences.self, from: Data("{}".utf8)), value)
    }

    func testSaveAndReloadPreserveIndependentChoicesAndValidatedArrangementRawValue() throws {
        let preferences = try defaults()
        let store = WindowBehaviorPreferencesStore(preferences: preferences)
        var draft = store.value
        draft.layoutGap = 27.5; draft.arrangement = .mainLeft; draft.wakeMode = .workArea
        draft.minimizeOnCapture = false; draft.wheelSwitchEnabled = false
        draft.wheelModifiers = UInt32(controlKey | optionKey | shiftKey)
        draft.shortcutsPaused = true; draft.completionSoundEnabled = false
        draft.systemNotificationsEnabled = true; draft.autoReconnectExisting = false
        draft.autoRestoreRecovery = true; draft.showRecoveryOnStartup = false
        draft.hideLauncherOnArrange = true; draft.overviewSize = .small; draft.launcherExtent = 450
        try store.save(draft)
        XCTAssertEqual(store.value, draft)
        XCTAssertNil(store.warning)
        XCTAssertEqual(WindowBehaviorPreferencesStore(preferences: preferences).value, draft)
        let bytes = try XCTUnwrap(preferences.data(forKey: WindowBehaviorPreferencesStore.key))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["arrangement"] as? String, "mainLeft")
    }

    func testClampingOccursBeforePublishingAndEncoding() throws {
        let preferences = try defaults()
        let store = WindowBehaviorPreferencesStore(preferences: preferences)
        var draft = store.value
        draft.layoutGap = -10; draft.launcherExtent = 999
        try store.save(draft)
        XCTAssertEqual(store.value.layoutGap, 0)
        XCTAssertEqual(store.value.launcherExtent, 520)
        draft.layoutGap = 100; draft.launcherExtent = 10
        try store.save(draft)
        XCTAssertEqual(store.value.layoutGap, 40)
        XCTAssertEqual(store.value.launcherExtent, 280)
        let loaded = WindowBehaviorPreferencesStore(preferences: preferences)
        XCTAssertEqual(loaded.value, store.value)
    }

    func testCorruptAndUnknownEnumJSONRemainUntouchedUntilExplicitSuccessfulSave() throws {
        let preferences = try defaults()
        for bytes in [Data("not JSON".utf8), Data("{\"arrangement\":\"not-a-mode\"}".utf8),
                      Data("{\"wakeMode\":\"unknown\"}".utf8), Data("{\"overviewSize\":\"giant\"}".utf8),
                      Data("{\"wheelModifiers\":0}".utf8)] {
            preferences.set(bytes, forKey: WindowBehaviorPreferencesStore.key)
            let store = WindowBehaviorPreferencesStore(preferences: preferences)
            XCTAssertEqual(store.value, WindowBehaviorPreferences())
            XCTAssertNotNil(store.warning)
            XCTAssertEqual(preferences.data(forKey: WindowBehaviorPreferencesStore.key), bytes)
            try store.save(WindowBehaviorPreferences())
            XCTAssertNil(store.warning)
            XCTAssertNotEqual(preferences.data(forKey: WindowBehaviorPreferencesStore.key), bytes)
        }
        preferences.set("unexpected type", forKey: WindowBehaviorPreferencesStore.key)
        XCTAssertNotNil(WindowBehaviorPreferencesStore(preferences: preferences).warning)
        XCTAssertEqual(preferences.string(forKey: WindowBehaviorPreferencesStore.key), "unexpected type")
    }

    func testInvalidCandidateCannotChangeStoredBytesOrPublishedValue() throws {
        let preferences = try defaults()
        let store = WindowBehaviorPreferencesStore(preferences: preferences)
        try store.save(WindowBehaviorPreferences())
        let bytes = preferences.data(forKey: WindowBehaviorPreferencesStore.key)
        let original = store.value
        for modifier in [UInt32(0), UInt32.max, UInt32(alphaLock)] {
            var candidate = original; candidate.wheelModifiers = modifier
            XCTAssertThrowsError(try store.save(candidate))
            XCTAssertEqual(store.value, original)
            XCTAssertEqual(preferences.data(forKey: WindowBehaviorPreferencesStore.key), bytes)
        }
        for number in [Double.nan, .infinity, -.infinity] {
            var candidate = original; candidate.layoutGap = number
            XCTAssertThrowsError(try store.save(candidate))
            candidate = original; candidate.launcherExtent = number
            XCTAssertThrowsError(try store.save(candidate))
        }
        XCTAssertEqual(store.value, original)
        XCTAssertEqual(preferences.data(forKey: WindowBehaviorPreferencesStore.key), bytes)
    }
}
