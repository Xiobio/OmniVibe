import Carbon
import Foundation
import XCTest
@testable import OmniVibeMac

final class ShortcutConfigurationTests: XCTestCase {
    func testPresetsRemainEquivalentAndActionsHaveStableCodableIdentifiers() throws {
        XCTAssertEqual(ShortcutConfiguration.configurableActions.count, 13)
        for scheme in ShortcutScheme.allCases {
            let configuration = ShortcutConfiguration(base: scheme)
            try configuration.validate()
            XCTAssertEqual(configuration.taskBindings, scheme.taskBindings)
            XCTAssertEqual(configuration.wheelBindings, scheme.wheelBindings)
            XCTAssertFalse(configuration.isCustomized)
            for action in ShortcutConfiguration.configurableActions {
                XCTAssertEqual(try JSONDecoder().decode(ShortcutAction.self, from: JSONEncoder().encode(action)), action)
            }
        }
        XCTAssertEqual(try String(decoding: JSONEncoder().encode(ShortcutAction.slot(4)), as: UTF8.self), "\"slot4\"")
    }

    func testCustomBindingAndDisabledActionRoundTripWithoutLosingPreset() throws {
        let custom = try binding(.slot(1), key: kVK_ANSI_K, modifiers: UInt32(controlKey), name: "K")
        let configuration = try ShortcutConfiguration(base: .optionNumbers).setting(custom).disabling(.toggleVisibility)
        let reloaded = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(reloaded, configuration)
        XCTAssertEqual(reloaded.base, .optionNumbers)
        XCTAssertEqual(reloaded.binding(for: .slot(1)), custom)
        XCTAssertNil(reloaded.binding(for: .toggleVisibility))
        XCTAssertEqual(reloaded.taskBindings.count, 10)
        XCTAssertEqual(reloaded.wheelBindings.map(\.action), [.aim])
        XCTAssertTrue(reloaded.isCustomized)
        XCTAssertEqual(reloaded.customization(for: .toggleVisibility), .disabled)
        XCTAssertEqual(reloaded.slotRangeLabel, "自定义任务快捷键")
    }

    func testInventoryFirstCanExplicitlyEnableAnyTaskActionAndOptionPresetCanAddInventory() throws {
        let custom = try binding(.slot(3), key: kVK_F2, modifiers: UInt32(controlKey), name: "F2")
        let first = try ShortcutConfiguration(base: .inventoryFirst).setting(custom)
        XCTAssertEqual(first.taskBindings, [custom])
        XCTAssertEqual(first.wheelBindings.map(\.action), [.inventory])
        let inventory = try binding(.inventory, key: kVK_Space, modifiers: UInt32(optionKey), name: " ")
        let direct = try ShortcutConfiguration(base: .optionNumbers).setting(inventory)
        XCTAssertEqual(inventory.label, "⌥Space")
        XCTAssertEqual(direct.wheelBindings.map(\.action), [.aim, .toggleVisibility, .inventory])
    }

    func testCrossServiceDuplicateIsRejectedAtomicallyButDifferentModifiersAreAllowed() throws {
        let original = ShortcutConfiguration(base: .optionNumbers)
        let duplicate = try binding(.slot(1), key: kVK_ANSI_Q, modifiers: UInt32(optionKey), name: "Q")
        XCTAssertThrowsError(try original.setting(duplicate)) { error in
            XCTAssertTrue(error.localizedDescription.contains("⌥Q"))
            XCTAssertTrue(error.localizedDescription.contains("任务 1"))
            XCTAssertTrue(error.localizedDescription.contains("轮盘"))
        }
        XCTAssertEqual(original.binding(for: .slot(1))?.label, "⌥1")
        XCTAssertFalse(original.isCustomized)
        let distinct = try binding(.slot(1), key: kVK_ANSI_Q, modifiers: UInt32(controlKey), name: "Q")
        XCTAssertEqual(try original.setting(distinct).binding(for: .slot(1)), distinct)
        let freed = try original.disabling(.aim).setting(duplicate)
        XCTAssertEqual(freed.binding(for: .slot(1)), duplicate)
        XCTAssertNil(freed.binding(for: .cancelModified))
    }

    func testDisablingAndResettingPreserveAnExplicitChoiceAndRejectNewCollisions() throws {
        let base = ShortcutConfiguration(base: .optionNumbers)
        let disabled = try base.disabling(.arrange)
        XCTAssertNil(disabled.binding(for: .arrange))
        XCTAssertEqual(try disabled.resetting(.arrange), base)

        let moved = try base.setting(binding(.slot(1), key: kVK_ANSI_K, modifiers: UInt32(optionKey), name: "K"))
        let reused = try moved.setting(binding(.slot(2), key: kVK_ANSI_1, modifiers: UInt32(optionKey), name: "1"))
        XCTAssertThrowsError(try reused.resetting(.slot(1)))
        XCTAssertEqual(reused.binding(for: .slot(1))?.label, "⌥K")
    }

