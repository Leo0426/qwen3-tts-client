import Foundation
import Observation

public struct ClonedVoice: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let transcript: String
    public let createdAt: Date
    public let fileName: String
}

/// 克隆音色库：参考音频文件 + JSON 索引的持久化。
/// 隐藏磁盘布局，对外是增查删；合成时用 cloneReference(for:) 取引用。
@MainActor
@Observable
public final class ClonedVoiceStore {
    public private(set) var items: [ClonedVoice] = []

    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    /// - Parameter directory: 存储目录；默认 Application Support/Qwen3TTS/Voices（测试可注入临时目录）
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Qwen3TTS/Voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadIndex()
    }

    /// 参考音频拷贝进库（保留原始格式，合成时由引擎解码重采样）
    @discardableResult
    public func add(name: String, transcript: String, sourceAudioURL: URL) throws -> ClonedVoice {
        let id = UUID()
        let ext = sourceAudioURL.pathExtension.isEmpty ? "wav" : sourceAudioURL.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        try FileManager.default.copyItem(at: sourceAudioURL, to: directory.appendingPathComponent(fileName))
        let voice = ClonedVoice(id: id, name: name, transcript: transcript, createdAt: .now, fileName: fileName)
        items.insert(voice, at: 0)
        persistIndex()
        return voice
    }

    public func delete(_ voice: ClonedVoice) {
        items.removeAll { $0.id == voice.id }
        try? FileManager.default.removeItem(at: audioURL(for: voice))
        persistIndex()
    }

    public func audioURL(for voice: ClonedVoice) -> URL {
        directory.appendingPathComponent(voice.fileName)
    }

    public func cloneReference(for voice: ClonedVoice) -> CloneReference {
        CloneReference(audioURL: audioURL(for: voice), transcript: voice.transcript)
    }

    // MARK: - Internals

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ClonedVoice].self, from: data) else {
            return
        }
        items = decoded.filter { FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
