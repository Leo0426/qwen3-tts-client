import Foundation
import Testing
@testable import TTSCore

@MainActor
struct ClonedVoiceStoreTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClonedVoiceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addCopiesAudioAndPersists() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.wav")
        try WavFile.write(samples: [0.1, 0.2, 0.3], sampleRate: 24_000, to: source)

        let store = ClonedVoiceStore(directory: dir)
        let voice = try store.add(name: "我的声音", transcript: "参考文字稿", sourceAudioURL: source)

        #expect(store.items.count == 1)
        #expect(FileManager.default.fileExists(atPath: store.audioURL(for: voice).path))

        let reference = store.cloneReference(for: voice)
        #expect(reference.transcript == "参考文字稿")
        #expect(reference.audioURL == store.audioURL(for: voice))

        // 重新加载：索引持久化生效
        let reloaded = ClonedVoiceStore(directory: dir)
        #expect(reloaded.items == store.items)
    }

    @Test func deleteRemovesAudioFile() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.wav")
        try WavFile.write(samples: [0.1], sampleRate: 24_000, to: source)

        let store = ClonedVoiceStore(directory: dir)
        let voice = try store.add(name: "x", transcript: "y", sourceAudioURL: source)
        let audioPath = store.audioURL(for: voice).path

        store.delete(voice)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audioPath))
    }
}
