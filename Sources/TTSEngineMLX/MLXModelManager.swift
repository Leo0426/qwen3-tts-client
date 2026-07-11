import Foundation
import HuggingFace
import MLXAudioCore
import Observation

/// 模型管理：隐藏 HF 下载协议、进度与缓存布局。
/// 对外只有「装没装、下载（带进度）、就绪状态」。
@MainActor
@Observable
public final class MLXModelManager {
    public enum State: Equatable {
        case checking
        case needsDownload
        case downloading(fraction: Double, completedBytes: Int64, totalBytes: Int64)
        case ready
        case failed(String)
    }

    public let modelRepo: String
    public private(set) var state: State = .checking

    /// 引导页提示用的下载体积估算（0.6B-CustomVoice-8bit 实测约 1.8 GB）
    public static let approximateDownloadBytes: Int64 = 1_900_000_000

    private let cache = HubCache.default

    public init(modelRepo: String = MLXInferenceEngine.defaultModelRepo) {
        self.modelRepo = modelRepo
    }

    public func refresh() {
        state = isInstalled ? .ready : .needsDownload
    }

    /// 镜像上游 ModelUtils 的缓存判定：
    /// `<hub-cache>/mlx-audio/<owner>_<repo>/` 下有 config.json 且存在非空 safetensors。
    public var isInstalled: Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return false }
        let hasWeights = files.contains { file in
            file.pathExtension == "safetensors"
                && ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) > 0
        }
        let hasConfig = FileManager.default.fileExists(
            atPath: modelDirectory.appendingPathComponent("config.json").path
        )
        return hasWeights && hasConfig
    }

    public var modelDirectory: URL {
        cache.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelRepo.replacingOccurrences(of: "/", with: "_"))
    }

    /// 缓存所在卷的可用空间（引导页磁盘提示）
    public var availableDiskBytes: Int64? {
        let values = try? cache.cacheDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public func download() async {
        guard let repoID = Repo.ID(rawValue: modelRepo) else {
            state = .failed("无效的模型仓库名：\(modelRepo)")
            return
        }
        state = .downloading(fraction: 0, completedBytes: 0, totalBytes: 0)
        do {
            _ = try await ModelUtils.resolveOrDownloadModel(
                client: HubClient(cache: cache),
                cache: cache,
                repoID: repoID,
                requiredExtension: "safetensors",
                progressHandler: { [weak self] progress in
                    self?.state = .downloading(
                        fraction: progress.fractionCompleted,
                        completedBytes: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount
                    )
                }
            )
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
