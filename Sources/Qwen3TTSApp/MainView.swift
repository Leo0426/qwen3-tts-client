import SwiftUI
import TTSCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showHistory = true
    @State private var showModelInfo = false

    var body: some View {
        HSplitView {
            editorPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            if showHistory {
                HistoryPanel(model: model)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .overlay {
            if let manager = model.modelManager {
                ModelSetupOverlay(manager: manager) {
                    model.downloadModel()
                }
            }
        }
        .toolbar {
            if let manager = model.modelManager {
                ToolbarItem {
                    Button {
                        showModelInfo.toggle()
                    } label: {
                        Label("模型", systemImage: "cpu")
                    }
                    .help("本地模型状态与管理")
                    .popover(isPresented: $showModelInfo, arrowEdge: .bottom) {
                        ModelInfoPopover(manager: manager)
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showHistory.toggle() }
                } label: {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                }
                .help("显示或隐藏历史记录")
            }
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            textEditor
            Divider()
            controlBar
        }
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.text)
                .font(.system(size: 15))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(12)
            if model.text.isEmpty {
                Text("输入要合成的文本…")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 12)
                    .padding(.leading, 17)
                    .allowsHitTesting(false)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                voicePicker
                Spacer()
                statusText
                synthesizeButton
            }
            if model.hasAudio || model.isSynthesizing {
                PlaybackBar(model: model)
            }
            if let errorMessage = model.errorMessage {
                HStack {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var voicePicker: some View {
        Picker(selection: $model.voice) {
            ForEach(Voice.presets) { voice in
                Text("\(voice.displayName) — \(voice.detail)").tag(voice)
            }
        } label: {
            Label("音色", systemImage: "person.wave.2")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(model.isSynthesizing)
    }

    private var statusText: some View {
        Group {
            if model.isSynthesizing {
                if let latency = model.firstChunkLatency {
                    Text("生成中 · 首包 \(String(format: "%.2f", latency))s")
                } else {
                    Text("准备中…")
                }
            } else if !model.text.isEmpty {
                Text("\(model.text.count) 字")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var synthesizeButton: some View {
        Group {
            if model.isSynthesizing {
                Button(role: .cancel) {
                    model.cancelSynthesis()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(minWidth: 64)
                }
            } else {
                Button {
                    model.synthesize()
                } label: {
                    Label("合成", systemImage: "waveform")
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSynthesize)
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .help("⌘⏎ 合成并播放")
    }
}

/// 播放控制条：进度 + 播放/暂停/重播/导出
struct PlaybackBar: View {
    @Bindable var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 12) {
                playPauseButton
                Button {
                    model.replay()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("重播")
                .disabled(model.player.samples.isEmpty)

                progressView

                Button {
                    model.exportCurrentAudio()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("导出 WAV")
                .disabled(!model.hasAudio)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
    }

    private var playPauseButton: some View {
        Button {
            switch model.player.state {
            case .playing: model.player.pause()
            case .paused: model.player.resume()
            case .finished, .idle: model.replay()
            }
        } label: {
            Image(systemName: model.player.state == .playing ? "pause.fill" : "play.fill")
        }
        .help(model.player.state == .playing ? "暂停" : "播放")
        .disabled(model.player.samples.isEmpty)
    }

    private var progressView: some View {
        let buffered = model.player.bufferedDuration
        let played = min(model.player.playbackTime, buffered)
        return HStack(spacing: 8) {
            Text(Self.format(played))
            ProgressView(value: buffered > 0 ? played / buffered : 0)
                .progressViewStyle(.linear)
            Text(Self.format(buffered) + (model.isSynthesizing ? "+" : ""))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private static func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