    func testChangingBaseCanPreserveOrClearCustomizationsAndCannotIntroduceDuplicate() throws {
        let custom = try binding(.slot(1), key: kVK_ANSI_K, modifiers: UInt32(controlKey), name: "K")
        let first = try ShortcutConfiguration(base: .optionNumbers).setting(custom).disabling(.arrange)
        let retained = try first.changingBase(to: .controlOption)
        XCTAssertEqual(retained.binding(for: .slot(1)), custom)
        XCTAssertNil(retained.binding(for: .arrange))
        XCTAssertEqual(try first.changingBase(to: .controlOption, preservingOverrides: false), ShortcutConfiguration(base: .controlOption))

        let conditional = try ShortcutConfiguration(base: .inventoryFirst)
            .setting(binding(.slot(1), key: kVK_ANSI_Q, modifiers: UInt32(optionKey), name: "Q"))
        XCTAssertThrowsError(try conditional.changingBase(to: .optionNumbers))
    }

    func testModifiedEscapeTracksTheEffectiveAimBindingAndDisappearsWhenAimIsDisabled() throws {
        let modifiers = UInt32(controlKey | shiftKey)
        let configuration = try ShortcutConfiguration(base: .inventoryFirst)
            .setting(binding(.aim, key: kVK_F2, modifiers: modifiers, name: "F2"))
        let cancel = try XCTUnwrap(configuration.binding(for: .cancelModified))
        XCTAssertEqual(cancel.keyCode, kVK_Escape)
        XCTAssertEqual(cancel.modifiers, modifiers)
        XCTAssertEqual(cancel.label, "⌃⇧Esc")
        XCTAssertNil(try configuration.disabling(.aim).binding(for: .cancelModified))
        XCTAssertThrowsError(try configuration.disabling(.cancelModified))
    }

    func testRecordingRequiresValidKeyAndCarbonModifiersAndGeneratesDisplayGlyphs() throws {
        let recorded = try binding(.arrange, key: kVK_ANSI_K, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), name: "K")
        XCTAssertEqual(recorded.label, "⌃⌥⇧⌘K")
        for modifiers: UInt32 in [0, 524_288, UInt32(optionKey) | (1 << 23)] {
            XCTAssertThrowsError(try binding(.arrange, key: kVK_ANSI_K, modifiers: modifiers, name: "K"))
        }
        for key in [-1, 128, kVK_Option, kVK_RightControl, kVK_Function, kVK_CapsLock] {
            XCTAssertThrowsError(try binding(.arrange, key: key, modifiers: UInt32(optionKey), name: "Key"))
        }
        XCTAssertThrowsError(try binding(.slot(10), key: kVK_ANSI_K, modifiers: UInt32(optionKey), name: "K"))
        for name in ["", "A\nB", "⌥K"] {
            XCTAssertThrowsError(try binding(.arrange, key: kVK_ANSI_K, modifiers: UInt32(optionKey), name: name))
        }
    }

    func testProtectionIsLimitedToEscapeAndCommonCommandSystemChords() throws {
        XCTAssertThrowsError(try binding(.arrange, key: kVK_Escape, modifiers: UInt32(optionKey), name: "Esc"))
        for key in [kVK_ANSI_Q, kVK_Tab, kVK_Space] {
            for modifiers in [UInt32(cmdKey), UInt32(cmdKey | shiftKey), UInt32(cmdKey | controlKey)] {
                XCTAssertThrowsError(try binding(.arrange, key: key, modifiers: modifiers, name: "Key"))
            }
        }
        for (key, modifiers, name) in [(kVK_ANSI_K, UInt32(cmdKey), "K"),
            (kVK_ANSI_W, UInt32(cmdKey), "W"), (kVK_ANSI_1, UInt32(cmdKey), "1"),
            (kVK_ANSI_Q, UInt32(optionKey), "Q"), (kVK_F1, UInt32(shiftKey), "F1")] {
            XCTAssertNoThrow(try binding(.arrange, key: key, modifiers: modifiers, name: name))
        }
    }

    func testDecodingInvalidOrDuplicateConfigurationFailsClosed() throws {
        let duplicate = ShortcutBinding(action: .slot(1), keyCode: kVK_ANSI_Q, modifiers: UInt32(optionKey), label: "⌥Q")
        let mismatch = ShortcutBinding(action: .slot(2), keyCode: kVK_ANSI_K, modifiers: UInt32(optionKey), label: "⌥K")
        let invalid = ShortcutBinding(action: .slot(1), keyCode: kVK_ANSI_K, modifiers: 0, label: "K")
        for override in [ShortcutConfiguration.Override.binding(duplicate), .binding(mismatch), .binding(invalid)] {
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(override))
            let data = try JSONSerialization.data(withJSONObject: ["base": "optionNumbers", "overrides": ["slot1": value]])
            XCTAssertThrowsError(try JSONDecoder().decode(ShortcutConfiguration.self, from: data))
        }
        let unknown = try JSONSerialization.data(withJSONObject: ["base": "optionNumbers", "overrides": ["futureAction": ["disabled": [:]]]])
        XCTAssertThrowsError(try JSONDecoder().decode(ShortcutConfiguration.self, from: unknown))
        let empty = Data("{\"base\":\"optionNumbers\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutConfiguration.self, from: empty), ShortcutConfiguration(base: .optionNumbers))
    }

    private func binding(_ action: ShortcutAction, key: Int, modifiers: UInt32, name: String) throws -> ShortcutBinding {
        try ShortcutBinding.recorded(action: action, physicalKeyCode: key, modifiers: modifiers, keyLabel: name)
    }
}
