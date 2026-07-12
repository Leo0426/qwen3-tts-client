import SwiftUI
import TTSCore

struct MainView: View {
    @Bindable var model: AppModel
    @State private var showHistory = true
    @State private var showModelInfo = false
    @State private var showCloneSheet = false
    @State private var showDesignSheet = false
    @Environment(\.openWindow) private var openWindow

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
                ToolbarItem {
                    Button {
                        openWindow(id: "model-downloads")
                    } label: {
                        Label("模型下载", systemImage: "arrow.down.circle")
                    }
                    .help("模型下载中心：下载、删除、存储位置")
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
                .font(.system(size: 16))
                .lineSpacing(7)
                .scrollContentBackground(.hidden)
                .padding(20)
            if model.text.isEmpty {
                Text("输入要合成的文本…")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
                    .padding(.leading, 25)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.text.isEmpty {
                Text("\(model.text.count) 字")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            TextField(instructionPlaceholder, text: $model.instruction)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
                .disabled(model.isSynthesizing || model.usingClone || model.usingDesign)
            HStack(spacing: 12) {
                voicePicker
                cloneButton
                designButton
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
        Picker(selection: $model.voiceSelection) {
            Section("预置音色") {
                ForEach(Voice.presets) { voice in
                    Text("\(voice.displayName) — \(voice.detail)").tag(VoiceSelection.preset(voice.id))
                }
            }
            if !model.clonedVoices.items.isEmpty {
                Section("克隆音色") {
                    ForEach(model.clonedVoices.items) { voice in
                        Text("\(voice.name) — 克隆").tag(VoiceSelection.clone(voice.id))
                    }
                }
            }
            if !model.designedVoices.items.isEmpty {
                Section("语音设计") {
                    ForEach(model.designedVoices.items) { voice in
                        Text("\(voice.name) — 设计").tag(VoiceSelection.design(voice.id))
                    }
                }
            }
        } label: {
            Label("音色", systemImage: "person.wave.2")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(model.isSynthesizing)
    }

    private var instructionPlaceholder: String {
        if model.usingClone { return "克隆音色的风格由参考音频决定，指令不生效" }
        if model.usingDesign { return "设计音色的风格由声音描述决定，指令不生效" }
        return "风格指令（可选），如：用温柔的语气慢慢说"
    }

    private var cloneButton: some View {
        Button {
            showCloneSheet = true
        } label: {
            Image(systemName: "person.badge.plus")
        }
        .help("克隆音色：用一段参考音频复刻声音")
        .disabled(model.isSynthesizing)
        .sheet(isPresented: $showCloneSheet) {
            CloneVoiceSheet(model: model)
        }
    }

    private var designButton: some View {
        Button {
            showDesignSheet = true
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .help("语音设计：用自然语言描述凭空造声音")
        .disabled(model.isSynthesizing)
        .sheet(isPresented: $showDesignSheet) {
            DesignVoiceSheet(model: model)
        }
    }

    private var statusText: some View {
        Group {
            if model.isSynthesizing {
                if let latency = model.firstChunkLatency {
                    Text("生成中 · 首包 \(String(format: "%.2f", latency))s")
                } else {
                    Text("准备中…")
                }
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
    /// 拖动波形时的预览进度；松手才真正 seek
    @State private var scrubFraction: Double?

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

                rateMenu

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

    private static let rateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    private var rateMenu: some View {
        Menu {
            ForEach(Self.rateOptions, id: \.self) { rate in
                Button {
                    model.playbackRate = rate
                } label: {
                    if model.playbackRate == rate {
                        Label(Self.formatRate(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.formatRate(rate))
                    }
                }
            }
        } label: {
            Text(Self.formatRate(model.playbackRate))
                .font(.caption)
                .monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("播放速度（变速不变调）")
    }

    private static func formatRate(_ rate: Float) -> String {
        rate == rate.rounded() ? String(format: "%.0f×", rate) : String(format: "%.2g×", rate)
    }

    private var progressView: some View {
        let buffered = model.player.bufferedDuration
        let played = min(model.player.playbackTime, buffered)
        let liveFraction = buffered > 0 ? played / buffered : 0
        let shownFraction = scrubFraction ?? liveFraction
        return HStack(spacing: 10) {
            Text(Self.format(scrubFraction.map { $0 * buffered } ?? played))
            GeometryReader { geometry in
                WaveformView(samples: model.player.samples, progress: shownFraction)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubFraction = min(max(0, value.location.x / geometry.size.width), 1)
                            }
                            .onEnded { value in
                                let fraction = min(max(0, value.location.x / geometry.size.width), 1)
                                scrubFraction = nil
                                model.player.seek(to: fraction * model.player.bufferedDuration)
                            }
                    )
            }
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .help("点按或拖动跳转")
            Text(Self.format(buffered) + (model.isSynthesizing ? "+" : ""))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private static func format(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
