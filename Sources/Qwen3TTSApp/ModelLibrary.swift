import Foundation
import Observation
import TTSEngineMLX

/// 模型库：所有已知模型的下载管理器统一入口。
/// 存储路径与下载源在这里集中管理，切换路径后管理器与引擎全部重建。
@MainActor
@Observable
final class ModelLibrary {
    struct CatalogEntry: Identifiable, Hashable {
        let repo: String
        let title: String
        let subtitle: String
        var id: String { repo }
    }

    /// 全部可用模型（预置音色 = CustomVoice 变体，声音克隆 = Base 变体）
    static let catalog: [CatalogEntry] = [
        CatalogEntry(
            repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
            title: "预置音色 0.6B",
            subtitle: "9 个官方音色 · 更快 · 约 1.8 GB"
        ),
        CatalogEntry(
            repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit",
            title: "预置音色 1.7B",
            subtitle: "9 个官方音色 · 音质更好 · 约 2.9 GB"
        ),
        CatalogEntry(
            repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
            title: "声音克隆 0.6B",
            subtitle: "参考音频复刻音色 · 更快 · 约 1.9 GB"
        ),
        CatalogEntry(
            repo: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
            title: "声音克隆 1.7B",
            subtitle: "参考音频复刻音色 · 音质更好 · 约 3.0 GB"
        ),
    ]

    private(set) var cacheDirectory: URL?
    private(set) var downloadHost: URL
    private var managers: [String: MLXModelManager] = [:]

    init(cacheDirectory: URL?, downloadHost: URL) {
        self.cacheDirectory = cacheDirectory
        self.downloadHost = downloadHost
    }

    /// 每个 repo 一个管理器，惰性创建并复用（下载进度等状态全程一致）
    func manager(for repo: String) -> MLXModelManager {
        if let existing = managers[repo] { return existing }
        let manager = MLXModelManager(modelRepo: repo, cacheDirectory: cacheDirectory)
        manager.downloadHost = downloadHost
        manager.refresh()
        managers[repo] = manager
        return manager
    }

    /// 下载中心展示用：目录中全部模型的管理器
    var catalogManagers: [(entry: CatalogEntry, manager: MLXModelManager)] {
        Self.catalog.map { ($0, manager(for: $0.repo)) }
    }

    /// 更改存储路径：管理器全部重建（不迁移已下载文件）
    func setCacheDirectory(_ url: URL?) {
        guard url != cacheDirectory else { return }
        cacheDirectory = url
        managers = [:]
    }

    func setDownloadHost(_ url: URL) {
        downloadHost = url
        for manager in managers.values {
            manager.downloadHost = url
        }
    }
}
