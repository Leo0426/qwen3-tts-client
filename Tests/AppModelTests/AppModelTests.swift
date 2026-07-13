import Foundation
import Testing
import TTSCore
@testable import Qwen3TTSApp

/// AppModel 状态机测试：全程 FakeInferenceEngine，隔离的 UserDefaults 与临时目录。
@MainActor
struct AppModelTests {
    private func makeModel() -> (model: AppModel, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suiteName = "AppModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // 测试进程不注册全局快捷键，避免与正在运行的 App 冲突
        defaults.set("none", forKey: "speakShortcutID")
        let model = AppModel(
            historyDirectory: dir.appendingPathComponent("history"),
            voicesDirectory: dir.appendingPathComponent("voices"),
            designsDirectory: dir.appendingPathComponent("designs"),
            settings: AppSettings(defaults: defaults),
            defaults: defaults,
            forceFakeEngine: true
        )
        return (model, {
            model.player.stop()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        })
    }

    /// 轮询等待合成结束（假引擎 1 秒起步，2× 实时产出）
    private func waitUntilIdle(_ model: AppModel, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.isSynthesizing {
            try await Task.sleep(for: .milliseconds(50))
            #expect(Date() < deadline, "合成超时未结束")
            if Date() >= deadline { return }
        }
    }

    @Test func synthesizeRunsStateMachineAndSavesHistory() async throws {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        model.text = "你好"

        #expect(model.canSynthesize)
        model.synthesize()
        #expect(model.isSynthesizing)
        #expect(!model.canSynthesize) // 合成中不可重入

        try await waitUntilIdle(model)
        #expect(model.errorMessage == nil)
        #expect(model.firstChunkLatency != nil)
        #expect(!model.player.samples.isEmpty)
        #expect(model.history.items.count == 1)
        #expect(model.history.items.first?.text == "你好")
    }

    @Test func emptyTextCannotSynthesize() {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        model.text = "   "
        #expect(!model.canSynthesize)
    }

    @Test func cancelStopsSynthesis() async throws {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        model.text = String(repeating: "长文本测试。", count: 40)
        model.synthesize()
        #expect(model.isSynthesizing)

        model.cancelSynthesis()
        try await waitUntilIdle(model)
        // 取消不算错误
        #expect(model.errorMessage == nil)
        // 取消的合成不进历史
        #expect(model.history.items.isEmpty)
    }

    @Test func auditionTogglesSpeakingWithoutHistory() async throws {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        model.toggleAuditionDesign(prompt: "低沉磁性的男声")
        #expect(model.isSynthesizing)

        try await waitUntilIdle(model)
        #expect(model.errorMessage == nil)
        // 试听不进历史
        #expect(model.history.items.isEmpty)

        // 出声期间再次 toggle = 停止
        if model.isSpeaking {
            model.toggleAuditionDesign(prompt: "低沉磁性的男声")
            #expect(!model.isSpeaking)
        }
    }

    @Test func failedCloneReportsErrorAndClearErrorResets() {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        // 源文件不存在 → 保存失败 → 错误提示
        model.addClonedVoice(
            name: "坏音色",
            transcript: "文稿",
            sourceAudioURL: URL(fileURLWithPath: "/nonexistent/audio.wav")
        )
        #expect(model.errorMessage != nil)

        model.clearError()
        #expect(model.errorMessage == nil)
        #expect(!model.errorNeedsDownloadCenter)
    }

    @Test func newSynthesisClearsPreviousError() async throws {
        let (model, cleanup) = makeModel()
        defer { cleanup() }
        model.addClonedVoice(
            name: "坏音色",
            transcript: "文稿",
            sourceAudioURL: URL(fileURLWithPath: "/nonexistent/audio.wav")
        )
        #expect(model.errorMessage != nil)

        model.text = "你好"
        model.synthesize()
        #expect(model.errorMessage == nil) // 开始合成即清除旧错误
        try await waitUntilIdle(model)
    }

    @Test func voiceSelectionPersistsAcrossInstances() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-persist-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "AppModelTests-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("none", forKey: "speakShortcutID")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }
        func make() -> AppModel {
            AppModel(
                historyDirectory: dir.appendingPathComponent("history"),
                voicesDirectory: dir.appendingPathComponent("voices"),
                designsDirectory: dir.appendingPathComponent("designs"),
                settings: AppSettings(defaults: defaults),
                defaults: defaults,
                forceFakeEngine: true
            )
        }

        let first = make()
        let target = Voice.presets[2].id
        first.voiceSelection = .preset(target)

        let second = make()
        #expect(second.voiceSelection == .preset(target))
    }
}
