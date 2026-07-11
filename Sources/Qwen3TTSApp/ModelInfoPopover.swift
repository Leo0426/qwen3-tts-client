import SwiftUI
import TTSEngineMLX

/// 工具栏弹出的模型管理面板：状态、占用、删除。
struct ModelInfoPopover: View {
    let manager: MLXModelManager
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("本地模型", systemImage: "cpu")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("模型").foregroundStyle(.secondary)
                    Text(manager.modelRepo.components(separatedBy: "/").last ?? manager.modelRepo)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("状态").foregroundStyle(.secondary)
                    statusText
                }
                if let bytes = manager.diskUsageBytes {
                    GridRow {
                        Text("磁盘占用").foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    }
                }
            }
            .font(.callout)

            if manager.state == .ready {
                Divider()
                if confirmingDelete {
                    HStack {
                        Text("删除后需重新下载")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("取消") { confirmingDelete = false }
                        Button("删除", role: .destructive) {
                            manager.deleteModel()
                            confirmingDelete = false
                        }
                    }
                } else {
                    Button("删除模型…", role: .destructive) {
                        confirmingDelete = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var statusText: some View {
        switch manager.state {
        case .ready:
            Label("已就绪 · 完全离线", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            Label("下载中", systemImage: "arrow.down.circle")
                .foregroundStyle(.blue)
        case .needsDownload:
            Label("未下载", systemImage: "arrow.down.circle.dotted")
                .foregroundStyle(.orange)
        case .checking:
            Label("检查中", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .failed:
            Label("下载失败", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
