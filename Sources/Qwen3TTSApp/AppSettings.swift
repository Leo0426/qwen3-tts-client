import Foundation
import Observation
import TTSCore
import TTSEngineMLX

/// 用户可调选项，UserDefaults 持久化。
/// 每个选项都对应推理侧的真实开关，不做摆设配置。
@MainActor
@Observable
final class AppSettings {
    struct ModelOption: Identifiable, Hashable {
        let repo: String
        let label: String
        let detail: String
        var id: String { repo }
    }

    static let modelOptions: [ModelOption] = [
        ModelOption(
            repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
            label: "0.6B",
            detail: "更快 · 约 1.8 GB"
        ),
        ModelOption(
            repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
            label: "1.7B",
            detail: "音质更好 · 约 2.9 GB"
        ),
    ]

    /// (显示名, 模型期望的英文名)；nil 值表示自动检测
    static let languageOptions: [(display: String, value: String?)] = [
        ("自动检测", nil),
        ("中文", "Chinese"), ("英语", "English"), ("日语", "Japanese"),
        ("韩语", "Korean"), ("德语", "German"), ("法语", "French"),
        ("俄语", "Russian"), ("葡萄牙语", "Portuguese"), ("西班牙语", "Spanish"),
        ("意大利语", "Italian"),
    ]

    static let streamingOptions: [(label: String, value: Double)] = [
        ("低延迟（0.16s 分块）", 0.16),
        ("平衡（0.32s 分块）", 0.32),
        ("平滑（0.64s 分块）", 0.64),
    ]

    var modelRepo: String {
        didSet { defaults.set(modelRepo, forKey: "modelRepo") }
    }
    /// nil = 自动检测
    var language: String? {
        didSet { defaults.set(language, forKey: "language") }
    }
    /// 关闭时全部走模型默认采样参数
    var useCustomSampling: Bool {
        didSet { defaults.set(useCustomSampling, forKey: "useCustomSampling") }
    }
    var temperature: Double {
        didSet { defaults.set(temperature, forKey: "temperature") }
    }
    var topP: Double {
        didSet { defaults.set(topP, forKey: "topP") }
    }
    var streamingInterval: Double {
        didSet { defaults.set(streamingInterval, forKey: "streamingInterval") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRepo = defaults.string(forKey: "modelRepo")
        modelRepo = Self.modelOptions.contains { $0.repo == savedRepo } ? savedRepo! : Self.modelOptions[0].repo
        language = defaults.string(forKey: "language")
        useCustomSampling = defaults.bool(forKey: "useCustomSampling")
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.9
        topP = defaults.object(forKey: "topP") as? Double ?? 1.0
        streamingInterval = defaults.object(forKey: "streamingInterval") as? Double ?? 0.32
    }

    /// 组装传给推理引擎的合成选项
    func makeSynthesisOptions(instruction: String) -> SynthesisOptions {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return SynthesisOptions(
            instruction: trimmed.isEmpty ? nil : trimmed,
            language: language,
            temperature: useCustomSampling ? Float(temperature) : nil,
            topP: useCustomSampling ? Float(topP) : nil,
            streamingInterval: streamingInterval
        )
    }
}
