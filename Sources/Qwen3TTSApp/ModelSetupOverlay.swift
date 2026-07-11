import SwiftUI
import TTSEngineMLX

/// 首次启动的模型下载引导：盖在主界面上，就绪后消失。
struct ModelSetupOverlay: View {
    let manager: MLXModelManager
    let onDownload: () -> Void

    var body: some View {
        if manager.state != .ready {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()
                card
            }
            .transition(.opacity)
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            switch manager.state {
            case .checking:
                ProgressView("检查模型…")
            case .needsDownload:
                needsDownloadContent
            case .downloading(let fraction, let completed, let total):
                downloadingContent(fraction: fraction, completed: completed, total: total)
            case .failed(let message):
                failedContent(message: message)
            case .ready:
                EmptyView()
            }
        }
        .padding(28)
        .frame(width: 380)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 24, y: 8)
    }

    private var needsDownloadContent: some View {
        VStack(spacing: 12) {
            Text("首次使用需要下载模型")
                .font(.headline)
            Text("Qwen3-TTS 0.6B（约 \(Self.formatBytes(MLXModelManager.approximateDownloadBytes))）\n下载后完全离线运行，文本不离开你的 Mac。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let available = manager.availableDiskBytes {
                if available < MLXModelManager.approximateDownloadBytes {
                    Label("磁盘可用空间不足（剩余 \(Self.formatBytes(available))）", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("磁盘可用空间：\(Self.formatBytes(available))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Button("开始下载", action: onDownload)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled((manager.availableDiskBytes ?? .max) < MLXModelManager.approximateDownloadBytes)
        }
    }

    private func downloadingContent(fraction: Double, completed: Int64, total: Int64) -> some View {
        VStack(spacing: 12) {
            Text("正在下载模型…")
                .font(.headline)
            ProgressView(value: max(0, min(1, fraction)))
                .progressViewStyle(.linear)
            Text(total > 0
                 ? "\(Self.formatBytes(completed)) / \(Self.formatBytes(total))"
                 : Self.formatBytes(completed))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 12) {
            Label("下载失败", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            Button("重试", action: onDownload)
                .buttonStyle(.borderedProminent)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
