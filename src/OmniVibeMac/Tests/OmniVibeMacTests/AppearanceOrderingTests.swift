import AppKit
import Foundation
import XCTest
import OmniVibeCore
@testable import OmniVibeMac

final class AppearanceOrderingTests: XCTestCase {
    @MainActor
    func testDefaultEquipmentAndEntityFollowTaskAcrossReorderInEveryTheme() throws {
        let root = try temporaryDirectory().appendingPathComponent("demo-does-not-write")
        let appearance = AppearanceModel(demo: true, root: root)
        var workspace = try boundWorkspace()
        let occupied = workspace.slots.filter { $0.window != nil }
        XCTAssertEqual(appearance.availableThemes.count, 13)
        let expected = try equipmentByTheme(appearance, slots: occupied)
        appearance.setTheme("relic")
        let originalEntity = try XCTUnwrap(appearance.entity(for: occupied[0]))

        try appearance.preserveTaskEquipment(workspace.slots)
        try workspace.reorder(from: 2, to: 8)
        let moved = try XCTUnwrap(workspace.slots.first { $0.id == occupied[0].id })
        XCTAssertEqual(moved.number, 8)
        XCTAssertEqual(try equipmentByTheme(appearance, slots: workspace.slots.filter { $0.window != nil }), expected)
        appearance.setTheme("relic")
        XCTAssertTrue(appearance.entity(for: moved) === originalEntity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testFreezePersistsAllThemesOnlyForOccupiedTasksAndIsIdempotent() throws {
        let root = try temporaryDirectory()
        let file = root.appendingPathComponent("appearance.json")
        let appearance = AppearanceModel(root: root)
        var workspace = try boundWorkspace()
        try appearance.preserveTaskEquipment([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let original = workspace.slots.filter { $0.window != nil }
        var expected: [String: [String: String]] = [:]
        for slot in original {
            expected[slot.id.uuidString] = Dictionary(uniqueKeysWithValues: appearance.availableThemes.map { theme in
                let items = ThemeResources.shared.equipmentItems(themeSlug: theme.slug)
                return (theme.slug, items[slot.number - 1].id)
            })
        }
        try appearance.preserveTaskEquipment(workspace.slots)
        let values = try preferences(at: file)
        XCTAssertEqual(values["selections"] as? [String: [String: String]], expected)
        XCTAssertEqual(expected.count, 2)
        XCTAssertTrue(expected.values.allSatisfy { $0.count == 13 })

        let sentinelDate = Date(timeIntervalSince1970: 1_234_567)
        try FileManager.default.setAttributes([.modificationDate: sentinelDate], ofItemAtPath: file.path)
        try workspace.reorder(from: 2, to: 8)
        try appearance.preserveTaskEquipment(workspace.slots)
        let modified = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, sentinelDate, "Already-frozen selections must not be rewritten using the new slot numbers.")

        let reloaded = AppearanceModel(root: root)
        XCTAssertEqual(try equipmentByTheme(reloaded, slots: workspace.slots.filter { $0.window != nil }), expected)
    }

    @MainActor
    func testExplicitEquipmentAndManagedCustomImageRemainUnchanged() throws {
        let root = try temporaryDirectory()
        var workspace = try boundWorkspace()
        let occupied = workspace.slots.filter { $0.window != nil }
        let chosen = ThemeResources.shared.equipmentItems(themeSlug: "relic")[8].id
        let imageName = "chosen.png"
        let imageFolder = root.appendingPathComponent("Loadout", isDirectory: true)
        try FileManager.default.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        let image = try smallPNG()
        try image.write(to: imageFolder.appendingPathComponent(imageName))
        let selected = [occupied[0].id.uuidString: ["relic": chosen, "future-theme": "keep-this-choice"]]
        let customImages = [occupied[1].id.uuidString: imageName]
        try writePreferences(root: root, selections: selected, customImages: customImages)
        let appearance = AppearanceModel(root: root)
        let customEntity = try XCTUnwrap(appearance.entity(for: occupied[1]))

        try appearance.preserveTaskEquipment(workspace.slots)
        try workspace.reorder(from: 2, to: 8)
        let movedSelected = try XCTUnwrap(workspace.slots.first { $0.id == occupied[0].id })
        let movedImage = try XCTUnwrap(workspace.slots.first { $0.id == occupied[1].id })
        XCTAssertEqual(appearance.selectedEquipmentID(for: movedSelected), chosen)
        XCTAssertTrue(appearance.entity(for: movedImage) === customEntity)
        XCTAssertEqual(try Data(contentsOf: imageFolder.appendingPathComponent(imageName)), image)
        let values = try preferences(at: root.appendingPathComponent("appearance.json"))
        XCTAssertEqual(values["customImages"] as? [String: String], customImages)
        XCTAssertEqual((values["selections"] as? [String: [String: String]])?[occupied[0].id.uuidString]?["future-theme"], "keep-this-choice")
    }

    @MainActor
    func testSaveFailureDoesNotPublishAnyFrozenDefaults() throws {
        let root = try temporaryDirectory().appendingPathComponent("blocked-root")
        let blocker = Data("retain this file".utf8)
        try blocker.write(to: root)
        let appearance = AppearanceModel(root: root)
        let workspace = try boundWorkspace()
        let original = workspace.slots[1]
        var reorderedProbe = original
        reorderedProbe.number = 8
        let fallbackAfterMove = appearance.selectedEquipmentID(for: reorderedProbe)
        XCTAssertNotEqual(fallbackAfterMove, appearance.selectedEquipmentID(for: original))

        XCTAssertThrowsError(try appearance.preserveTaskEquipment(workspace.slots))
        XCTAssertEqual(appearance.selectedEquipmentID(for: reorderedProbe), fallbackAfterMove,
            "A failed save must not leave earlier tasks frozen in memory.")
        XCTAssertEqual(try Data(contentsOf: root), blocker)
    }

    @MainActor
    func testFailedAtomicReplacementRetainsExistingSelectionsAndOtherFileContents() throws {
        let root = try temporaryDirectory()
        let workspace = try boundWorkspace()
        let occupied = workspace.slots.filter { $0.window != nil }
        let chosen = ThemeResources.shared.equipmentItems(themeSlug: "relic")[8].id
        try writePreferences(root: root, selections: [occupied[0].id.uuidString: ["relic": chosen]])
        let appearance = AppearanceModel(root: root)
        let file = root.appendingPathComponent("appearance.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let marker = file.appendingPathComponent("retain.txt")
        try Data("unchanged".utf8).write(to: marker)
        var movedDefault = occupied[1]
        movedDefault.number = 3
        let fallbackAfterMove = appearance.selectedEquipmentID(for: movedDefault)

        XCTAssertThrowsError(try appearance.preserveTaskEquipment(workspace.slots))
        XCTAssertEqual(appearance.selectedEquipmentID(for: occupied[0]), chosen)
        XCTAssertEqual(appearance.selectedEquipmentID(for: movedDefault), fallbackAfterMove)
        XCTAssertEqual(try String(contentsOf: marker), "unchanged")
    }

    @MainActor
    func testDemoFreezesOnlyInMemoryEvenWhenPersistenceRootCannotBeWritten() throws {
        let root = try temporaryDirectory().appendingPathComponent("blocked-root")
        let blocker = Data("demo must not write".utf8)
        try blocker.write(to: root)
        let appearance = AppearanceModel(demo: true, root: root)
        let workspace = try boundWorkspace()
        let original = workspace.slots[1]
        let selected = appearance.selectedEquipmentID(for: original)
        try appearance.preserveTaskEquipment(workspace.slots)
        var moved = original
        moved.number = 8
        XCTAssertEqual(appearance.selectedEquipmentID(for: moved), selected)
        XCTAssertEqual(try Data(contentsOf: root), blocker)
    }

    @MainActor
    func testExplicitTaskIdentityTransferCopiesAllThemeChoicesAndImageWhileKeepingOldMappings() throws {
        let root = try temporaryDirectory()
        let slots = try boundWorkspace().slots.filter { $0.window != nil }
        let old = slots[0], replacement = slots[1]
        let choices = Dictionary(uniqueKeysWithValues: ThemeResources.shared.themes.map { theme in
            (theme.slug, ThemeResources.shared.equipmentItems(themeSlug: theme.slug)[8].id)
        })
        try writePreferences(root: root, selections: [old.id.uuidString: choices], customImages: [old.id.uuidString: "kept.png"])
        let appearance = AppearanceModel(root: root)
        try appearance.transferEquipment(from: old.id, to: replacement.id)
        let values = try preferences(at: root.appendingPathComponent("appearance.json"))
        let selected = try XCTUnwrap(values["selections"] as? [String: [String: String]])
        let images = try XCTUnwrap(values["customImages"] as? [String: String])
        XCTAssertEqual(choices.count, 13)
        XCTAssertEqual(selected[old.id.uuidString], choices)
        XCTAssertEqual(selected[replacement.id.uuidString], choices)
        XCTAssertEqual(images[old.id.uuidString], "kept.png")
        XCTAssertEqual(images[replacement.id.uuidString], "kept.png")
        for theme in appearance.availableThemes {
            appearance.setTheme(theme.slug)
            XCTAssertEqual(appearance.selectedEquipmentID(for: replacement), choices[theme.slug])
        }
    }

    @MainActor
    func testTaskIdentityTransferWriteFailureDoesNotPublishEitherCandidate() throws {
        let root = try temporaryDirectory()
        let slots = try boundWorkspace().slots.filter { $0.window != nil }
        let old = slots[0], replacement = slots[1]
        let chosen = ThemeResources.shared.equipmentItems(themeSlug: "relic")[8].id
        try writePreferences(root: root, selections: [old.id.uuidString: ["relic": chosen]], customImages: [old.id.uuidString: "kept.png"])
        let appearance = AppearanceModel(root: root)
        let originalReplacement = appearance.selectedEquipmentID(for: replacement)
        XCTAssertNotEqual(originalReplacement, chosen)
        let file = root.appendingPathComponent("appearance.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let marker = file.appendingPathComponent("retain.txt")
        try Data("unchanged".utf8).write(to: marker)
        XCTAssertThrowsError(try appearance.transferEquipment(from: old.id, to: replacement.id))
        XCTAssertEqual(appearance.selectedEquipmentID(for: replacement), originalReplacement)
        XCTAssertEqual(appearance.selectedEquipmentID(for: old), chosen)
        XCTAssertEqual(try String(contentsOf: marker), "unchanged")
    }

    @MainActor
    private func equipmentByTheme(_ appearance: AppearanceModel, slots: [TaskSlot]) throws -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for theme in appearance.availableThemes {
            appearance.setTheme(theme.slug)
            for slot in slots {
                result[slot.id.uuidString, default: [:]][theme.slug] = try XCTUnwrap(appearance.selectedEquipmentID(for: slot))
            }
        }
        return result
    }

    private func boundWorkspace() throws -> WorkspaceState {
        var workspace = WorkspaceState()
        for number in [2, 7] {
            let window = WindowIdentity(processID: Int32(100 + number), processStartedAt: Date(timeIntervalSince1970: Double(number)),
                bundleIdentifier: "example.Terminal", applicationName: "Terminal", title: "Task \(number)")
            try workspace.bind(window, to: number)
        }
        return workspace
    }

    private func preferences(at file: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    private func writePreferences(root: URL, selections: [String: [String: String]], customImages: [String: String] = [:]) throws {
        let values: [String: Any] = ["themeSlug": "relic", "decorations": true, "animate": false,
            "selections": selections, "customImages": customImages, "soundEnabled": false, "soundVolume": 0.2]
        try JSONSerialization.data(withJSONObject: values).write(to: root.appendingPathComponent("appearance.json"))
    }

    @MainActor
    private func smallPNG() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 8, bitsPerPixel: 32))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for pixel in 0..<4 {
            pixels[pixel * 4] = 255
            pixels[pixel * 4 + 1] = 0
            pixels[pixel * 4 + 2] = 0
            pixels[pixel * 4 + 3] = 255
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omnivibe-appearance-ordering-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
