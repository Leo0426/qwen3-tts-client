import Foundation

/// 长文本分段：按句子边界切分，保证每段不超过模型单次生成的舒适长度。
public enum TextSegmenter {
    /// 句末标点（分段只发生在这些位置，保证段间停顿听感自然）
    private static let terminators: Set<Character> = ["。", "！", "？", "!", "?", ".", ";", "；", "\n"]

    public static func segment(_ text: String, maxLength: Int = 400) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        // 先切成完整句子（保留句末标点）
        var sentences: [String] = []
        var current = ""
        for character in trimmed {
            current.append(character)
            if terminators.contains(character) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            sentences.append(current)
        }

        // 句子累积成段；单句超长时按 maxLength 硬切
        var segments: [String] = []
        var buffer = ""
        for sentence in sentences {
            if !buffer.isEmpty, buffer.count + sentence.count > maxLength {
                segments.append(buffer)
                buffer = ""
            }
            if sentence.count > maxLength {
                var start = sentence.startIndex
                while start < sentence.endIndex {
                    let end = sentence.index(start, offsetBy: maxLength, limitedBy: sentence.endIndex) ?? sentence.endIndex
                    segments.append(String(sentence[start ..< end]))
                    start = end
                }
            } else {
                buffer += sentence
            }
        }
        if !buffer.isEmpty {
            segments.append(buffer)
        }

        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// 长文本装饰器：把文本分段后逐段交给底层引擎，音频块无缝拼入同一条流。
/// 对上层完全透明——任何 InferenceEngine 包一层即获得长文本能力。
public struct SegmentingEngine: InferenceEngine {
    private let base: any InferenceEngine
    private let maxSegmentLength: Int

    public init(base: any InferenceEngine, maxSegmentLength: Int = 400) {
        self.base = base
        self.maxSegmentLength = maxSegmentLength
    }

    public func synthesize(text: String, voice: Voice, options: SynthesisOptions) -> AsyncThrowingStream<AudioChunk, Error> {
        let segments = TextSegmenter.segment(text, maxLength: maxSegmentLength)
        guard segments.count > 1 else {
            return base.synthesize(text: text, voice: voice, options: options)
        }
        let base = base
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for segment in segments {
                        try Task.checkCancellation()
                        for try await chunk in base.synthesize(text: segment, voice: voice, options: options) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
