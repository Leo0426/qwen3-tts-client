import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import TTSCore
import TTSEngineMLX

/// 当前选中的发声方式：预置音色 / 克隆音色 / 语音设计
enum VoiceSelection: Hashable {
    case preset(String)
    case clone(UUID)
    case design(UUID)
}

/// 引擎槽位：每种发声方式对应一个模型（CustomVoice / Base / VoiceDesign 变体）
enum ModelSlotKind: CaseIterable, Hashable {
    case preset
    case clone
    case design

    var title: String {
        switch self {
        case .preset: return "预置音色模型"
        case .clone: return "克隆音色模型"
        case .design: return "语音设计模型"
        }
    }
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
            ensureActiveSlot()
        }
    }
    /// 风格指令（仅预置音色生效；克隆/设计的风格由参考音频或描述决定）
    var instruction: String = "" {
        didSet { UserDefaults.standard.set(instruction, forKey: "lastInstruction") }
    }
    /// 播放速度（变速不变调），跨会话记住
    var playbackRate: Float = 1.0 {
        didSet {
            player.rate = playbackRate
            UserDefaults.standard.set(Double(playbackRate), forKey: "playbackRate")
        }
    }
    let settings = AppSettings()

    private(set) var isSynthesizing = false
    private(set) var errorMessage: String?
    /// 本次合成的首包延迟（可感知的“开始出声”时间）
    private(set) var firstChunkLatency: TimeInterval?

    let player = StreamingAudioPlayer()
    let history: HistoryStore
    let clonedVoices: ClonedVoiceStore
    let designedVoices: DesignedVoiceStore
    let modelLibrary: ModelLibrary

    // 每个槽位一套 MLX 引擎与下载管理器，按需惰性创建；
    // QWEN3TTS_FAKE_ENGINE=1 时全部走假引擎跑 UI 快速内循环
    private var fakeEngine: (any InferenceEngine)?
    private var mlxEngines: [ModelSlotKind: MLXInferenceEngine] = [:]
    private var managers: [ModelSlotKind: MLXModelManager] = [:]
    private var loadStates: [ModelSlotKind: ModelLoadState] = [:]
    private var synthesisTask: Task<Void, Never>?
    private var isFakeMode: Bool { fakeEngine != nil }
    /// 全局快捷键 ⌃⌥⌘S：朗读剪贴板 / 停止（开关语义）
    private var speakHotKey: GlobalHotKey?

    init(historyDirectory: URL? = nil, voicesDirectory: URL? = nil, designsDirectory: URL? = nil) {
        history = HistoryStore(directory: historyDirectory)
        clonedVoices = ClonedVoiceStore(directory: voicesDirectory)
        designedVoices = DesignedVoiceStore(directory: designsDirectory)
        modelLibrary = ModelLibrary(
            cacheDirectory: settings.resolvedStorageURL,
            downloadHost: settings.resolvedDownloadHost
        )
        if ProcessInfo.processInfo.environment["QWEN3TTS_FAKE_ENGINE"] == "1" {
            fakeEngine = SegmentingEngine(base: FakeInferenceEngine())
        } else {
            ensureSlot(.preset)
        }
        restoreVoiceSelection()
        instruction = UserDefaults.standard.string(forKey: "lastInstruction") ?? ""
        if let savedRate = UserDefaults.standard.object(forKey: "playbackRate") as? Double {
            playbackRate = Float(savedRate)
        }
        ensureActiveSlot()
        warmUpActiveEngineIfReady()
        speakHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        ) { [weak self] in
            Task { @MainActor in
                self?.toggleSpeakClipboard()
            }
        }
    }

    // MARK: - 剪贴板朗读（菜单栏 / 全局快捷键）

    var isSpeaking: Bool {
        isSynthesizing || player.state == .playing
    }

    /// 开关语义：正在出声就停止，否则朗读剪贴板文本
    func toggleSpeakClipboard() {
        if isSpeaking {
            cancelSynthesis()
            player.stop()
            return
        }
        guard let clipboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clipboard.isEmpty else {
            NSSound.beep()
            return
        }
        text = clipboard
        synthesize()
    }

    // MARK: - 音色选择

    var activeSlot: ModelSlotKind {
        switch voiceSelection {
        case .preset: return .preset
        case .clone: return .clone
        case .design: return .design
        }
    }

    var usingClone: Bool { activeSlot == .clone }
    var usingDesign: Bool { activeSlot == .design }

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

    var selectedDesignedVoice: DesignedVoice? {
        guard case .design(let id) = voiceSelection else { return nil }
        return designedVoices.items.first { $0.id == id }
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

    func addDesignedVoice(name: String, prompt: String) {
        let voice = designedVoices.add(name: name, prompt: prompt)
        voiceSelection = .design(voice.id)
    }

    func deleteDesignedVoice(_ voice: DesignedVoice) {
        designedVoices.delete(voice)
        if case .design(let id) = voiceSelection, id == voice.id {
            voiceSelection = .preset(Voice.default.id)
        }
    }

    // MARK: - 槽位与模型就绪

    func repo(for kind: ModelSlotKind) -> String {
        switch kind {
        case .preset: return settings.modelRepo
        case .clone: return settings.baseModelRepo
        case .design: return AppSettings.designModelRepo
        }
    }

    /// 惰性创建槽位的引擎与管理器
    private func ensureSlot(_ kind: ModelSlotKind) {
        guard !isFakeMode, mlxEngines[kind] == nil else { return }
        let repo = repo(for: kind)
        mlxEngines[kind] = MLXInferenceEngine(modelRepo: repo, cacheDirectory: settings.resolvedStorageURL)
        managers[kind] = modelLibrary.manager(for: repo)
        loadStates[kind] = .unloaded
    }

    private func ensureActiveSlot() {
        guard !isFakeMode else { return }
        ensureSlot(activeSlot)
        warmUpActiveEngineIfReady()
    }

    /// 当前发声方式所需的模型管理器（引导页/工具栏面板/设置均随之切换）
    var modelManager: MLXModelManager? {
        managers[activeSlot]
    }

    /// 设置页加载管理用：已创建的槽位
    var activeSlots: [ModelSlotKind] {
        ModelSlotKind.allCases.filter { managers[$0] != nil }
    }

    func slotManager(_ kind: ModelSlotKind) -> MLXModelManager? {
        managers[kind]
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

    /// 设置里切换模型规格后重建全部槽位；未下载时引导页自然出现
    func applyModelSelection() {
        guard !isFakeMode, mlxEngines[.preset]?.modelRepo != settings.modelRepo else { return }
        rebuildEngines()
    }

    /// 设置里改下载源后同步到全部管理器（对下一次下载生效）
    func applyDownloadSource() {
        modelLibrary.setDownloadHost(settings.resolvedDownloadHost)
    }

    /// 更改模型存储路径：管理器与引擎全部重建（不迁移已下载文件）
    func applyStorageDirectory() {
        guard !isFakeMode else { return }
        modelLibrary.setCacheDirectory(settings.resolvedStorageURL)
        rebuildEngines()
    }

    private func rebuildEngines() {
        guard !isFakeMode else { return }
        mlxEngines = [:]
        managers = [:]
        loadStates = [:]
        ensureSlot(.preset)
        ensureActiveSlot()
        warmUpActiveEngineIfReady()
    }

    // MARK: - 加载管理

    /// 当前所需模型就绪后按设置自动预热，首次合成不吃加载延迟
    private func warmUpActiveEngineIfReady() {
        guard settings.autoWarmUp else { return }
        warmUpModel(activeSlot)
    }

    /// 手动/自动把模型加载进内存
    func warmUpModel(_ kind: ModelSlotKind) {
        guard let engine = mlxEngines[kind], managers[kind]?.state == .ready,
              loadState(kind) == .unloaded else { return }
        loadStates[kind] = .loading
        Task { [weak self] in
            do {
                try await engine.prepare()
                self?.loadStates[kind] = .loaded
            } catch {
                self?.loadStates[kind] = .unloaded
                self?.errorMessage = "模型加载失败：\(error.localizedDescription)"
            }
        }
    }

    /// 卸载模型释放内存；下次合成会重新加载
    func unloadModel(_ kind: ModelSlotKind) {
        guard !isSynthesizing, let engine = mlxEngines[kind] else { return }
        Task { [weak self] in
            await engine.unload()
            self?.loadStates[kind] = .unloaded
        }
    }

    func loadState(_ kind: ModelSlotKind) -> ModelLoadState {
        loadStates[kind] ?? .unloaded
    }

    // MARK: - 合成

    var canSynthesize: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isSynthesizing, isModelReady else { return false }
        if usingClone, selectedClonedVoice == nil { return false }
        if usingDesign, selectedDesignedVoice == nil { return false }
        return true
    }

    var hasAudio: Bool {
        !player.samples.isEmpty && !isSynthesizing
    }

    func synthesize() {
        guard canSynthesize else { return }
        let historyVoiceID: String
        switch voiceSelection {
        case .preset: historyVoiceID = selectedPresetVoice.id
        case .clone: historyVoiceID = selectedClonedVoice?.name ?? "克隆音色"
        case .design: historyVoiceID = selectedDesignedVoice?.name ?? "设计音色"
        }
        let options = settings.makeSynthesisOptions(
            instruction: instruction,
            clone: selectedClonedVoice.map { clonedVoices.cloneReference(for: $0) },
            design: selectedDesignedVoice?.prompt
        )
        startSynthesis(
            text: text,
            voice: selectedPresetVoice,
            options: options,
            slot: activeSlot,
            historyVoiceID: historyVoiceID
        )
    }

    /// 试听一段声音描述（语音设计面板用）：固定示例句，不进历史
    static let auditionSampleText = "你好，这就是用这段描述生成的声音。今天天气不错，适合出去走走。"

    func toggleAuditionDesign(prompt: String) {
        if isSpeaking {
            cancelSynthesis()
            player.stop()
            return
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureSlot(.design)
        if !isFakeMode, managers[.design]?.state != .ready {
            errorMessage = "试听需要先下载「语音设计 1.7B」模型（工具栏 ⬇ 打开模型下载中心）"
            return
        }
        let options = settings.makeSynthesisOptions(instruction: "", design: trimmed)
        startSynthesis(
            text: Self.auditionSampleText,
            voice: .default,
            options: options,
            slot: .design,
            historyVoiceID: nil
        )
    }

    /// 合成执行器：正式合成与试听共用同一条链路
    private func startSynthesis(
        text inputText: String,
        voice inputVoice: Voice,
        options: SynthesisOptions,
        slot: ModelSlotKind,
        historyVoiceID: String?
    ) {
        let activeEngine: any InferenceEngine = fakeEngine
            ?? mlxEngines[slot].map { SegmentingEngine(base: $0) }
            ?? SegmentingEngine(base: FakeInferenceEngine())
        errorMessage = nil
        firstChunkLatency = nil
        isSynthesizing = true

        synthesisTask = Task {
            let started = ContinuousClock.now
            do {
                try player.beginStreaming(sampleRate: 24_000)
                for try await chunk in activeEngine.synthesize(text: inputText, voice: inputVoice, options: options) {
                    if firstChunkLatency == nil {
                        firstChunkLatency = started.duration(to: .now).seconds
                        // 合成会隐式加载模型，同步到加载管理状态
                        if !isFakeMode { loadStates[slot] = .loaded }
                    }
                    player.enqueue(chunk)
                }
                player.endStreaming()
                if let historyVoiceID {
                    saveToHistory(text: inputText, voiceID: historyVoiceID)
                }
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
                ?? Voice(id: voiceID, displayName: voiceID, detail: "自定义")
            try history.add(text: text, voice: voice, samples: player.samples, sampleRate: player.sampleRate)
        } catch {
            errorMessage = "历史记录保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 选择持久化

    private func persistVoiceSelection() {
        let value: String
        switch voiceSelection {
        case .preset(let id): value = "preset:\(id)"
        case .clone(let id): value = "clone:\(id.uuidString)"
        case .design(let id): value = "design:\(id.uuidString)"
        }
        UserDefaults.standard.set(value, forKey: "lastVoiceSelection")
    }

    private func restoreVoiceSelection() {
        guard let saved = UserDefaults.standard.string(forKey: "lastVoiceSelection") else { return }
        if saved.hasPrefix("preset:") {
            let id = String(saved.dropFirst("preset:".count))
            if Voice.presets.contains(where: { $0.id == id }) {
                voiceSelection = .preset(id)
            }
        } else if saved.hasPrefix("clone:"),
                  let uuid = UUID(uuidString: String(saved.dropFirst("clone:".count))),
                  clonedVoices.items.contains(where: { $0.id == uuid }) {
            voiceSelection = .clone(uuid)
        } else if saved.hasPrefix("design:"),
                  let uuid = UUID(uuidString: String(saved.dropFirst("design:".count))),
                  designedVoices.items.contains(where: { $0.id == uuid }) {
            voiceSelection = .design(uuid)
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
