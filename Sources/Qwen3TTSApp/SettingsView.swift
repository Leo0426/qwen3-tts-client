import SwiftUI
import TTSEngineMLX

/// 标准设置窗口（⌘,）
struct SettingsView: View {
    let model: AppModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            modelSection
            languageSection
            samplingSection
            streamingSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var modelSection: some View {
        Section("模型") {
            Picker("模型规格", selection: $settings.modelRepo) {
                ForEach(AppSettings.modelOptions) { option in
                    Text("\(option.label) — \(option.detail)").tag(option.repo)
                }
            }
            if let manager = model.modelManager, manager.state != .ready {
                Label("该模型尚未下载，主窗口将显示下载引导", systemImage: "arrow.down.circle.dotted")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var languageSection: some View {
        Section("语言") {
            Picker("合成语言", selection: $settings.language) {
                ForEach(AppSettings.languageOptions, id: \.display) { option in
                    Text(option.display).tag(option.value)
                }
            }
            Text("自动检测适合大多数场景；混合语种文本可显式指定主语言。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var samplingSection: some View {
        Section("生成") {
            Toggle("自定义采样参数", isOn: $settings.useCustomSampling)
            if settings.useCustomSampling {
                LabeledContent("温度 \(settings.temperature, specifier: "%.2f")") {
                    Slider(value: $settings.temperature, in: 0.1 ... 1.5)
                }
                LabeledContent("Top-P \(settings.topP, specifier: "%.2f")") {
                    Slider(value: $settings.topP, in: 0.5 ... 1.0)
                }
                Text("温度越低越稳定，越高越有表现力；模型默认 0.90 / 1.00。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var streamingSection: some View {
        Section("流式播放") {
            Picker("分块策略", selection: $settings.streamingInterval) {
                ForEach(AppSettings.streamingOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            Text("分块越小首包越快，越大播放越平滑；对下一次合成生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
