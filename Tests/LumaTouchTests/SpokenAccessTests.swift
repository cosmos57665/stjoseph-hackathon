import AVFoundation
import Speech

@MainActor final class SpokenAccessTests {
    func run() async throws {
        for duration in [Double.nan, Double.infinity, -1, 0, 600.1] {
            do { _ = try SpokenAccess.chunkRanges(duration: duration); expectTrue(false) }
            catch { expectTrue(true) }
        }
        let one = try SpokenAccess.chunkRanges(duration: 12.5)
        expectEqual(one.count, 1); expectEqual(one[0].start.seconds, 0)
        expectEqual(one[0].duration.seconds, 12.5)
        let boundary = try SpokenAccess.chunkRanges(duration: 90)
        expectEqual(boundary.count, 2); expectEqual(boundary[1].start.seconds, 45)
        let maximum = try SpokenAccess.chunkRanges(duration: 600)
        expectEqual(maximum.count, 14)
        expectEqual(maximum.last!.duration.seconds, 15)
        expectEqual(maximum.reduce(0.0) { $0 + $1.duration.seconds }, 600)
        let speech = SpokenAccess(authorization: { .denied })
        expectFalse(speech.canSpeak)
        speech.text = " \n "; expectFalse(speech.canSpeak)
        speech.text = "Keep my original lesson."; expectTrue(speech.canSpeak)
        speech.transcribe(url: URL(fileURLWithPath: "/missing-test-video.mp4"))
        expectTrue(speech.isTranscribing); expectFalse(speech.canSpeak)
        try await Task.sleep(nanoseconds: 15_000_000)
        expectFalse(speech.isTranscribing)
        expectEqual(speech.text, "Keep my original lesson.")
        expectTrue(speech.status.contains("Speech permission is off"))

        var pending: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>?
        let cancelled = SpokenAccess(authorization: {
            await withCheckedContinuation { pending = $0 }
        })
        cancelled.text = "Preserved draft"
        cancelled.transcribe(url: URL(fileURLWithPath: "/missing-test-video.mp4"))
        try await Task.sleep(nanoseconds: 15_000_000)
        expectTrue(pending != nil); expectTrue(cancelled.isTranscribing)
        cancelled.cancelTranscription()
        expectFalse(cancelled.isTranscribing); expectTrue(cancelled.canSpeak)
        cancelled.text = "Edited after cancellation"
        pending?.resume(returning: .denied)
        try await Task.sleep(nanoseconds: 15_000_000)
        expectEqual(cancelled.text, "Edited after cancellation")
        expectTrue(cancelled.status.contains("cancelled"))
        expectFalse(cancelled.isTranscribing)
        cancelled.togglePause(); expectFalse(cancelled.isSpeaking)
        cancelled.shutdown(); expectFalse(cancelled.isSpeaking); expectFalse(cancelled.isPaused)

        // A superseded permission callback must not clear a newer request's state.
        var callbacks: [CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>] = []
        let restarted = SpokenAccess(authorization: {
            await withCheckedContinuation { callbacks.append($0) }
        })
        restarted.text = "Keep restart draft"
        restarted.transcribe(url: URL(fileURLWithPath: "/old-video.mp4"))
        try await Task.sleep(nanoseconds: 15_000_000)
        restarted.transcribe(url: URL(fileURLWithPath: "/new-video.mp4"))
        try await Task.sleep(nanoseconds: 15_000_000)
        expectEqual(callbacks.count, 2)
        callbacks[0].resume(returning: .denied)
        try await Task.sleep(nanoseconds: 15_000_000)
        expectTrue(restarted.isTranscribing)
        expectEqual(restarted.status, "Checking speech permission…")
        expectEqual(restarted.text, "Keep restart draft")
        callbacks[1].resume(returning: .denied)
        try await Task.sleep(nanoseconds: 15_000_000)
        expectFalse(restarted.isTranscribing)
        expectTrue(restarted.status.contains("Speech permission is off"))
    }
}
