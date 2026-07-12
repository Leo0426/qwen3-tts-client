import Foundation
import Observation

public struct DesignedVoice: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    /// 自然语言声音描述，如“一个低沉磁性的中年男声，语速平缓”
    public let prompt: String
    public let createdAt: Date
}

/// 设计音色库：命名的声音描述，JSON 持久化。
@MainActor
@Observable
public final class DesignedVoiceStore {
    public private(set) var items: [DesignedVoice] = []

    private let indexURL: URL

    /// - Parameter directory: 存储目录；默认 Application Support/Qwen3TTS（测试可注入临时目录）
    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Qwen3TTS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        indexURL = dir.appendingPathComponent("designed-voices.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([DesignedVoice].self, from: data) {
            items = decoded
        }
    }

    @discardableResult
    public func add(name: String, prompt: String) -> DesignedVoice {
        let voice = DesignedVoice(id: UUID(), name: name, prompt: prompt, createdAt: .now)
        items.insert(voice, at: 0)
        persist()
        return voice
    }

    public func delete(_ voice: DesignedVoice) {
        items.removeAll { $0.id == voice.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
