import Foundation
import XCTest
@testable import OmniVibeMac

final class LocalizationTests: XCTestCase {
    func testSystemLanguageUsesTheFirstSupportedPreferenceAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hant-TW", "en-US"]), .zhHans)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en_GB", "zh-Hans"]), .en)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .en)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .en)
        XCTAssertEqual(AppLanguage.en.resolved(preferredLanguages: ["zh-Hans"]), .en)
        XCTAssertEqual(AppLanguage.zhHans.resolved(preferredLanguages: ["en-US"]), .zhHans)
    }

    func testBundledEnglishCatalogueIsCompleteAndOnlyProperNamesRemainVerbatim() throws {
        let catalogue = try LocalizationCatalog.bundled()
        XCTAssertGreaterThan(catalogue.translations.count, 650)
        XCTAssertEqual(catalogue.translations["取消"], "Cancel")
        XCTAssertEqual(catalogue.text("窗口间距", language: .en), "Window spacing")
        let han = try NSRegularExpression(pattern: #"[\p{Han}]"#)
        for (source, english) in catalogue.translations {
            if catalogue.verbatimKeys.contains(source) { XCTAssertEqual(source, english) }
            else {
                XCTAssertNil(han.firstMatch(in: english, range: NSRange(english.startIndex..., in: english)), source)
            }
        }
    }

    func testUnknownStringsAndCapturedTaskDataRemainUnchanged() throws {
        let catalogue = try LocalizationCatalog(translations: ["任务 %@ 已完成": "Task %@ is complete"])
        let name = "项目 / 用户文档 100% $1 \\ (保留)\n第二行"
        XCTAssertEqual(catalogue.text("任务 \(name) 已完成", language: .en), "Task \(name) is complete")
        XCTAssertEqual(catalogue.text("任务 \(name) 已完成", language: .zhHans), "任务 \(name) 已完成")
        XCTAssertEqual(catalogue.text(name, language: .en), name)
        XCTAssertEqual(catalogue.text("Unregistered task name", language: .zhHans), "Unregistered task name")
    }

    func testStoredComposedStatusCanSwitchBackWithoutTranslatingItsCapturedValue() throws {
        let catalogue = try LocalizationCatalog(translations: ["已收纳 %@ 个窗口": "%@ windows captured"])
        let english = catalogue.text("已收纳 3 个窗口", language: .en)
        XCTAssertEqual(english, "3 windows captured")
        XCTAssertEqual(catalogue.text(english, language: .zhHans), "已收纳 3 个窗口")
        XCTAssertEqual(catalogue.text("已收纳 3 个窗口", language: .en), english)
    }

    func testSpecificTemplateWinsAndConflictingRepeatedArgumentsDoNotMatch() throws {
        let catalogue = try LocalizationCatalog(translations: [
            "打开%@": "Open %@",
            "打开%@失败：%@": "Could not open %@: %@",
            "%1$@与%1$@匹配": "%1$@ matches %1$@"
        ])
        XCTAssertEqual(catalogue.text("打开项目甲失败：busy", language: .en), "Could not open 项目甲: busy")
        XCTAssertEqual(catalogue.text("A与A匹配", language: .en), "A matches A")
        XCTAssertEqual(catalogue.text("A与B匹配", language: .en), "A与B匹配")
    }

    func testPrintfArgumentsCanReorderButMustKeepTheirTypes() throws {
        let catalogue = try LocalizationCatalog(translations: ["%@ 有 %ld 项": "%2$ld items for %1$@"])
        XCTAssertEqual(catalogue.format("%@ 有 %ld 项", arguments: ["项目甲", 3], language: .en), "3 items for 项目甲")
        XCTAssertEqual(catalogue.format("%@ 有 %ld 项", arguments: ["项目甲", 3], language: .zhHans), "项目甲 有 3 项")
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["%@ 有 %ld 项": "%1$ld items for %2$@"] ))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["任务 %@": "Task %p"] ))
    }

    func testIncorrectArgumentCountTypesAndUnsafeFormatsDoNotReachCFormatting() throws {
        let catalogue = try LocalizationCatalog(translations: ["任务 %@": "Task %@", "进度 %d%%": "Progress %d%%"])
        XCTAssertEqual(catalogue.format("任务 %@", arguments: [], language: .en), "任务 %@")
        XCTAssertEqual(catalogue.format("任务 %@", arguments: [42], language: .en), "任务 %@")
        XCTAssertEqual(catalogue.format("进度 %d%%", arguments: [70], language: .en), "Progress 70%")
        XCTAssertEqual(catalogue.format("Unsafe %n", arguments: [1], language: .en), "Unsafe %n")
        XCTAssertEqual(catalogue.format("Unsafe %*d", arguments: [2, 1], language: .en), "Unsafe %*d")
        XCTAssertEqual(catalogue.format("100%", arguments: [], language: .en), "100%")
    }

    func testAmbiguousReverseTranslationsDoNotChooseAnArbitrarySource() throws {
        let catalogue = try LocalizationCatalog(translations: ["关闭": "Close", "关上": "Close"])
        XCTAssertEqual(catalogue.text("Close", language: .zhHans), "Close")
        XCTAssertEqual(catalogue.text("关闭", language: .en), "Close")
    }

    func testNestedErrorsTranslateOnlyTheirDeclaredArgumentsAndPreserveMatchingTaskNamesAndPaths() throws {
        let source = "任务 %@ · 路径 %@：%@"
        let catalogue = try LocalizationCatalog(translations: [
            source: "Task %@ - path %@: %@",
            "窗口已关闭": "Window closed",
            "操作失败：%@": "Operation failed: %@"
        ], nestedErrorArguments: [source: [2], "操作失败：%@": [0]])
        let original = "任务 窗口已关闭 · 路径 窗口已关闭：操作失败：窗口已关闭"
        let english = "Task 窗口已关闭 - path 窗口已关闭: Operation failed: Window closed"
        XCTAssertEqual(catalogue.text(original, language: .en), english)
        XCTAssertEqual(catalogue.errorText(original, language: .en), english)
        XCTAssertEqual(catalogue.errorText(english, language: .zhHans), original)
        XCTAssertEqual(catalogue.format(source,
            arguments: ["窗口已关闭", "窗口已关闭", "操作失败：窗口已关闭"], language: .en), english)
    }

    func testPerWindowErrorTranslationPreservesApplicationNamesAndUnknownData() throws {
        let catalogue = try LocalizationCatalog(translations: ["窗口已关闭": "Window closed"])
        XCTAssertEqual(catalogue.errorText("取消：窗口已关闭\nLark：窗口已关闭", language: .en),
                       "取消: Window closed\nLark: Window closed")
        XCTAssertEqual(catalogue.text("取消：窗口已关闭", language: .en), "取消：窗口已关闭")
        XCTAssertEqual(catalogue.errorText("path：unregistered value", language: .en), "path：unregistered value")
    }

    func testNestedErrorMetadataIsValidatedAndRecursionRemainsBounded() throws {
        let catalogue = try LocalizationCatalog(translations: [
            "错误：%@": "Error: %@", "窗口已关闭": "Window closed"
        ], nestedErrorArguments: ["错误：%@": [0]])
        let source = String(repeating: "错误：", count: 100) + "窗口已关闭"
        let translated = catalogue.errorText(source, language: .en)
        XCTAssertTrue(translated.hasPrefix("Error: Error: Error: Error: "))
        XCTAssertTrue(translated.contains("错误："))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["数量 %d": "Count %d"],
            nestedErrorArguments: ["数量 %d": [0]]))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["错误：%@": "Error: %@"],
            nestedErrorArguments: ["错误：%@": [1]]))
    }

    @MainActor
    func testLanguageSelectionPersistsAndDoesNotChangeOtherPreferences() throws {
        let (preferences, _) = try isolatedPreferences()
        preferences.set("untouched", forKey: "Unrelated.Preference")
        let catalogue = try LocalizationCatalog(translations: ["取消": "Cancel"])
        let model = AppLocalization(preferences: preferences, preferredLanguages: { ["zh-Hans"] }, catalog: catalogue)
        XCTAssertEqual(model.language, .system)
        XCTAssertEqual(model.text("取消"), "取消")
        XCTAssertTrue(model.setLanguage(.en))
        XCTAssertEqual(model.language, .en)
        XCTAssertEqual(model.text("取消"), "Cancel")
        XCTAssertEqual(preferences.string(forKey: AppLocalization.preferenceKey), "en")
        XCTAssertEqual(preferences.string(forKey: "Unrelated.Preference"), "untouched")
        let restarted = AppLocalization(preferences: preferences, preferredLanguages: { ["zh-Hans"] }, catalog: catalogue)
        XCTAssertEqual(restarted.language, .en)
        XCTAssertEqual(restarted.resolvedLanguage, .en)
        XCTAssertEqual(restarted.text("取消"), "Cancel")
    }

    @MainActor
    func testInvalidStoredLanguageIsRetainedUntilAnExplicitChoice() throws {
        let (preferences, _) = try isolatedPreferences()
        preferences.set(Data([1, 2, 3]), forKey: AppLocalization.preferenceKey)
        let model = AppLocalization(preferences: preferences, preferredLanguages: { ["en-US"] }, catalog: .empty)
        XCTAssertEqual(model.language, .system)
        XCTAssertEqual(model.resolvedLanguage, .en)
        XCTAssertNotNil(model.warning)
        XCTAssertEqual(preferences.data(forKey: AppLocalization.preferenceKey), Data([1, 2, 3]))
        XCTAssertTrue(model.setLanguage(.system))
        XCTAssertNil(model.warning)
        XCTAssertEqual(preferences.string(forKey: AppLocalization.preferenceKey), "system")
    }

    @MainActor
    func testSystemLanguageRefreshChangesRevisionAndNativeNotificationOnlyWhenNecessary() throws {
        let (preferences, _) = try isolatedPreferences()
        var preferred = ["zh-Hans"]
        let catalogue = try LocalizationCatalog(translations: ["取消": "Cancel"])
        let model = AppLocalization(preferences: preferences, preferredLanguages: { preferred }, catalog: catalogue)
        let notifications = NotificationCount()
        let observer = NotificationCenter.default.addObserver(forName: .omniVibeLanguageDidChange,
            object: model, queue: nil) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        model.refreshSystemLanguage()
        XCTAssertEqual(model.revision, 0)
        preferred = ["en-GB"]
        model.refreshSystemLanguage()
        XCTAssertEqual(model.resolvedLanguage, .en)
        XCTAssertEqual(model.revision, 1)
        XCTAssertEqual(notifications.value, 1)
        XCTAssertTrue(model.setLanguage(.en))
        XCTAssertEqual(notifications.value, 2)
        XCTAssertTrue(model.setLanguage(.en))
        XCTAssertEqual(notifications.value, 2)
        preferred = ["zh-Hans"]
        model.refreshSystemLanguage()
        XCTAssertEqual(model.resolvedLanguage, .en)
        XCTAssertEqual(model.revision, 2)
    }

    func testCatalogueRejectsInvalidSchemaOversizedAndPlaceholderChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeLocalizationTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("en.json")
        try Data(#"{"schemaVersion":99,"translations":{}}"#.utf8).write(to: file)
        XCTAssertThrowsError(try LocalizationCatalog.load(file))
        try Data(repeating: 32, count: 2_097_153).write(to: file)
        XCTAssertThrowsError(try LocalizationCatalog.load(file))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["任务 %@": "Task"] ))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["": "Empty"] ))
        XCTAssertThrowsError(try LocalizationCatalog(translations: ["品牌": "Brand"], verbatimKeys: ["品牌"]))
    }

    private func isolatedPreferences() throws -> (UserDefaults, String) {
        let name = "OmniVibeLocalizationTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { preferences.removePersistentDomain(forName: name) }
        return (preferences, name)
    }
}

private final class NotificationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}
