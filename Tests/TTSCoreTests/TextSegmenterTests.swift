import Testing
@testable import TTSCore

struct TextSegmenterTests {
    @Test func shortTextStaysWhole() {
        let segments = TextSegmenter.segment("你好，世界。", maxLength: 400)
        #expect(segments == ["你好，世界。"])
    }

    @Test func emptyTextYieldsNothing() {
        #expect(TextSegmenter.segment("   \n  ", maxLength: 400).isEmpty)
    }

    @Test func splitsAtSentenceBoundaries() {
        let sentence = String(repeating: "字", count: 60) + "。"
        let text = String(repeating: sentence, count: 5) // 305 字，5 句
        let segments = TextSegmenter.segment(text, maxLength: 130)
        // 每段不超限且都在句末结束
        #expect(segments.count == 3)
        for segment in segments {
            #expect(segment.count <= 130)
            #expect(segment.hasSuffix("。"))
        }
        #expect(segments.joined() == text)
    }

    @Test func hardSplitsOverlongSentence() {
        let text = String(repeating: "字", count: 900) // 无任何标点
        let segments = TextSegmenter.segment(text, maxLength: 400)
        #expect(segments.count == 3)
        #expect(segments.joined().count == 900)
        #expect(segments.allSatisfy { $0.count <= 400 })
    }

    @Test func mixedPunctuationAndNewlines() {
        let text = "第一段内容！第二句呢？\n英文 sentence here. 结尾没有标点的尾巴"
        let segments = TextSegmenter.segment(text, maxLength: 12)
        #expect(!segments.isEmpty)
        // 内容不丢（忽略被 trim 的空白）
        let joined = segments.joined()
        #expect(joined.contains("第一段内容！"))
        #expect(joined.contains("结尾没有标点的尾巴"))
    }
}

struct SegmentingEngineTests {
    @Test func streamsAllSegmentsContinuously() async throws {
        let fake = FakeInferenceEngine(firstChunkDelay: 0, chunkDuration: 0.1)
        let engine = SegmentingEngine(base: fake, maxSegmentLength: 50)
        // 3 段 × 每段约 30 字（约 6s 音频/段）
        let sentence = String(repeating: "测", count: 29) + "。"
        let text = sentence + sentence + sentence

        var totalDuration = 0.0
        for try await chunk in engine.synthesize(text: text, voice: .default, options: .default) {
            totalDuration += chunk.duration
        }
        // 假引擎按 5 字/秒：3 段共 90 字 ≈ 18s（每段各自向上取整，允许少量误差）
        #expect(totalDuration > 15, "三段的音频都应到达，实际 \(totalDuration)s")
    }

    @Test func cancellationStopsRemainingSegments() async throws {
        let fake = FakeInferenceEngine(firstChunkDelay: 0, chunkDuration: 0.1)
        let engine = SegmentingEngine(base: fake, maxSegmentLength: 50)
        let sentence = String(repeating: "长", count: 49) + "。"
        let text = String(repeating: sentence, count: 10)

        let received = await Task {
            var count = 0
            do {
                for try await _ in engine.synthesize(text: text, voice: .default, options: .default) {
                    count += 1
                    if count == 3 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            } catch {}
            return count
        }.value
        #expect(received < 20, "取消后不应继续吐出后续段的音频")
    }
}
