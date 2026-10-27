import AppKit
import AVFoundation
import Combine
import Foundation

enum AudioCue: String, CaseIterable, Sendable {
    case `switch`, capture, remove, expand, collapse, arrange, restore, reorder
    case inventoryOpen = "inventoryopen"
    case inventoryClose = "inventoryclose"
    case waiting, ready, error, detent
}

/// Short, bounded playback work stays away from window activation and drawing.
/// This class never records audio, launches a player process, or requests input access.
@MainActor
final class ThemeAudio {
    private static let worker = ThemeAudioWorker()
    private let appearance: AppearanceModel
    private var subscriptions = Set<AnyCancellable>()
    private var lastSubmitted: [String: TimeInterval] = [:]

    init(appearance: AppearanceModel) {
        self.appearance = appearance
        appearance.$soundEnabled.combineLatest(appearance.$soundVolume).sink { enabled, volume in
            if !enabled || !volume.isFinite || volume <= 0 { Self.worker.stop() }
        }.store(in: &subscriptions)
        appearance.$themeSlug.dropFirst().sink { _ in Self.worker.stop() }.store(in: &subscriptions)
    }

    func play(_ cue: AudioCue) {
        // Check mute before even resolving or opening an audio resource.
        guard appearance.soundEnabled, appearance.soundVolume.isFinite, appearance.soundVolume > 0 else { return }
        let key = appearance.themeSlug + ":" + cue.rawValue
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (lastSubmitted[key] ?? -.infinity) >= 0.08 else { return }
        lastSubmitted[key] = now
        guard let url = Self.resourceURL(for: cue, themeSlug: appearance.themeSlug) else { return }
        let gain = cue == .ready ? appearance.soundVolume * 0.5 : appearance.soundVolume
        Self.worker.submit(url: url, volume: gain, identity: key)
    }

    /// An explicit audition can be used with a muted settings draft. It does not save it.
    func preview(_ cue: AudioCue, themeSlug: String? = nil, volume: Double? = nil) {
        let level = Self.safeVolume(volume ?? appearance.soundVolume)
        guard level > 0, let url = Self.resourceURL(for: cue, themeSlug: themeSlug ?? appearance.themeSlug) else { return }
        Self.worker.stop()
        Self.worker.submit(url: url, volume: cue == .ready ? level * 0.5 : level, identity: "preview")
    }

    func previewFile(_ url: URL, volume: Double) throws {
        let level = Self.safeVolume(volume)
        guard level > 0 else { return }
        let data = try Self.readValidatedWave(url)
        Self.worker.stop()
        Self.worker.submit(url: url, volume: level, identity: "preview", preparedData: data)
    }

    func stop() { Self.worker.stop() }

    static func hasSound(_ cue: AudioCue, themeSlug: String) -> Bool {
        resourceURL(for: cue, themeSlug: themeSlug) != nil
    }

