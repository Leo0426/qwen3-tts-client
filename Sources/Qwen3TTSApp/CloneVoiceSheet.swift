import SwiftUI
import TTSCore
import UniformTypeIdentifiers

/// 克隆音色管理：新建（参考音频 + 文字稿 + 命名）与删除。
struct CloneVoiceSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var transcript = ""
    @State private var audioURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("克隆音色")
                .font(.title3.bold())
                .padding(.bottom, 12)

            if !model.clonedVoices.items.isEmpty {
                existingList
                Divider().padding(.vertical, 12)
            }

            newCloneForm

            HStack {
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
        audioURL != nil
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var existingList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已有音色")
                .font(.headline)
            ForEach(model.clonedVoices.items) { voice in
                HStack {
                    Image(systemName: "person.wave.2.fill")
                        .foregroundStyle(.tint)
                    Text(voice.name)
                    Spacer()
                    Button {
                        model.deleteClonedVoice(voice)
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

    private var newCloneForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新建克隆")
                .font(.headline)
            Text("提供 3 秒以上的清晰人声音频和与之完全一致的文字稿，模型将复刻其音色。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    pickAudioFile()
                } label: {
                    Label(audioURL?.lastPathComponent ?? "选择参考音频…", systemImage: "waveform.badge.plus")
                        .lineLimit(1)
                }
                if audioURL != nil {
                    Button {
                        audioURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TextField("音色名称，如：我的声音", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("参考音频的文字稿")
                    .font(.callout)
                TextEditor(text: $transcript)
                    .font(.body)
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
    }

    private func pickAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            audioURL = panel.url
        }
    }

    private func save() {
        guard let audioURL else { return }
        model.addClonedVoice(
            name: name.trimmingCharacters(in: .whitespaces),
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceAudioURL: audioURL
        )
        dismiss()
    }
}
