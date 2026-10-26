import CoreFoundation
import Foundation

/// Reads only Terminal's profile dictionary. No saved state, shell history,
/// tab contents, session files, or preference mutations are part of this API.
protocol TerminalProfilePreferencesReading: AnyObject {
    func profileData(named: String) throws -> Data
}

final class TerminalProfilePreferencesReader: TerminalProfilePreferencesReading {
    func profileData(named name: String) throws -> Data {
        guard name.hasPrefix("OmniVibe Recovery "), UUID(uuidString: String(name.dropFirst("OmniVibe Recovery ".count))) != nil else {
            throw TerminalProfileApplicationError.invalidRecoveryBaseline
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.2
        repeat {
            if let all = CFPreferencesCopyValue("Window Settings" as CFString, "com.apple.Terminal" as CFString,
                kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any],
               let profile = all[name] as? [String: Any] {
                guard all.count <= 512, profile["name"] as? String == name,
                      profile["type"] as? String == "Window Settings",
                      PropertyListSerialization.propertyList(profile, isValidFor: .binary) else {
                    throw TerminalProfileApplicationError.nativeCopyNotPersisted
                }
                let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
                guard !data.isEmpty, data.count <= 2 * 1_048_576 else {
                    throw TerminalProfileApplicationError.nativeCopyNotPersisted
                }
                return data
            }
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
        throw TerminalProfileApplicationError.nativeCopyNotPersisted
    }
}