    static func resourceURL(for cue: AudioCue, themeSlug: String) -> URL? {
        guard !themeSlug.isEmpty, themeSlug.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
        }) else { return nil }
        let resources = ThemeResources.shared.root
        let url: URL
        if cue == .switch {
            let custom = customAudioRoot.appendingPathComponent(themeSlug).appendingPathComponent("signature.wav")
            if FileManager.default.fileExists(atPath: custom.path) { return custom }
            // Match Windows: three bundled CC0 signatures; missing local game
            // signatures remain silent rather than using a synthetic substitute.
            url = resources.appendingPathComponent("skins/signature-audio/bundled/\(themeSlug)/signature.wav")
        } else if cue == .ready {
            url = resources.appendingPathComponent("skins/completion-audio/\(themeSlug)/complete.wav")
        } else {
            url = resources.appendingPathComponent("skins/audio/\(themeSlug)/\(cue.rawValue).wav")
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Called only after the user explicitly saves a selected local WAV.
    static func importSignature(from source: URL, themeSlug: String) throws {
        guard ThemeResources.shared.themes.contains(where: { $0.slug == themeSlug }) else { throw AudioImportError.invalidTheme }
        let data = try readValidatedWave(source)
        let folder = customAudioRoot.appendingPathComponent(themeSlug, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("signature.wav")
        if FileManager.default.fileExists(atPath: target.path) {
            let backup = folder.appendingPathComponent("signature.backup-\(UUID().uuidString).wav")
            try FileManager.default.copyItem(at: target, to: backup)
        }
        try data.write(to: target, options: .atomic)
        worker.invalidate(path: target.path)
    }

    static var customAudioRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OmniVibe/Audio", isDirectory: true)
    }

    private static func readValidatedWave(_ url: URL) throws -> Data {
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard properties.isRegularFile == true, let size = properties.fileSize, size > 44, size <= 1_200_000 else {
            throw AudioImportError.invalidFormat
        }
        let data = try Data(contentsOf: url)
        guard waveDuration(data) != nil else { throw AudioImportError.invalidFormat }
        return data
    }

    /// Same custom-input boundary as Windows: PCM16 mono/stereo, 16–96 kHz, <=3 s.
    nonisolated static func waveDuration(_ data: Data) -> Double? {
        let bytes = [UInt8](data)
        guard bytes.count > 44, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        guard u32(4) >= 36, u32(4) <= bytes.count - 8 else { return nil }
        var offset = 12, rate = 0, channels = 0, blockAlign = 0, sampleBytes = 0
        var formatSeen = false, dataSeen = false
        while offset + 8 <= bytes.count {
            let length = u32(offset + 4)
            let content = offset + 8
            guard length >= 0, length <= bytes.count - content else { return nil }
            let kind = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
            if kind == "fmt " {
                guard !formatSeen, length >= 16, u16(content) == 1, u16(content + 14) == 16 else { return nil }
                formatSeen = true
                channels = u16(content + 2); rate = u32(content + 4); blockAlign = u16(content + 12)
            } else if kind == "data" {
                guard !dataSeen else { return nil }
                dataSeen = true; sampleBytes = length
            }
            offset = content + length + length % 2
        }
        guard (channels == 1 || channels == 2), (16_000...96_000).contains(rate),
              blockAlign == channels * 2, sampleBytes > 0, sampleBytes % blockAlign == 0 else { return nil }
        let duration = Double(sampleBytes) / Double(rate * blockAlign)
        return duration > 0 && duration <= 3 ? duration : nil
    }

    private static func safeVolume(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

private enum AudioImportError: LocalizedError {
    case invalidFormat, invalidTheme
    var errorDescription: String? {
        let localizedSource: String? = {
            switch self {
            case .invalidFormat: return "请选择不超过 3 秒的 PCM16 WAV（单声道或立体声、16–96 kHz，最大 1.2 MB）。"
            case .invalidTheme: return "主题不存在，未保存声音。"
            }
    }()
        return localizedSource.map { L10n.errorText($0) }
    }
}

/// A single application-wide output pool: <=4 pending requests, <=4 voices,
/// <=32 cached files and <=8 MiB of source WAV data. No playback wait is queued.
private final class ThemeAudioWorker: @unchecked Sendable {
    private struct Request: Sendable {
        let url: URL
        let volume: Float
        let identity: String
        let generation: UInt64
        let preparedData: Data?
    }
    private struct Voice {
        let path: String
        let player: AVAudioPlayer
        let generation: UInt64
    }
    private struct CachedSound {
        let data: Data
        let modifiedAt: Date?
        let size: Int
    }
    private let queue = DispatchQueue(label: "io.github.xiobio.OmniVibe.audio", qos: .userInitiated)
    private let lock = NSLock()
    private var pending: [Request] = []
    private var scheduled = false
    private var generation: UInt64 = 0
    // The following fields are accessed only by queue.
    private var voices: [Voice] = []
    private var cache: [String: CachedSound] = [:]
    private var order: [String] = []
    private var cachedBytes = 0

    func submit(url: URL, volume: Double, identity: String, preparedData: Data? = nil) {
        guard volume.isFinite, volume > 0 else { return }
        lock.lock()
        pending.removeAll { $0.identity == identity }
        pending.append(Request(url: url, volume: Float(min(1, volume)), identity: identity,
                               generation: generation, preparedData: preparedData))
        if pending.count > 4 { pending.removeFirst(pending.count - 4) }
        let shouldStart = !scheduled
        scheduled = true
        lock.unlock()
        if shouldStart { queue.async { [self] in drain() } }
    }

    func stop() {
        lock.lock()
        generation &+= 1
        let cutoff = generation
        pending.removeAll()
        lock.unlock()
        queue.async { [self] in
            voices.filter { $0.generation < cutoff }.forEach { $0.player.stop() }
            voices.removeAll { $0.generation < cutoff }
        }
    }

    func invalidate(path: String) {
        lock.lock()
        generation &+= 1
        let cutoff = generation
        pending.removeAll()
        lock.unlock()
        queue.async { [self] in
            if let previous = cache.removeValue(forKey: path) { cachedBytes -= previous.data.count }
            order.removeAll { $0 == path }
            voices.filter { $0.path == path && $0.generation < cutoff }.forEach { $0.player.stop() }
            voices.removeAll { $0.path == path && $0.generation < cutoff }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !pending.isEmpty else { scheduled = false; lock.unlock(); return }
            let request = pending.removeFirst()
            lock.unlock()
            do {
                guard current(request.generation) else { continue }
                let data = try request.preparedData ?? soundData(at: request.url)
                guard current(request.generation) else { continue }
                let player = try AVAudioPlayer(data: data)
                player.volume = request.volume
                guard current(request.generation) else { continue }
                voices.removeAll { !$0.player.isPlaying }
                if voices.count >= 4 { voices.removeFirst().player.stop() }
                if player.play() { voices.append(Voice(path: request.url.path, player: player, generation: request.generation)) }
            } catch {
                // Missing/corrupt resources or an unavailable output device are
                // silent failures; navigation and task state remain unaffected.
            }
        }
    }

    private func current(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }

    private func soundData(at url: URL) throws -> Data {
        let key = url.path
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey])
        guard properties.isRegularFile == true, let size = properties.fileSize, size > 0, size <= 1_200_000 else {
            throw AudioImportError.invalidFormat
        }
        if let cached = cache[key], cached.size == size, cached.modifiedAt == properties.contentModificationDate {
            order.removeAll { $0 == key }; order.append(key)
            return cached.data
        }
        let data = try Data(contentsOf: url)
        guard ThemeAudio.waveDuration(data) != nil else { throw AudioImportError.invalidFormat }
        if let previous = cache.removeValue(forKey: key) { cachedBytes -= previous.data.count }
        order.removeAll { $0 == key }
        cache[key] = CachedSound(data: data, modifiedAt: properties.contentModificationDate, size: size)
        order.append(key); cachedBytes += data.count
        while order.count > 32 || cachedBytes > 8 * 1024 * 1024 {
            let oldest = order.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) { cachedBytes -= removed.data.count }
        }
        return data
    }
}
