import SwiftUI
import TTSEngineMLX

/// 独立的模型下载中心：存储位置、下载源、全部模型的下载/删除。
struct ModelDownloadView: View {
    let model: AppModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            storageSection
            sourceSection
            catalogSection
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }

    // MARK: - 存储位置

    private var storageSection: some View {
        Section("存储位置") {
            LabeledContent("模型目录") {
                HStack(spacing: 8) {
                    Text(currentStorageDisplayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button("更改…") { pickStorageDirectory() }
                    if !settings.modelStoragePath.isEmpty {
                        Button("恢复默认") {
                            settings.modelStoragePath = ""
                            model.applyStorageDirectory()
                        }
                    }
                }
            }
            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([currentStorageURL])
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            Text("更改路径后新下载存入新位置；已下载的模型不会自动迁移，可在访达中手动移动 mlx-audio 目录后再切换。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentStorageURL: URL {
        settings.resolvedStorageURL ?? MLXModelManager.defaultCacheDirectory
    }

    private var currentStorageDisplayPath: String {
        let path = currentStorageURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func pickStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择模型目录"
        if panel.runModal() == .OK, let url = panel.url {
            settings.modelStoragePath = url.path
            model.applyStorageDirectory()
        }
    }

    // MARK: - 下载源

    private var sourceSection: some View {
        Section("下载源") {
            Picker("下载源", selection: $settings.downloadSource) {
                ForEach(AppSettings.DownloadSource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            if settings.downloadSource == .custom {
                TextField("https://your-mirror.example.com", text: $settings.customEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            Text("对下一次下载生效。国内网络建议使用镜像源。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 模型库

    private var catalogSection: some View {
        Section("模型库") {
            ForEach(ModelLibrary.catalog) { entry in
                ModelCatalogRow(entry: entry, manager: model.modelLibrary.manager(for: entry.repo))
            }
        }
    }
}

private struct ModelCatalogRow: View {
    let entry: ModelLibrary.CatalogEntry
    let manager: MLXModelManager
    @State private var confirmingDelete = false

    var body: some View {
        LabeledContent {
            statusControls
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .confirmationDialog(
            "删除「\(entry.title)」？删除后需重新下载。",
            isPresented: $confirmingDelete
        ) {
            Button("删除", role: .destructive) { manager.deleteModel() }
        }
    }

    @ViewBuilder
    private var statusControls: some View {
        switch manager.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .needsDownload:
            Button("下载") {
                Task { await manager.download() }
            }
        case .downloading(let fraction, let completed, let total):
            HStack(spacing: 8) {
                ProgressView(value: max(0, min(1, fraction)))
                    .frame(width: 100)
                Text(total > 0
                     ? "\(Self.formatBytes(completed)) / \(Self.formatBytes(total))"
                     : Self.formatBytes(completed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .ready:
            HStack(spacing: 8) {
                if let bytes = manager.diskUsageBytes {
                    Text(Self.formatBytes(bytes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除模型")
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(message)
                Button("重试") {
                    Task { await manager.download() }
                }
            }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
