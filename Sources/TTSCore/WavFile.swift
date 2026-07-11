import AVFoundation
import Foundation

/// 单声道 Float32 样本与 WAV 文件的互转（导出 / 历史重播用）。
/// 写入手工构造 RIFF（IEEE float32）：AVAudioFile 的写缓冲在关闭时机上不可靠，
/// 会把最后一个不满块的尾部截掉。
public enum WavFile {
    public static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        let dataSize = UInt32(samples.count * MemoryLayout<Float>.size)
        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        append(&data, UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(&data, UInt32(16))
        append(&data, UInt16(3)) // IEEE float
        append(&data, UInt16(1)) // 单声道
        append(&data, UInt32(sampleRate))
        append(&data, UInt32(sampleRate) * 4) // byte rate
        append(&data, UInt16(4)) // block align
        append(&data, UInt16(32)) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(&data, dataSize)
        samples.withUnsafeBufferPointer { pointer in
            data.append(UnsafeRawBufferPointer(pointer).bindMemory(to: UInt8.self))
        }
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw CocoaError(.fileReadUnknown)
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        // AVAudioFile.read 与 POSIX read 一样不保证一次读满，必须循环到 EOF
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            guard let channelData = buffer.floatChannelData else {
                throw CocoaError(.fileReadCorruptFile)
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
        }
        return (samples, format.sampleRate)
    }

    private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
