import AppKit
import Foundation
import Observation
import TTSCore
import TTSEngineMLX

@MainActor
@Observable
final class AppModel {
    var text: String = ""
    var voice: Voice = Voice.default {
        didSet { UserDefaults.standard.set(voice.id, forKey: "lastVoiceID") }
    }

    private(set) var isSynthesizing = false
    private(set) var errorMessage: String?
    /// 本次合成的首包延迟（可感知的“开始出声”时间）
    private(set) var firstChunkLatency: TimeInterval?

    let player = StreamingAudioPlayer()
    let history: HistoryStore
    /// 首次启动模型下载引导；假引擎模式下为 nil（视为就绪）
    let modelManager: MLXModelManager?

    // MLX 引擎为默认（ADR-0001）；QWEN3TTS_FAKE_ENGINE=1 时用假引擎跑 UI 快速内循环
    private let engine: any InferenceEngine
    private let mlxEngine: MLXInferenceEngine?
    private var synthesisTask: Task<Void, Never>?

    init(historyDirectory: URL? = nil) {
        history = HistoryStore(directory: historyDirectory)
        if ProcessInfo.processInfo.environment["QWEN3TTS_FAKE_ENGINE"] == "1" {
            engine = FakeInferenceEngine()
            mlxEngine = nil
            modelManager = nil
        } else {
            let mlx = MLXInferenceEngine()
            engine = mlx
            mlxEngine = mlx
            modelManager = MLXModelManager()
            modelManager?.refresh()
            warmUpIfReady()
        }
        if let savedVoiceID = UserDefaults.standard.string(forKey: "lastVoiceID"),
           let savedVoice = Voice.presets.first(where: { $0.id == savedVoiceID }) {
            voice = savedVoice
        }
    }

    // MARK: - 模型就绪

    var isModelReady: Bool {
        modelManager.map { $0.state == .ready } ?? true
    }

    func downloadModel() {
        guard let modelManager else { return }
        Task {
            await modelManager.download()
            warmUpIfReady()
        }
    }

    /// 模型就绪后后台预热，首次合成不吃加载延迟
    private func warmUpIfReady() {
        guard let mlxEngine, isModelReady else { return }
        Task.detached(priority: .utility) {
            try? await mlxEngine.prepare()
        }
    }

    // MARK: - 合成

    var canSynthesize: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSynthesizing && isModelReady
    }

    var hasAudio: Bool {
        !player.samples.isEmpty && !isSynthesizing
    }

    func synthesize() {
        guard canSynthesize else { return }
        let inputText = text
        let inputVoice = voice
        errorMessage = nil
        firstChunkLatency = nil
        isSynthesizing = true

        synthesisTask = Task {
            let started = ContinuousClock.now
            do {
                try player.beginStreaming(sampleRate: 24_000)
                for try await chunk in engine.synthesize(text: inputText, voice: inputVoice) {
                    if firstChunkLatency == nil {
                        firstChunkLatency = started.duration(to: .now).seconds
                    }
                    player.enqueue(chunk)
                }
                player.endStreaming()
                saveToHistory(text: inputText, voice: inputVoice)
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
                if let itemVoice = Voice.presets.first(where: { $0.id == item.voiceID }) {
                    voice = itemVoice
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

    private func saveToHistory(text: String, voice: Voice) {
        guard !player.samples.isEmpty else { return }
        do {
            try history.add(text: text, voice: voice, samples: player.samples, sampleRate: player.sampleRate)
        } catch {
            errorMessage = "历史记录保存失败：\(error.localizedDescription)"
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
