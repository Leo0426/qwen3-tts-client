import Foundation
import Observation

public struct StoredHistoryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let voiceID: String
    public let sampleRate: Double
    public let duration: TimeInterval
    public let fileName: String
}

/// 历史记录：音频缓存文件 + JSON 索引的持久化。
/// 隐藏磁盘布局与文件管理，对外是增查删。
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var items: [StoredHistoryItem] = []

    private let directory: URL
    private let maxItems: Int
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    /// - Parameter directory: 存储目录；默认 Application Support/Qwen3TTS/History（测试可注入临时目录）
    public init(directory: URL? = nil, maxItems: Int = 50) {
        self.maxItems = maxItems
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Qwen3TTS/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadIndex()
    }

    @discardableResult
    public func add(text: String, voice: Voice, samples: [Float], sampleRate: Double) throws -> StoredHistoryItem {
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        try WavFile.write(samples: samples, sampleRate: sampleRate, to: directory.appendingPathComponent(fileName))
        let item = StoredHistoryItem(
            id: id,
            date: .now,
            text: text,
            voiceID: voice.id,
            sampleRate: sampleRate,
            duration: Double(samples.count) / sampleRate,
            fileName: fileName
        )
        items.insert(item, at: 0)
        trimToCapacity()
        persistIndex()
        return item
    }

    public func delete(_ item: StoredHistoryItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: audioURL(for: item))
        persistIndex()
    }

    public func audioURL(for item: StoredHistoryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    public func samples(for item: StoredHistoryItem) throws -> (samples: [Float], sampleRate: Double) {
        try WavFile.read(from: audioURL(for: item))
    }

    // MARK: - Internals

    private func trimToCapacity() {
        while items.count > maxItems {
            let removed = items.removeLast()
            try? FileManager.default.removeItem(at: audioURL(for: removed))
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([StoredHistoryItem].self, from: data) else {
            return
        }
        // 只保留音频文件仍然存在的条目
        items = decoded.filter { FileManager.default.fileExists(atPath: audioURL(for: $0).path) }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
