import Foundation
import AppKit

final class CoreTests {
    func testKnownMorseAndSpacing() {
        expectEqual(Morse.display("SOS"), "... --- ...")
        expectEqual(Morse.display("HI THERE"), ".... .. / - .... . .-. .")
        expectEqual(Morse.encode("E T").map(\.word), [0, 1])
        expectEqual(Morse.units(Morse.encode("E")), 1)
        expectEqual(Morse.units(Morse.encode("T")), 3)
        expectEqual(Morse.units(Morse.encode("EE")), 5)
        expectEqual(Morse.units(Morse.encode("E E")), 9)
        expectEqual(Morse.units(Morse.encode("SOS")), 27)
    }
    func testNormalizationAndUnrepresentableText() {
        expectEqual(Morse.display("é"), ".")
        expectEqual(Morse.unsupported("Hi 🌱 தமிழ்"), String(Set("🌱 தமிழ்".filter { !$0.isWhitespace }).sorted()))
        expectEqual(Morse.encode("  \n  "), [])
        expectEqual(Morse.alphabet.count, 54)
    }
    func testAllProvidersSendImagesAndKeepKeysOutOfBodyAndURL() throws {
        for provider in Provider.allCases {
            let config = AIConfiguration(provider: provider, key: "test-secret-not-real", model: provider.defaultModel)
            let request = try AIClient.request(config: config, prompt: "Read this", image: Data([1, 2, 3]))
            expectEqual(request.httpMethod, "POST")
            expectFalse(request.url!.absoluteString.contains(config.key))
            expectFalse(String(data: request.httpBody!, encoding: .utf8)!.contains(config.key))
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            if provider == .gemini {
                expectEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), config.key)
                let contents = body["contents"] as! [[String: Any]]
                let parts = contents[0]["parts"] as! [[String: Any]]
                expectEqual((parts[1]["inline_data"] as! [String: Any])["mime_type"] as? String, "image/jpeg")
            } else {
                expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(config.key)")
                let messages = body["messages"] as! [[String: Any]]
                let content = messages[0]["content"] as! [[String: Any]]
                expectTrue(((content[1]["image_url"] as! [String: Any])["url"] as! String).hasPrefix("data:image/jpeg;base64,"))
            }
        }
    }
    func testEmptyKeyAndBadModelAreRejected() {
        expectThrows(try AIClient.request(config: AIConfiguration(provider: .groq, key: "", model: "model"), prompt: "hi"))
        expectThrows(try AIClient.request(config: AIConfiguration(provider: .gemini, key: "fake", model: "model?key=other"), prompt: "hi"))
    }
    func testProviderResponsesAndErrors() throws {
        let gemini = Data(#"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"secret reasoning","thought":true},{"text":"HELLO"}]}}]}"#.utf8)
        expectEqual(try AIClient.parse(data: gemini, status: 200, provider: .gemini), "HELLO")
        let compatible = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"HI"}}]}"#.utf8)
        for p in [Provider.openRouter, .groq] { expectEqual(try AIClient.parse(data: compatible, status: 200, provider: p), "HI") }
        for status in [400, 401, 403, 404, 429, 500] {
            expectThrows(try AIClient.parse(data: Data("sensitive raw content".utf8), status: status, provider: .groq)) { error in
                expectFalse(error.localizedDescription.contains("sensitive raw content"))
            }
        }
        expectThrows(try AIClient.parse(data: Data(#"{"choices":[{"finish_reason":"length","message":{"content":"incomplete"}}]}"#.utf8), status: 200, provider: .openRouter))
        expectThrows(try AIClient.parse(data: Data(#"{"candidates":[{"finishReason":"MAX_TOKENS"}]}"#.utf8), status: 200, provider: .gemini))
    }
    func testPracticePDFTextAndScan() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/Start-Here-Practice.pdf")
        let pages = try PDFReader.open(url) { _, _ in }
        expectEqual(pages.count, 2)
        expectTrue(pages[0].source.contains("I AM SAM"))
        expectEqual(pages[0].extraction, "PDF text")
        expectTrue(pages[1].source.lowercased().contains("photosynthesis"))
        expectEqual(pages[1].extraction, "On-device OCR")
        let image = try PDFReader.imageData(url: url, page: 1)
        expectGreater(image.count, 1000)
        let bitmap = NSBitmapImageRep(data: image)!
        var darkSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent < 0.7 { darkSamples += 1 }
            }
        }
        expectGreater(darkSamples, 50)
    }
    @MainActor func testPlayerNavigationAndReset() {
        let player = HapticPlayer()
        player.load("HI SAM")
        expectEqual(player.current?.character, "H")
        player.skipWord(1)
        expectEqual(player.current?.character, "S")
        player.skipWord(-1)
        expectEqual(player.current?.character, "H")
        player.reset()
        expectFalse(player.isPlaying)
        player.load("")
        expectNil(player.current)
        expectEqual(player.progress, 0)
    }
}

private var checks = 0
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    checks += 1
    precondition(lhs == rhs, "Expected equal values at \(file):\(line): \(lhs) != \(rhs)")
}
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    checks += 1
    precondition(value, "Expected true at \(file):\(line)")
}
func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
func expectGreater<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) { expectTrue(lhs > rhs, file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    checks += 1
    do { _ = try expression(); preconditionFailure("Expected error at \(file):\(line)") }
    catch { handler(error) }
}
@main struct TestRunner {
    @MainActor static func main() async throws {
        let suite = CoreTests()
        suite.testKnownMorseAndSpacing()
        suite.testNormalizationAndUnrepresentableText()
        try suite.testAllProvidersSendImagesAndKeepKeysOutOfBodyAndURL()
        suite.testEmptyKeyAndBadModelAreRejected()
        try suite.testProviderResponsesAndErrors()
        try suite.testPracticePDFTextAndScan()
        suite.testPlayerNavigationAndReset()
        await ReaderControlTests().run()
        TouchControlTests().run()
        print("PASS: \(checks) assertions covering Morse, PDF/OCR, provider requests, reader playback, line navigation and touch controls. No live API calls or haptic output.")
    }
}
