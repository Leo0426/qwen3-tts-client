import Foundation
import Testing
@testable import TTSCore

struct M4AFileTests {
    @Test func writeProducesReadableAACFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4AFileTests-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let sampleRate = 24_000.0
        let samples: [Float] = (0 ..< 24_000).map { sin(Float($0) * 0.05) * 0.5 }

        try M4AFile.write(samples: samples, sampleRate: sampleRate, to: url)

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 1_000)
        // AAC 有损 + 编码器首尾 padding，只验证时长量级一致
        let (readBack, rate) = try WavFile.read(from: url)
        #expect(rate == sampleRate)
        let duration = Double(readBack.count) / rate
        #expect(abs(duration - 1.0) < 0.15)
    }

    @Test func emptySamplesThrow() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("M4AFileTests-empty-\(UUID().uuidString).m4a")
        #expect(throws: (any Error).self) {
            try M4AFile.write(samples: [], sampleRate: 24_000, to: url)
        }
    }
}
