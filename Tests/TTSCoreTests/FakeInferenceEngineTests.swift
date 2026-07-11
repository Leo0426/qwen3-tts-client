import Testing
@testable import TTSCore

struct FakeInferenceEngineTests {
    @Test func streamsAudioProportionalToTextLength() async throws {
        let engine = FakeInferenceEngine(firstChunkDelay: 0, chunkDuration: 0.1)
        var totalSamples = 0
        var chunkCount = 0
        for try await chunk in engine.synthesize(text: String(repeating: "测", count: 25), voice: .default) {
            #expect(chunk.sampleRate == 24_000)
            totalSamples += chunk.samples.count
            chunkCount += 1
        }
        // 25 字 ≈ 5s 音频
        #expect(chunkCount > 1)
        #expect(abs(Double(totalSamples) / 24_000 - 5.0) < 0.2)
    }

    @Test func cancellationTerminatesStream() async throws {
        let engine = FakeInferenceEngine(firstChunkDelay: 0, chunkDuration: 0.1)
        let task = Task {
            var received = 0
            do {
                for try await _ in engine.synthesize(text: String(repeating: "长", count: 500), voice: .default) {
                    received += 1
                    if received == 2 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            } catch {
                // 取消以抛出（CancellationError）或流终止两种方式结束都可接受
            }
            return received
        }
        let received = await task.value
        #expect(received < 10, "取消后流应尽快终止")
    }
}
