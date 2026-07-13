import AVFoundation
import Foundation

/// 单声道 Float32 样本导出为 AAC (.m4a)，文件体积约为 WAV 的十分之一。
/// 与 WavFile 不同这里可以用 AVAudioFile：样本一次性写入，
/// 函数返回时文件即关闭，不存在流式写入的收尾截断问题。
public enum M4AFile {
    public static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        guard !samples.isEmpty,
              let pcmFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: pcmFormat,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: samples.count)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // 码率由编码器按采样率自选（固定码率在 24kHz 单声道下会越界报错）
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}
