import Foundation

/// 开发与测试用引擎：按真实引擎的节奏（TTFB + 分块间隔）流式产出提示音，
/// 让 UI 和播放链路在运行时选型落地前就能完整开发和验证。
public struct FakeInferenceEngine: InferenceEngine {
    public let sampleRate: Double
    /// 模拟的首包延迟
    public let firstChunkDelay: TimeInterval
    /// 每块音频时长
    public let chunkDuration: TimeInterval

    public init(sampleRate: Double = 24_000, firstChunkDelay: TimeInterval = 0.5, chunkDuration: TimeInterval = 0.32) {
        self.sampleRate = sampleRate
        self.firstChunkDelay = firstChunkDelay
        self.chunkDuration = chunkDuration
    }

    public func synthesize(text: String, voice: Voice, options: SynthesisOptions) -> AsyncThrowingStream<AudioChunk, Error> {
        let sampleRate = sampleRate
        let firstChunkDelay = firstChunkDelay
        let chunkDuration = chunkDuration
        // 音频总时长与文本长度挂钩，粗略模拟真实语速（约每秒 5 字）。
        let totalDuration = max(1.0, Double(text.count) / 5.0)
        // 音色映射到不同基频，让切换音色在假引擎下也可感知。
        let baseFrequency = 220.0 * pow(2.0, Double(abs(voice.id.hashValue % 12)) / 12.0)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: .seconds(firstChunkDelay))
                    let chunkCount = Int((totalDuration / chunkDuration).rounded(.up))
                    let samplesPerChunk = Int(chunkDuration * sampleRate)
                    for chunkIndex in 0 ..< chunkCount {
                        try Task.checkCancellation()
                        let startSample = chunkIndex * samplesPerChunk
                        let samples = (0 ..< samplesPerChunk).map { offset -> Float in
                            let t = Double(startSample + offset) / sampleRate
                            // 每 0.8s 换一个音高，听感上像“内容在推进”
                            let step = Int(t / 0.8)
                            let frequency = baseFrequency * pow(2.0, Double(step % 5) / 12.0)
                            let envelope = min(1.0, t / 0.05) * 0.3
                            return Float(sin(2 * .pi * frequency * t) * envelope)
                        }
                        continuation.yield(AudioChunk(samples: samples, sampleRate: sampleRate))
                        // 模拟生成快于实时（RTF ≈ 2）
                        try await Task.sleep(for: .seconds(chunkDuration / 2))
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
