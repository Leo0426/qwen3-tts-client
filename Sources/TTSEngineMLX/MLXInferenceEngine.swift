import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS
import TTSCore

/// 真实推理引擎：MLX Swift（ADR-0001）。
/// 隐藏模型加载、DashScope 之外的一切运行时细节：HF 权重解析、tokenization、
/// 自回归生成与 codec 解码。对外只有 InferenceEngine 的「文本+音色 → 音频块流」。
public final class MLXInferenceEngine: InferenceEngine {
    /// MVP 默认模型：预置音色变体，8bit 量化
    public static let defaultModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"

    /// 与播放缓冲匹配的流式分块间隔（秒）
    private let streamingInterval: Double
    private let loader: ModelLoader

    public init(modelRepo: String = MLXInferenceEngine.defaultModelRepo, streamingInterval: Double = 0.32) {
        self.streamingInterval = streamingInterval
        self.loader = ModelLoader(modelRepo: modelRepo)
    }

    /// 预热：提前加载模型（首次会触发权重下载），让首次合成不吃加载延迟。
    public func prepare() async throws {
        _ = try await loader.model()
    }

    public func synthesize(text: String, voice: Voice) -> AsyncThrowingStream<AudioChunk, Error> {
        let loader = loader
        let streamingInterval = streamingInterval
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = try await loader.model()
                    let sampleRate = Double(model.sampleRate)
                    let stream = model.generateStream(
                        text: text,
                        voice: voice.id,
                        refAudio: nil,
                        refText: nil,
                        language: nil,
                        generationParameters: model.defaultGenerationParameters,
                        streamingInterval: streamingInterval
                    )
                    for try await event in stream {
                        try Task.checkCancellation()
                        guard case .audio(let audio) = event else { continue }
                        let samples = Self.monoSamples(audio)
                        guard !samples.isEmpty else { continue }
                        continuation.yield(AudioChunk(samples: samples, sampleRate: sampleRate))
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

    /// MLXArray → 单声道 Float32。生成结果可能是 [N]、[1, N] 或 [1, 1, N]。
    private static func monoSamples(_ audio: MLXArray) -> [Float] {
        var audio = audio.asType(.float32)
        while audio.ndim > 1, audio.dim(0) == 1 {
            audio = audio[0]
        }
        guard audio.ndim == 1 else { return [] }
        return audio.asArray(Float.self)
    }
}

/// 模型只加载一次并复用；用 actor 串行化并发的首次加载。
private actor ModelLoader {
    private let modelRepo: String
    private var loaded: SpeechGenerationModel?

    init(modelRepo: String) {
        self.modelRepo = modelRepo
        // 限制 MLX 缓冲缓存，避免长会话内存膨胀（与上游 CLI 同值）
        Memory.cacheLimit = 256 * 1024 * 1024
    }

    func model() async throws -> SpeechGenerationModel {
        if let loaded { return loaded }
        let model = try await TTS.loadModel(modelRepo: modelRepo)
        loaded = model
        return model
    }
}
