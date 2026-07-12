import SwiftUI
import TTSCore

struct HistoryPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("历史")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider()
            if model.history.items.isEmpty {
                emptyState
            } else {
                List(model.history.items) { item in
                    HistoryRow(item: item, model: model)
                }
                .listStyle(.plain)
            }
        }
        .background(.background.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text("合成结果会出现在这里")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryRow: View {
    let item: StoredHistoryItem
    let model: AppModel
    @State private var isHovering = false

    private var voiceName: String {
        Voice.presets.first(where: { $0.id == item.voiceID })?.displayName ?? item.voiceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
                .lineLimit(2)
                .font(.callout)
            HStack(spacing: 6) {
                Text(voiceName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quinary, in: Capsule())
                Text(Self.format(item.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if isHovering {
                    Button {
                        model.replay(item)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("重播")
                    Button {
                        model.exportHistory(item)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("导出 WAV")
                    Button {
                        model.deleteHistory(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("删除")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(height: 18)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("重播") { model.replay(item) }
            Button("导出 WAV…") { model.exportHistory(item) }
            Divider()
            Button("删除", role: .destructive) { model.deleteHistory(item) }
        }
    }

    private static func format(_ time: TimeInterval) -> String {
        String(format: "%.1fs", time)
    }
}
