import AppKit
import Foundation
import OmniVibeCore

@MainActor
enum AppearanceValidationRunner {
    struct Result: Encodable {
        var name: String
        var passed: Bool
        var detail: String
    }

    static func run(outputPath: String) -> Int32 {
        let resources = ThemeResources.shared
        var results: [Result] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            results.append(Result(name: name, passed: passed, detail: detail))
        }
        check("Original thirteen theme catalogues", resources.themes.count == 13)
        check("No missing catalogue assets", resources.assetWarning == nil, resources.assetWarning ?? "")
        var entityCount = 0
        for theme in resources.themes {
            let items = resources.equipmentItems(themeSlug: theme.slug)
            entityCount += items.count
            check("\(theme.slug): nine equipment options", items.count == 9)
            check("\(theme.slug): transparent theme identity", resources.identity(themeSlug: theme.slug) != nil)
            check("\(theme.slug): original frame", resources.image("skins/native-v2/\(theme.slug)/frame.png") != nil)
            check("\(theme.slug): original illustration", resources.image(theme.artwork) != nil)
            for item in items {
                check("\(theme.slug): \(item.id)", resources.equipmentImage(item) != nil)
            }
        }
        check("All 117 original equipment images decode", entityCount == 117)

        // Validate the packaged files directly. Playback resolution also checks
        // user overrides, which must never affect this distributable-asset report.
        let operationCues = AudioCue.allCases.map(\.rawValue)
        let classicSignatures: Set<String> = ["ink-jade", "midnight", "cinnabar"]
        check("Original fourteen operation audio cues", operationCues.count == 14)
        var validAudioFiles = 0
        func checkWave(_ relativePath: String) {
            let url = resources.root.appendingPathComponent(relativePath)
            do {
                let data = try Data(contentsOf: url)
                guard let duration = ThemeAudio.waveDuration(data) else {
                    check(relativePath, false, "Invalid or unsupported short PCM16 WAV")
                    return
                }
                validAudioFiles += 1
                check(relativePath, true, String(format: "%.3f seconds; parsed without playback", duration))
            } catch {
                check(relativePath, false, error.localizedDescription)
            }
        }
        for theme in resources.themes {
            for cue in operationCues {
                // Include the legacy switch.wav even though live switching uses
                // the signature policy, and ready.wav despite the completion cue.
                checkWave("skins/audio/\(theme.slug)/\(cue).wav")
            }
            checkWave("skins/completion-audio/\(theme.slug)/complete.wav")
            let signaturePath = "skins/signature-audio/bundled/\(theme.slug)/signature.wav"
            if classicSignatures.contains(theme.slug) {
                checkWave(signaturePath)
            } else {
                check("\(theme.slug): no bundled switch signature",
                      !FileManager.default.fileExists(atPath: resources.root.appendingPathComponent(signaturePath).path),
                      "Missing game-theme signatures remain silent; user audio is not inspected")
            }
        }
        check("All 198 bundled audio files parse without playback", validAudioFiles == 198,
              "\(validAudioFiles) valid WAV files; expected 182 operation + 13 completion + 3 classic signatures")

        do {
            let catalog = try LocalizationCatalog.bundled()
            check("Packaged English localization catalogue loads", catalog.translations.count >= 800)
            check("Core English settings actions resolve", catalog.text("设置", language: .en) == "Settings" &&
                  catalog.text("取消", language: .en) == "Cancel")
            let actions = ["新建或继续任务…", "指定 Terminal 恢复配置", "生成并联动 Claude 主题", "启动／继续…"]
            check("New lifecycle and theme actions have English translations", actions.allSatisfy {
                let translated = catalog.text($0, language: .en)
                return !translated.isEmpty && translated != $0
            })
        } catch { check("Packaged localization resources", false, error.localizedDescription) }

        do {
            let catalog = try TerminalThemeCatalog.bundled()
            check("All thirteen calibrated complete Terminal schemes load", catalog.themes.count == 13)
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("OmniVibeProfileValidation-\(UUID())")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let decorated = try catalog.exportProfiles(to: temporary, decorations: true, variantNames: true)
            let minimal = try catalog.exportProfiles(to: temporary, decorations: false, variantNames: true)
            let urls = decorated.profileURLs + minimal.profileURLs
            check("Decorated and minimal Terminal variants coexist", urls.count == 26 && Set(urls).count == 26)
            for url in urls {
                let data = try Data(contentsOf: url)
                let profile = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
                check(url.lastPathComponent + ": complete ANSI and base colors",
                      TerminalThemeCatalog.ansiProfileKeys.allSatisfy { profile[$0.profile] is Data } &&
                      ["BackgroundColor", "TextColor", "TextBoldColor", "CursorColor", "SelectionColor"].allSatisfy { profile[$0] is Data })
                if let archive = profile["BackgroundImageBookmark"] as? Data,
                   let bookmark = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSData.self, from: archive) {
                    var stale = false
                    let image = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
                    check(url.lastPathComponent + ": stable background reference", !stale && FileManager.default.fileExists(atPath: image.path))
                } else { check(url.lastPathComponent + ": stable background reference", false) }
                check(url.lastPathComponent + ": no shell startup command", !profile.keys.contains(where: { $0.lowercased().contains("command") }))
            }
        } catch { check("Complete native Terminal profile validation", false, error.localizedDescription) }

        let appearance = AppearanceModel(demo: true)
        check("Default theme matches original Relic", appearance.themeSlug == "relic")
        let slot = TaskSlot(number: 1)
        appearance.setTheme("relic")
        if let alternate = appearance.equipmentOptions.last {
            appearance.setEquipment(alternate.id, for: slot)
            appearance.setTheme("ink-jade")
            appearance.setTheme("relic")
            check("Equipment selection is independent per theme", appearance.selectedEquipmentID(for: slot) == alternate.id)
        }
        let passed = results.allSatisfy(\.passed)
        do {
            let output = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: output, options: .atomic)
            print("Theme, audio and Terminal profile validation: \(results.count) checks, \(passed ? "passed" : "failed"). Report: \(output.path)")
            return passed ? 0 : 1
        } catch {
            fputs("Cannot write appearance validation report: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
