import Carbon
import Foundation
import XCTest
@testable import OmniVibeMac

final class ShortcutSchemeTests: XCTestCase {
    func testSchemesRoundTripWithStablePersistableRawValues() throws {
        XCTAssertEqual(ShortcutScheme.allCases.map(\.rawValue), ["optionNumbers", "inventoryFirst", "controlOption"])
        for scheme in ShortcutScheme.allCases {
            XCTAssertEqual(try JSONDecoder().decode(ShortcutScheme.self, from: JSONEncoder().encode(scheme)), scheme)
            XCTAssertEqual(ShortcutScheme(rawValue: scheme.rawValue), scheme)
        }
        XCTAssertNil(ShortcutScheme(rawValue: "future-unknown-scheme"))
    }

    func testOptionNumbersContainsExactlyTheRequestedDirectBindings() throws {
        let scheme = ShortcutScheme.optionNumbers
        XCTAssertEqual(scheme.taskBindings.map(\.action), (1...9).map { .slot($0) } + [.arrange])
        XCTAssertEqual(scheme.taskBindings.map(\.keyCode), [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_Grave])
        XCTAssertEqual(scheme.taskBindings.map(\.label), (1...9).map { "⌥\($0)" } + ["⌥`"])
        XCTAssertFalse(scheme.taskBindings.contains { $0.keyCode == kVK_ANSI_0 })
        XCTAssertTrue(scheme.taskBindings.allSatisfy { $0.modifiers == UInt32(optionKey) })
        XCTAssertEqual(scheme.wheelBindings.map(\.action), [.aim, .toggleVisibility])
        XCTAssertEqual(scheme.wheelBindings.map(\.keyCode), [kVK_ANSI_Q, kVK_ANSI_H])
        XCTAssertEqual(scheme.wheelBindings.map(\.label), ["⌥Q", "⌥H"])
        XCTAssertTrue(scheme.wheelBindings.allSatisfy { $0.modifiers == UInt32(optionKey) })
        XCTAssertEqual(try XCTUnwrap(scheme.binding(for: .cancelModified)).label, "⌥Esc")
        XCTAssertNil(scheme.binding(for: .inventory))
    }

    func testOriginalSchemeKeepsExactKeysWithControlOptionModifiers() throws {
        let scheme = ShortcutScheme.controlOption
        XCTAssertEqual(scheme.taskBindings.count, 10)
        XCTAssertEqual(scheme.wheelBindings.count, 2)
        XCTAssertEqual(scheme.taskBindings.dropLast().map(\.keyCode), ShortcutScheme.optionNumbers.taskBindings.dropLast().map(\.keyCode))
        XCTAssertEqual(scheme.taskBindings.last?.keyCode, kVK_ANSI_0)
        XCTAssertEqual(scheme.wheelBindings.map(\.keyCode), ShortcutScheme.optionNumbers.wheelBindings.map(\.keyCode))
        XCTAssertTrue((scheme.taskBindings + scheme.wheelBindings).allSatisfy { $0.modifiers == UInt32(controlKey | optionKey) })
        XCTAssertEqual(try XCTUnwrap(scheme.binding(for: .slot(3))).label, "⌃⌥3")
        XCTAssertEqual(try XCTUnwrap(scheme.binding(for: .arrange)).label, "⌃⌥0")
        XCTAssertEqual(try XCTUnwrap(scheme.binding(for: .cancelModified)).label, "⌃⌥Esc")
    }

    func testInventoryFirstHasOnlyOptionSpaceAndNeverReservesGlobalNumberOrWheelKeys() throws {
        let scheme = ShortcutScheme.inventoryFirst
        XCTAssertTrue(scheme.taskBindings.isEmpty)
        XCTAssertEqual(scheme.wheelBindings.count, 1)
        let binding = try XCTUnwrap(scheme.binding(for: .inventory))
        XCTAssertEqual(scheme.wheelBindings, [binding])
        XCTAssertEqual(binding.action, .inventory)
        XCTAssertEqual(binding.keyCode, kVK_Space)
        XCTAssertEqual(binding.modifiers, UInt32(optionKey))
        XCTAssertEqual(binding.label, "⌥Space")
        for action in (1...9).map({ ShortcutAction.slot($0) }) + [.arrange, .aim, .toggleVisibility, .cancelModified] {
            XCTAssertNil(scheme.binding(for: action))
        }
    }

    func testInvalidSlotNumbersNeverBecomeAKeyBindingAndSchemesHaveNoDuplicateGlobalChords() {
        for scheme in ShortcutScheme.allCases {
            for number in [-1, 0, 10, Int.max] { XCTAssertNil(scheme.binding(for: .slot(number))) }
            let bindings = scheme.taskBindings + scheme.wheelBindings
            XCTAssertEqual(Set(bindings.map { "\($0.keyCode):\($0.modifiers)" }).count, bindings.count)
        }
    }
}
