import Testing
@testable import TTSCore

@MainActor
struct StreamingAudioPlayerTests {
    /// 回归：UI 可能在 beginStreaming 之前渲染进度条。
    /// 未挂载节点上读进度 / 调 stop 曾抛 NSException 导致崩溃。
    @Test func accessBeforeStreamingIsSafe() {
        let player = StreamingAudioPlayer()
        #expect(player.playbackTime == 0)
        #expect(player.bufferedDuration == 0)
        player.pause()
        player.resume()
        player.stop()
        #expect(player.state == .idle)
    }
}
