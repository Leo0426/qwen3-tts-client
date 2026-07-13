import AppKit
import SwiftUI

@main
struct Qwen3TTSApp: App {
    @State private var model = AppModel()

    init() {
        // `swift run` 直接运行（无 .app bundle）时也要能弹出窗口并获得焦点
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Qwen3 TTS", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 860, height: 540)

        MenuBarExtra("Qwen3 TTS", systemImage: "waveform") {
            MenuBarContent(model: model)
        }

        Window("模型下载", id: "model-downloads") {
            ModelDownloadView(model: model, settings: model.settings)
                .onChange(of: model.settings.downloadSource) {
                    model.applyDownloadSource()
                }
                .onChange(of: model.settings.customEndpoint) {
                    model.applyDownloadSource()
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model, settings: model.settings)
                .onChange(of: model.settings.modelRepo) {
                    model.applyModelSelection()
                }
                .onChange(of: model.settings.downloadSource) {
                    model.applyDownloadSource()
                }
                .onChange(of: model.settings.customEndpoint) {
                    model.applyDownloadSource()
                }
                .onChange(of: model.settings.speakShortcutID) {
                    model.applySpeakShortcut()
                }
        }
    }
}
