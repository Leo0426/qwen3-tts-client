import Foundation
import Testing
@testable import TTSCore

@MainActor
struct HistoryStoreTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addPersistsAndRoundTripsAudio() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let samples: [Float] = (0 ..< 24_000).map { sin(Float($0) * 0.01) * 0.5 }

        let item = try store.add(text: "测试文本", voice: .default, samples: samples, sampleRate: 24_000)
        #expect(store.items.count == 1)
        #expect(abs(item.duration - 1.0) < 0.001)

        let (readBack, rate) = try store.samples(for: item)
        #expect(rate == 24_000)
        #expect(readBack.count == samples.count)
        #expect(abs(readBack[100] - samples[100]) < 0.0001)

        // 重新加载：索引持久化生效
        let reloaded = HistoryStore(directory: dir)
        #expect(reloaded.items == store.items)
    }

    @Test func deleteRemovesItemAndFile() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let item = try store.add(text: "x", voice: .default, samples: [0.1, 0.2, 0.3], sampleRate: 24_000)
        let fileURL = store.audioURL(for: item)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.delete(item)
        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func capacityTrimsOldestWithFiles() throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, maxItems: 3)
        var first: StoredHistoryItem?
        for i in 0 ..< 5 {
            let item = try store.add(text: "第\(i)条", voice: .default, samples: [0.1], sampleRate: 24_000)
            if i == 0 { first = item }
        }
        #expect(store.items.count == 3)
        #expect(store.items.first?.text == "第4条")
        if let first {
            #expect(!FileManager.default.fileExists(atPath: store.audioURL(for: first).path))
        }
    }
}
