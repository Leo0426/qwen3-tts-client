import Foundation

/// 一段流式产出的 PCM 音频。单声道 Float32。
public struct AudioChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval {
        Double(samples.count) / sampleRate
    }
}

/// 声音克隆引用：3 秒以上参考音频 + 与之一致的文字稿。
public struct CloneReference: Equatable, Sendable {
    public var audioURL: URL
    public var transcript: String

    public init(audioURL: URL, transcript: String) {
        self.audioURL = audioURL
        self.transcript = transcript
    }
}

/// 合成选项。所有字段 nil 即模型默认值，保证零配置可用。
public struct SynthesisOptions: Equatable, Sendable {
    /// 声音克隆；设置后使用参考音频的音色，预置音色与指令被忽略（需 Base 变体模型）
    public var clone: CloneReference?
    /// 风格指令（如“用温柔的语气慢慢说”）；nil 不加指令
    public var instruction: String?
    /// 语言（模型期望英文名，如 "Chinese"）；nil 自动检测
    public var language: String?
    /// 采样温度；nil 用模型默认（0.9）
    public var temperature: Float?
    /// nucleus 采样 top-p；nil 用模型默认（1.0）
    public var topP: Float?
    /// 流式分块间隔（秒）；nil 用默认 0.32
    public var streamingInterval: Double?

    public static let `default` = SynthesisOptions()

    public init(
        clone: CloneReference? = nil,
        instruction: String? = nil,
        language: String? = nil,
        temperature: Float? = nil,
        topP: Float? = nil,
        streamingInterval: Double? = nil
    ) {
        self.clone = clone
        self.instruction = instruction
        self.language = language
        self.temperature = temperature
        self.topP = topP
        self.streamingInterval = streamingInterval
    }
}

/// 全 App 最核心的契约：给文本、音色和选项，返回音频块流。
/// 运行时（MLX / CoreML / Fake）的全部细节都必须藏在这个接口后面。
/// 取消消费方的 Task 必须终止流并释放推理资源。
public protocol InferenceEngine: Sendable {
    func synthesize(text: String, voice: Voice, options: SynthesisOptions) -> AsyncThrowingStream<AudioChunk, Error>
}

public extension InferenceEngine {
    func synthesize(text: String, voice: Voice) -> AsyncThrowingStream<AudioChunk, Error> {
        synthesize(text: text, voice: voice, options: .default)
    }
}

public enum InferenceError: LocalizedError {
    case modelNotReady
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return String(localized: "模型尚未就绪，请先在设置中下载模型。")
        case .generationFailed(let reason):
            return String(localized: "合成失败：\(reason)")
        }
    }
}
