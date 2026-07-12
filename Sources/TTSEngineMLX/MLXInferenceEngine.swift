import Foundation
import HuggingFace
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

    public let modelRepo: String
    private let loader: ModelLoader

    /// - Parameter cacheDirectory: 模型存储根目录；nil 用默认，需与 MLXModelManager 一致
    public init(modelRepo: String = MLXInferenceEngine.defaultModelRepo, cacheDirectory: URL? = nil) {
        self.modelRepo = modelRepo
        self.loader = ModelLoader(modelRepo: modelRepo, cacheDirectory: cacheDirectory)
    }

    /// 预热：提前加载模型（首次会触发权重下载），让首次合成不吃加载延迟。
    public func prepare() async throws {
        _ = try await loader.model()
    }

    /// 卸载模型释放内存；下次合成会重新加载。
    public func unload() async {
        await loader.unload()
    }

    public var isLoaded: Bool {
        get async { await loader.isLoaded }
    }

    public func synthesize(text: String, voice: Voice, options: SynthesisOptions) -> AsyncThrowingStream<AudioChunk, Error> {
        let loader = loader
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = try await loader.model()
                    let sampleRate = Double(model.sampleRate)
                    var parameters = model.defaultGenerationParameters
                    if let temperature = options.temperature { parameters.temperature = temperature }
                    if let topP = options.topP { parameters.topP = topP }

                    // 克隆：参考音频 + 文字稿，音色由参考音频决定（需 Base 变体模型）
                    // 设计：voice 参数即自然语言声音描述（需 VoiceDesign 变体模型）
                    // 预置：CustomVoice 以 "speaker, 指令" 形式携带风格指令
                    let voicePrompt: String?
                    let refAudio: MLXArray?
                    let refText: String?
                    if let clone = options.clone {
                        voicePrompt = nil
                        (_, refAudio) = try loadAudioArray(from: clone.audioURL, sampleRate: model.sampleRate)
                        refText = clone.transcript
                    } else if let design = options.design {
                        voicePrompt = design
                        refAudio = nil
                        refText = nil
                    } else {
                        voicePrompt = options.instruction.map { "\(voice.id), \($0)" } ?? voice.id
                        refAudio = nil
                        refText = nil
                    }

                    let stream = model.generateStream(
                        text: text,
                        voice: voicePrompt,
                        refAudio: refAudio,
                        refText: refText,
                        language: options.language,
                        generationParameters: parameters,
                        streamingInterval: options.streamingInterval ?? 0.32
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
    private let cache: HubCache
    private var loaded: SpeechGenerationModel?

    init(modelRepo: String, cacheDirectory: URL?) {
        self.modelRepo = modelRepo
        self.cache = cacheDirectory.map { HubCache(cacheDirectory: $0) } ?? .default
        // 限制 MLX 缓冲缓存，避免长会话内存膨胀（与上游 CLI 同值）
        Memory.cacheLimit = 256 * 1024 * 1024
    }

    func model() async throws -> SpeechGenerationModel {
        if let loaded { return loaded }
        let model = try await TTS.loadModel(modelRepo: modelRepo, cache: cache)
        loaded = model
        return model
    }

    var isLoaded: Bool { loaded != nil }

    func unload() {
        loaded = nil
    }
}
