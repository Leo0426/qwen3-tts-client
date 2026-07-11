import AppKit
import Foundation
import Observation
import TTSCore
import TTSEngineMLX

/// 当前选中的发声方式：预置音色或克隆音色
enum VoiceSelection: Hashable {
    case preset(String)
    case clone(UUID)
}

/// 模型在内存中的加载状态（加载管理用）
enum ModelLoadState: Equatable {
    case unloaded
    case loading
    case loaded

    var label: String {
        switch self {
        case .unloaded: return "未加载"
        case .loading: return "加载中…"
        case .loaded: return "已加载（约 2 GB 内存）"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var text: String = ""
    var voiceSelection: VoiceSelection = .preset(Voice.default.id) {
        didSet {
            persistVoiceSelection()
            ensureCloneInfrastructureIfNeeded()
        }
    }
    /// 风格指令（仅预置音色生效；克隆音色的风格由参考音频决定）
    var instruction: String = "" {
        didSet { UserDefaults.standard.set(instruction, forKey: "lastInstruction") }
    }
    let settings = AppSettings()

    private(set) var isSynthesizing = false
    private(set) var errorMessage: String?
    /// 本次合成的首包延迟（可感知的“开始出声”时间）
    private(set) var firstChunkLatency: TimeInterval?

    let player = StreamingAudioPlayer()
    let history: HistoryStore
    let clonedVoices: ClonedVoiceStore

    // 预置音色走 CustomVoice 模型，克隆走 Base 模型（带 speaker encoder），
    // 各自有独立的引擎与下载管理；QWEN3TTS_FAKE_ENGINE=1 时用假引擎跑 UI 快速内循环
    private var presetEngine: any InferenceEngine
    private var presetMLXEngine: MLXInferenceEngine?
    private var presetManager: MLXModelManager?
    private var cloneEngine: MLXInferenceEngine?
    private var cloneManager: MLXModelManager?
    private var synthesisTask: Task<Void, Never>?
    private var isFakeMode: Bool { presetMLXEngine == nil }

    private(set) var presetLoadState: ModelLoadState = .unloaded
    private(set) var cloneLoadState: ModelLoadState = .unloaded

    /// 设置页加载管理用的只读访问
    var presetModelManager: MLXModelManager? { presetManager }
    var cloneModelManager: MLXModelManager? { cloneManager }

    init(historyDirectory: URL? = nil, voicesDirectory: URL? = nil) {
        history = HistoryStore(directory: historyDirectory)
        clonedVoices = ClonedVoiceStore(directory: voicesDirectory)
        if ProcessInfo.processInfo.environment["QWEN3TTS_FAKE_ENGINE"] == "1" {
            presetEngine = FakeInferenceEngine()
            presetMLXEngine = nil
            presetManager = nil
        } else {
            let mlx = MLXInferenceEngine(modelRepo: settings.modelRepo)
            presetEngine = mlx
            presetMLXEngine = mlx
            presetManager = MLXModelManager(modelRepo: settings.modelRepo)
            presetManager?.downloadHost = settings.resolvedDownloadHost
            presetManager?.refresh()
        }
        restoreVoiceSelection()
        instruction = UserDefaults.standard.string(forKey: "lastInstruction") ?? ""
        ensureCloneInfrastructureIfNeeded()
        warmUpActiveEngineIfReady()
    }

    // MARK: - 音色选择

    var usingClone: Bool {
        if case .clone = voiceSelection { return true }
        return false
    }

    var selectedPresetVoice: Voice {
        if case .preset(let id) = voiceSelection,
           let preset = Voice.presets.first(where: { $0.id == id }) {
            return preset
        }
        return .default
    }

    var selectedClonedVoice: ClonedVoice? {
        guard case .clone(let id) = voiceSelection else { return nil }
        return clonedVoices.items.first { $0.id == id }
    }

    var currentVoiceDisplayName: String {
        usingClone ? (selectedClonedVoice?.name ?? "克隆音色") : selectedPresetVoice.displayName
    }

    func addClonedVoice(name: String, transcript: String, sourceAudioURL: URL) {
        do {
            let voice = try clonedVoices.add(name: name, transcript: transcript, sourceAudioURL: sourceAudioURL)
            voiceSelection = .clone(voice.id)
        } catch {
            errorMessage = "克隆音色保存失败：\(error.localizedDescription)"
        }
    }

    func deleteClonedVoice(_ voice: ClonedVoice) {
        clonedVoices.delete(voice)
        if case .clone(let id) = voiceSelection, id == voice.id {
            voiceSelection = .preset(Voice.default.id)
        }
    }

    // MARK: - 模型就绪（当前选择对应的模型）

    /// 当前发声方式所需的模型管理器（引导页/工具栏面板/设置均随之切换）
    var modelManager: MLXModelManager? {
        usingClone ? cloneManager : presetManager
    }

    var isModelReady: Bool {
        if isFakeMode { return true }
        return modelManager?.state == .ready
    }

    func downloadModel() {
        guard let manager = modelManager else { return }
        Task {
            await manager.download()
            warmUpActiveEngineIfReady()
        }
    }

    /// 设置里切换模型规格后重建两套引擎与管理器；未下载时引导页自然出现
    func applyModelSelection() {
        guard let current = presetMLXEngine, current.modelRepo != settings.modelRepo else { return }
        let mlx = MLXInferenceEngine(modelRepo: settings.modelRepo)
        presetEngine = mlx
        presetMLXEngine = mlx
        presetLoadState = .unloaded
        presetManager = MLXModelManager(modelRepo: settings.modelRepo)
        presetManager?.downloadHost = settings.resolvedDownloadHost
        presetManager?.refresh()
        cloneEngine = nil
        cloneManager = nil
        cloneLoadState = .unloaded
        ensureCloneInfrastructureIfNeeded()
        warmUpActiveEngineIfReady()
    }

    /// 设置里改下载源后同步到两个管理器（对下一次下载生效）
    func applyDownloadSource() {
        presetManager?.downloadHost = settings.resolvedDownloadHost
        cloneManager?.downloadHost = settings.resolvedDownloadHost
    }

    /// 首次选中克隆音色时，惰性创建 Base 模型的引擎与管理器
    private func ensureCloneInfrastructureIfNeeded() {
        guard usingClone, !isFakeMode, cloneManager == nil else { return }
        cloneEngine = MLXInferenceEngine(modelRepo: settings.baseModelRepo)
        cloneLoadState = .unloaded
        cloneManager = MLXModelManager(modelRepo: settings.baseModelRepo)
        cloneManager?.downloadHost = settings.resolvedDownloadHost
        cloneManager?.refresh()
        warmUpActiveEngineIfReady()
    }

    // MARK: - 加载管理

    /// 当前所需模型就绪后按设置自动预热，首次合成不吃加载延迟
    private func warmUpActiveEngineIfReady() {
        guard settings.autoWarmUp else { return }
        warmUpModel(clone: usingClone)
    }

    /// 手动/自动把模型加载进内存
    func warmUpModel(clone: Bool) {
        guard !isFakeMode else { return }
        let engine = clone ? cloneEngine : presetMLXEngine
        let manager = clone ? cloneManager : presetManager
        guard let engine, manager?.state == .ready,
              loadState(clone: clone) == .unloaded else { return }
        setLoadState(clone: clone, .loading)
        Task { [weak self] in
            do {
                try await engine.prepare()
                self?.setLoadState(clone: clone, .loaded)
            } catch {
                self?.setLoadState(clone: clone, .unloaded)
                self?.errorMessage = "模型加载失败：\(error.localizedDescription)"
            }
        }
    }

    /// 卸载模型释放内存；下次合成会重新加载
    func unloadModel(clone: Bool) {
        guard !isSynthesizing, let engine = clone ? cloneEngine : presetMLXEngine else { return }
        Task { [weak self] in
            await engine.unload()
            self?.setLoadState(clone: clone, .unloaded)
        }
    }

    func loadState(clone: Bool) -> ModelLoadState {
        clone ? cloneLoadState : presetLoadState
    }

    private func setLoadState(clone: Bool, _ state: ModelLoadState) {
        if clone {
            cloneLoadState = state
        } else {
            presetLoadState = state
        }
    }

    // MARK: - 合成

    var canSynthesize: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSynthesizing, isModelReady else { return false }
        if usingClone, selectedClonedVoice == nil { return false }
        return true
    }

    var hasAudio: Bool {
        !player.samples.isEmpty && !isSynthesizing
    }

    func synthesize() {
        guard canSynthesize else { return }
        let inputText = text
        let inputVoice = selectedPresetVoice
        let clone = selectedClonedVoice.map { clonedVoices.cloneReference(for: $0) }
        let historyVoiceID = usingClone ? (selectedClonedVoice?.name ?? "克隆音色") : inputVoice.id
        let activeEngine: any InferenceEngine = usingClone ? (cloneEngine ?? presetEngine) : presetEngine
        let activeIsClone = usingClone
        errorMessage = nil
        firstChunkLatency = nil
        isSynthesizing = true

        let options = settings.makeSynthesisOptions(instruction: instruction, clone: clone)
        synthesisTask = Task {
            let started = ContinuousClock.now
            do {
                try player.beginStreaming(sampleRate: 24_000)
                for try await chunk in activeEngine.synthesize(text: inputText, voice: inputVoice, options: options) {
                    if firstChunkLatency == nil {
                        firstChunkLatency = started.duration(to: .now).seconds
                        // 合成会隐式加载模型，同步到加载管理状态
                        if !isFakeMode { setLoadState(clone: activeIsClone, .loaded) }
                    }
                    player.enqueue(chunk)
                }
                player.endStreaming()
                saveToHistory(text: inputText, voiceID: historyVoiceID)
            } catch is CancellationError {
                player.endStreaming()
            } catch {
                player.stop()
                errorMessage = error.localizedDescription
            }
            isSynthesizing = false
        }
    }

    func cancelSynthesis() {
        synthesisTask?.cancel()
        synthesisTask = nil
    }

    // MARK: - 播放与历史

    func replay(_ item: StoredHistoryItem? = nil) {
        do {
            if let item {
                let (samples, sampleRate) = try history.samples(for: item)
                try player.beginStreaming(sampleRate: sampleRate)
                player.enqueue(AudioChunk(samples: samples, sampleRate: sampleRate))
                player.endStreaming()
                text = item.text
                if Voice.presets.contains(where: { $0.id == item.voiceID }) {
                    voiceSelection = .preset(item.voiceID)
                }
            } else {
                try player.replay()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteHistory(_ item: StoredHistoryItem) {
        history.delete(item)
    }

    // MARK: - 导出

    /// 导出当前播放器里的音频
    func exportCurrentAudio() {
        guard !player.samples.isEmpty, let url = askSaveDestination() else { return }
        do {
            try WavFile.write(samples: player.samples, sampleRate: player.sampleRate, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 导出历史条目（直接拷贝缓存文件）
    func exportHistory(_ item: StoredHistoryItem) {
        guard let url = askSaveDestination() else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: history.audioURL(for: item), to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askSaveDestination() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "qwen3-tts-\(Self.fileTimestamp()).wav"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func saveToHistory(text: String, voiceID: String) {
        guard !player.samples.isEmpty else { return }
        do {
            let voice = Voice.presets.first { $0.id == voiceID }
                ?? Voice(id: voiceID, displayName: voiceID, detail: "克隆")
            try history.add(text: text, voice: voice, samples: player.samples, sampleRate: player.sampleRate)
        } catch {
            errorMessage = "历史记录保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 选择持久化

    private func persistVoiceSelection() {
        switch voiceSelection {
        case .preset(let id):
            UserDefaults.standard.set("preset:\(id)", forKey: "lastVoiceSelection")
        case .clone(let id):
            UserDefaults.standard.set("clone:\(id.uuidString)", forKey: "lastVoiceSelection")
        }
    }

    private func restoreVoiceSelection() {
        guard let saved = UserDefaults.standard.string(forKey: "lastVoiceSelection") else {
            // 兼容旧版存储
            if let oldID = UserDefaults.standard.string(forKey: "lastVoiceID"),
               Voice.presets.contains(where: { $0.id == oldID }) {
                voiceSelection = .preset(oldID)
            }
            return
        }
        if saved.hasPrefix("preset:") {
            let id = String(saved.dropFirst("preset:".count))
            if Voice.presets.contains(where: { $0.id == id }) {
                voiceSelection = .preset(id)
            }
        } else if saved.hasPrefix("clone:"),
                  let uuid = UUID(uuidString: String(saved.dropFirst("clone:".count))),
                  clonedVoices.items.contains(where: { $0.id == uuid }) {
            voiceSelection = .clone(uuid)
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

extension Duration {
    var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
