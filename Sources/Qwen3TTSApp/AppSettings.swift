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

    enum DownloadSource: String, CaseIterable {
        case official
        case mirror
        case custom

        var label: String {
            switch self {
            case .official: return "官方 huggingface.co"
            case .mirror: return "镜像 hf-mirror.com"
            case .custom: return "自定义…"
            }
        }
    }

    var modelRepo: String {
        didSet { defaults.set(modelRepo, forKey: "modelRepo") }
    }
    var downloadSource: DownloadSource {
        didSet { defaults.set(downloadSource.rawValue, forKey: "downloadSource") }
    }
    var customEndpoint: String {
        didSet { defaults.set(customEndpoint, forKey: "customEndpoint") }
    }
    /// 启动或模型就绪后是否自动把模型加载进内存
    var autoWarmUp: Bool {
        didSet { defaults.set(autoWarmUp, forKey: "autoWarmUp") }
    }
    /// 模型存储根目录；空 = 默认（~/.cache/huggingface/hub）
    var modelStoragePath: String {
        didSet { defaults.set(modelStoragePath, forKey: "modelStoragePath") }
    }

    /// nil = 默认目录
    var resolvedStorageURL: URL? {
        let trimmed = modelStoragePath.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    /// 当前生效的下载地址；自定义地址无效时回落官方源
    var resolvedDownloadHost: URL {
        switch downloadSource {
        case .official: return URL(string: "https://huggingface.co")!
        case .mirror: return URL(string: "https://hf-mirror.com")!
        case .custom:
            let trimmed = customEndpoint.trimmingCharacters(in: .whitespaces)
            if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
                return url
            }
            return URL(string: "https://huggingface.co")!
        }
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
        downloadSource = DownloadSource(rawValue: defaults.string(forKey: "downloadSource") ?? "") ?? .official
        customEndpoint = defaults.string(forKey: "customEndpoint") ?? ""
        autoWarmUp = defaults.object(forKey: "autoWarmUp") as? Bool ?? true
        modelStoragePath = defaults.string(forKey: "modelStoragePath") ?? ""
        useCustomSampling = defaults.bool(forKey: "useCustomSampling")
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.9
        topP = defaults.object(forKey: "topP") as? Double ?? 1.0
        streamingInterval = defaults.object(forKey: "streamingInterval") as? Double ?? 0.32
    }

    /// 声音克隆使用同规格的 Base 变体模型（带 speaker encoder）
    var baseModelRepo: String {
        modelRepo.replacingOccurrences(of: "CustomVoice", with: "Base")
    }

    /// 语音设计模型（官方仅提供 1.7B 变体，与规格选择无关）
    static let designModelRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"

    /// 组装传给推理引擎的合成选项；clone/design 非空时指令被忽略
    func makeSynthesisOptions(instruction: String, clone: CloneReference? = nil, design: String? = nil) -> SynthesisOptions {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return SynthesisOptions(
            clone: clone,
            design: design,
            instruction: clone == nil && design == nil && !trimmed.isEmpty ? trimmed : nil,
            language: language,
            temperature: useCustomSampling ? Float(temperature) : nil,
            topP: useCustomSampling ? Float(topP) : nil,
            streamingInterval: streamingInterval
        )
    }
}
