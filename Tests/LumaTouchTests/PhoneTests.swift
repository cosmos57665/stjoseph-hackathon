import AppKit

@MainActor final class PhoneTests {
    func run() async throws {
        expectEqual(Morse.vibrationPattern(code: ".-", unit: 0.22), [220,220,660])
        expectEqual(Morse.vibrationPattern(code: "...", unit: 0.12), [120,120,120,120,120])
        expectTrue(PhoneBridge.validPattern([0]))
        expectFalse(PhoneBridge.validPattern([]))
        expectFalse(PhoneBridge.validPattern([-1]))
        expectFalse(PhoneBridge.validPattern([2001]))
        expectFalse(PhoneBridge.validPattern(Array(repeating: 100, count: 65)))
        for code in Morse.alphabet.values { expectTrue(PhoneBridge.validPattern(Morse.vibrationPattern(code: code, unit: 0.45))) }
        var local = 0, patterns: [[Int]] = [], stops = 0
        let player = HapticPlayer(startupDelay: 0, output: { _ in local += 1 })
        player.phoneOutput = { patterns.append($0); return true }
        player.phoneStop = { stops += 1 }
        player.unit = 0.12
        player.load("A"); player.play()
        try await Task.sleep(nanoseconds: 30_000_000)
        expectEqual(patterns, [[120,120,360]]); expectEqual(local, 0)
        player.pause(); expectTrue(stops >= 2); expectFalse(player.isPlaying)
        patterns = []; player.cue(.paused)
        expectEqual(patterns, [[50,110,50]]); expectEqual(local, 0)
        player.stop(); patterns = []
        player.phoneOutput = { _ in false }
        player.cue(.ready); expectEqual(local, 1)
        player.stop()
        let phone = PhoneBridge()
        expectFalse(phone.enabled); expectFalse(phone.ready)
        expectFalse(phone.play([200])); phone.shutdown()
    }
}
