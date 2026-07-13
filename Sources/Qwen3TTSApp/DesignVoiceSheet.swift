import SwiftUI
import TTSCore

/// 语音设计管理：用自然语言描述凭空造声音，命名保存后可反复使用。
struct DesignVoiceSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var name = ""
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("语音设计")
                .font(.title3.bold())
                .padding(.bottom, 12)

            if !model.designedVoices.items.isEmpty {
                existingList
                Divider().padding(.vertical, 12)
            }

            newDesignForm

            if let error = model.errorMessage {
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if model.errorNeedsDownloadCenter {
                        Button("去下载") {
                            openWindow(id: "model-downloads")
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                    Button {
                        model.clearError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("关闭提示")
                }
                .padding(.top, 8)
            }

            HStack {
                Button {
                    model.toggleAuditionDesign(prompt: prompt)
                } label: {
                    Label(
                        model.isSpeaking ? "停止" : "试听",
                        systemImage: model.isSpeaking ? "stop.fill" : "play.fill"
                    )
                }
                .help("用示例句试听这段描述的声音，满意再保存")
                .disabled(!model.isSpeaking && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存并使用") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 460)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var existingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已有设计")
                .font(.headline)
            ForEach(model.designedVoices.items) { voice in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                        Text(voice.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        model.deleteDesignedVoice(voice)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除")
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var newDesignForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新建设计")
                .font(.headline)
            Text("用自然语言描述想要的声音：音色、年龄、性别、情感、语速等，越具体越好。")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("名称，如：磁性男声", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("声音描述")
                    .font(.callout)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    if prompt.isEmpty {
                        Text("例：一个低沉磁性的中年男声，语速平缓，像深夜电台主播")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func save() {
        model.addDesignedVoice(
            name: name.trimmingCharacters(in: .whitespaces),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}
