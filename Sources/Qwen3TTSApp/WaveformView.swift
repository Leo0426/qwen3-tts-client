import SwiftUI

/// 真实音频波形：由合成结果的实际采样绘制振幅条，
/// 已播放部分点亮为强调色；流式合成时波形随音频到达实时生长。
struct WaveformView: View {
    let samples: [Float]
    /// 播放进度 0...1
    let progress: Double

    private static let barCount = 56

    var body: some View {
        Canvas { context, size in
            let levels = Self.levels(from: samples, count: Self.barCount)
            let slotWidth = size.width / CGFloat(Self.barCount)
            let barWidth = slotWidth * 0.58
            for (index, level) in levels.enumerated() {
                let height = max(2.5, CGFloat(level) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slotWidth + (slotWidth - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let played = (Double(index) + 0.5) / Double(Self.barCount) <= progress
                context.fill(path, with: .color(played ? .accentColor : .primary.opacity(0.16)))
            }
        }
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(progress * 100))%")
    }

    /// 分桶取峰值并按整体峰值归一；跨步采样保证长音频下开销恒定
    private static func levels(from samples: [Float], count: Int) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.08, count: count)
        }
        let bucketSize = max(1, samples.count / count)
        let step = max(1, bucketSize / 64)
        var peaks = [Float](repeating: 0, count: count)
        for bucket in 0 ..< count {
            let start = bucket * bucketSize
            let end = min(samples.count, start + bucketSize)
            guard start < end else { break }
            var peak: Float = 0
            var index = start
            while index < end {
                peak = max(peak, abs(samples[index]))
                index += step
            }
            peaks[bucket] = peak
        }
        let maxPeak = max(peaks.max() ?? 1, 0.01)
        return peaks.map { max(0.08, $0 / maxPeak) }
    }
}
