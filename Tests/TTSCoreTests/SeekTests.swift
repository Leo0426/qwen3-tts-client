import Testing
@testable import TTSCore

@MainActor
struct SeekTests {
    /// 回归：空播放器上 seek 不崩溃、不改变状态
    @Test func seekOnEmptyPlayerIsSafe() {
        let player = StreamingAudioPlayer()
        player.seek(to: 3.0)
        #expect(player.state == .idle)
        #expect(player.playbackTime == 0)
    }
}
