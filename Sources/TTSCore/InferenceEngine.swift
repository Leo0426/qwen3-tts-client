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

/// 全 App 最核心的契约：给文本和音色，返回音频块流。
/// 运行时（MLX / CoreML / Fake）的全部细节都必须藏在这个接口后面。
/// 取消消费方的 Task 必须终止流并释放推理资源。
public protocol InferenceEngine: Sendable {
    func synthesize(text: String, voice: Voice) -> AsyncThrowingStream<AudioChunk, Error>
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
