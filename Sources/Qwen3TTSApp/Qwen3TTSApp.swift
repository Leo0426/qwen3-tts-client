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
        WindowGroup("Qwen3 TTS") {
            MainView(model: model)
        }
        .defaultSize(width: 860, height: 540)
    }
}
