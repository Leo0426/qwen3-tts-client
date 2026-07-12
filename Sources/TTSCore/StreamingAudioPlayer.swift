import AVFoundation
import Foundation

/// 流式播放引擎：消费 AudioChunk 流，音频到达即出声。
/// 隐藏 AVAudioEngine 的调度细节；同时累积全部样本供重播和导出。
@MainActor
public final class StreamingAudioPlayer {
    public enum State: Equatable {
        case idle
        case playing
        case paused
        case finished
    }

    public private(set) var state: State = .idle
    /// 已累积的全部样本（重播 / 导出用）
    public private(set) var samples: [Float] = []
    public private(set) var sampleRate: Double = 24_000

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// 变速不变调（0.5×~2×）
    private let timePitch = AVAudioUnitTimePitch()
    private var format: AVAudioFormat?

    /// 播放速度；对正在播放的音频立即生效
    public var rate: Float = 1.0 {
        didSet {
            let clamped = min(2.0, max(0.5, rate))
            if clamped != rate { rate = clamped }
            timePitch.rate = rate
        }
    }
    /// 尚未播完的已调度 buffer 数；归零且流已结束 → finished
    private var pendingBuffers = 0
    private var streamEnded = false
    private var attached = false
    /// 调度代际号：stop/seek/replay 后旧 buffer 的完成回调异步补刀，
    /// 代际不匹配的回调直接作废，避免打乱新一轮的计数
    private var scheduleGeneration = 0
    /// seek 后的进度基准（playerNode 的 sampleTime 在重新 play 后从 0 计）
    private var playbackBaseOffset: TimeInterval = 0

    public init() {}

    public var bufferedDuration: TimeInterval {
        Double(samples.count) / sampleRate
    }

    /// 当前播放进度（秒）。
    /// 节点未挂载到引擎时 lastRenderTime 会抛 NSException（UI 可能在
    /// beginStreaming 之前渲染进度条），必须先判 engine。
    public var playbackTime: TimeInterval {
        guard playerNode.engine != nil,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return state == .finished ? bufferedDuration : playbackBaseOffset
        }
        return playbackBaseOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    /// 跳转到指定时间继续播放（含流式合成进行中：之后到达的音频仍按序衔接）
    public func seek(to time: TimeInterval) {
        guard !samples.isEmpty, format != nil else { return }
        let clamped = min(max(0, time), bufferedDuration)
        scheduleGeneration += 1
        playerNode.stop()
        pendingBuffers = 0
        playbackBaseOffset = clamped
        do { try startEngine(sampleRate: sampleRate) } catch { return }
        playerNode.play()
        state = .playing
        let startFrame = min(samples.count, Int(clamped * sampleRate))
        let remaining = Array(samples[startFrame...])
        if remaining.isEmpty {
            settleIfDrained()
        } else {
            schedule(remaining)
        }
    }

    /// 开始一次新的流式播放会话，清空上次的累积样本。
    public func beginStreaming(sampleRate: Double) throws {
        stop()
        playbackBaseOffset = 0
        samples = []
        self.sampleRate = sampleRate
        streamEnded = false
        try startEngine(sampleRate: sampleRate)
        playerNode.play()
        state = .playing
    }

    /// 喂入一块音频，立即进入播放队列。
    public func enqueue(_ chunk: AudioChunk) {
        samples.append(contentsOf: chunk.samples)
        schedule(chunk.samples)
    }

    /// 流式输入结束（合成完成或被取消后调用）。
    public func endStreaming() {
        streamEnded = true
        settleIfDrained()
    }

    public func pause() {
        guard state == .playing else { return }
        playerNode.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        playerNode.play()
        state = .playing
    }

    /// 从头重播累积的全部音频。
    public func replay() throws {
        guard !samples.isEmpty else { return }
        let all = samples
        scheduleGeneration += 1
        playerNode.stop()
        pendingBuffers = 0
        playbackBaseOffset = 0
        streamEnded = true
        try startEngine(sampleRate: sampleRate)
        playerNode.play()
        state = .playing
        schedule(all)
    }

    public func stop() {
        scheduleGeneration += 1
        if playerNode.engine != nil {
            playerNode.stop()
        }
        engine.stop()
        pendingBuffers = 0
        playbackBaseOffset = 0
        streamEnded = true
        state = .idle
    }

    // MARK: - Internals

    private func startEngine(sampleRate: Double) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        if !attached {
            engine.attach(playerNode)
            engine.attach(timePitch)
            timePitch.rate = rate
            attached = true
        }
        // 采样率变化时需要重连
        if self.format?.sampleRate != sampleRate {
            engine.connect(playerNode, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            self.format = format
        }
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func schedule(_ chunkSamples: [Float]) {
        guard let format, !chunkSamples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSamples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(chunkSamples.count)
        chunkSamples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: chunkSamples.count)
        }
        pendingBuffers += 1
        let generation = scheduleGeneration
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.scheduleGeneration == generation else { return }
                self.pendingBuffers -= 1
                self.settleIfDrained()
            }
        }
    }

    private func settleIfDrained() {
        if streamEnded, pendingBuffers <= 0, state == .playing {
            state = .finished
        }
    }
}
