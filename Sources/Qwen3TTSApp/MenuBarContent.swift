import SwiftUI

/// 菜单栏常驻入口：主窗口关闭后合成能力依然随手可用。
struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.isSpeaking ? "停止朗读" : "朗读剪贴板") {
            model.toggleSpeakClipboard()
        }
        Text("全局快捷键：⌃⌥⌘S")
        Divider()
        Button("打开 Qwen3 TTS") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        SettingsLink {
            Text("设置…")
        }
        Divider()
        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
    }
}
