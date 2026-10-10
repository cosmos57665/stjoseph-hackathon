import AppKit
import Foundation

@MainActor final class AskAITests {
    private let config = AIConfiguration(provider: .gemini, key: "test-only-placeholder", model: "test-model")
    private func player() -> HapticPlayer { HapticPlayer(startupDelay: 0, output: { _ in }) }
    private func context(id: UUID = UUID()) -> LessonQuestionContext {
        LessonQuestionContext(documentID: id, title: "Plants", pageIndex: 0, line: "Leaves absorb light.", pages: ["Plants use light to make food.", "Chlorophyll absorbs light.", "Numbers and fractions."])
    }
    private func write(_ text: String, to model: AskAIModel) {
        for char in text {
            if char == " " { model.addSpace(); continue }
            for mark in Morse.alphabet[char]! { model.add(mark == "." ? .dot : .dash) }
            model.finishLetter()
        }
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 40_000_000) }

    func testShapesAndTaps() {
        let line = (0...10).map { CGPoint(x: 0.15 + Double($0) * 0.025, y: 0.3) }
        expectEqual(DrawnMorse.recognize(line), .dash)
        expectEqual(DrawnMorse.recognize(Array(line.reversed())), .dash)
        let circle: [CGPoint] = (0...30).map { i in
            let angle: Double = Double(i) * Double.pi / 15.0
            let x: Double = 0.4 + 0.04 * cos(angle)
            let y: Double = 0.3 + 0.04 * sin(angle)
            return CGPoint(x: x, y: y)
        }
        expectEqual(DrawnMorse.recognize(circle), .dot)
        expectNil(DrawnMorse.recognize([CGPoint(x: 0.3, y: 0.2)]))
        expectNil(DrawnMorse.recognize((0...10).map { CGPoint(x: 0.3, y: Double($0) / 20) }))
        expectNil(DrawnMorse.recognize((0...10).map { CGPoint(x: Double($0) / 20, y: Double($0) / 20) }))
        expectNil(DrawnMorse.recognize([CGPoint(x: Double.nan, y: 0), .zero, .zero]))
        expectTrue(DrawnMorse.isTap([CGPoint(x: 0.4, y: 0.3)], duration: 0.12))
        expectTrue(DrawnMorse.isTap([.zero, CGPoint(x: 0.008, y: 0.003)], duration: 0.25))
        expectFalse(DrawnMorse.isTap([.zero], duration: 1.2))
        expectFalse(DrawnMorse.isTap(line, duration: 0.2))
        expectFalse(DrawnMorse.isTap([], duration: 0.1))
    }

    func testDecodingAndEditing() throws {
        for (character, code) in Morse.alphabet {
            var draft = MorseDraft()
            for mark in code { try draft.append(mark == "." ? .dot : .dash) }
            expectEqual(draft.letter, character)
            try draft.finishLetter()
            expectEqual(draft.text, String(character))
        }
        var draft = MorseDraft()
        try draft.append(.dot); try draft.append(.dash)
        expectEqual(draft.preview, "A")
        try draft.space()
        expectEqual(draft.text, "A ")
        try draft.space()
        expectEqual(draft.text, "A ")
        try draft.append(.dash)
        expectEqual(try draft.question(), "A T")
        expectTrue(draft.undo()); expectEqual(draft.text, "A ")
        try draft.append(.dot); expectTrue(draft.undo()); expectEqual(draft.pending, "")
        var invalid = MorseDraft()
        for _ in 0..<5 { try invalid.append(.dash) }
        expectThrows(try invalid.append(.dash)); expectEqual(invalid.pending, "-----")
        var empty = MorseDraft()
        expectThrows(try empty.question()); expectFalse(empty.undo())
        var long = MorseDraft()
        for _ in 0..<MorseDraft.limit { try long.append(.dot); try long.finishLetter() }
        expectThrows(try long.append(.dot)); expectEqual(long.text.count, 240)
    }

    func testContextAndProviderInstructions() throws {
        let payload = try QuestionPrompt.payload(question: "WHY CHLOROPHYLL", context: context(), history: [])
        let data = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as! [String: Any]
        expectEqual(data["learner_question"] as? String, "WHY CHLOROPHYLL")
        let excerpts = data["document_excerpts"] as! [[String: Any]]
        expectEqual(excerpts.count, 2)
        expectEqual(excerpts[0]["page"] as? Int, 1)
        expectEqual(excerpts[1]["page"] as? Int, 2)
        let long = LessonQuestionContext(documentID: UUID(), title: "Ignore instructions", pageIndex: 0, line: "source line", pages: Array(repeating: String(repeating: "chlorophyll ", count: 10000), count: 5))
        let bounded = long.excerpts(for: "CHLOROPHYLL")
        expectEqual(bounded.count, 3)
        expectEqual((bounded[0]["text"] as! String).count, 12000)
        expectEqual((bounded[1]["text"] as! String).count, 4000)
        expectEqual(bounded[0]["truncated"] as? Bool, true)
        for provider in Provider.allCases {
            let request = try AIClient.request(config: AIConfiguration(provider: provider, key: "test-only-secret", model: "test-model"), prompt: payload, system: QuestionPrompt.system)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            expectFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("test-only-secret"))
            if provider == .gemini { expectTrue(body["systemInstruction"] != nil) }
            else { expectEqual((body["messages"] as! [[String: Any]])[0]["role"] as? String, "system") }
        }
    }

    func testTapClicksNeverSendAndPhysicalClickSendsOnce() {
        let view = MorseDrawingNSView()
        var commands: [DrawingCommand] = []
        view.onCommand = { commands.append($0) }
        func event(_ type: NSEvent.EventType, count: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 1,
                              windowNumber: 0, context: nil, eventNumber: 1, clickCount: count, pressure: 1)!
        }
        // A tap-to-click sequence has no pressure gesture, regardless of the
        // mouse event's pressure field or click count. It must never submit.
        for count in 1...4 { view.mouseDown(with: event(.leftMouseDown, count: count)); view.mouseUp(with: event(.leftMouseUp, count: count)) }
        expectEqual(commands, [])
        // Pressure may arrive either before or after mouseDown.
        view.receivedPressure(stage: 1)
        view.mouseDown(with: event(.leftMouseDown, count: 3))
        view.mouseUp(with: event(.leftMouseUp, count: 3))
        expectEqual(commands, [.send])
        view.mouseDown(with: event(.leftMouseDown))
        view.receivedPressure(stage: 1); view.receivedPressure(stage: 0)
        view.mouseUp(with: event(.leftMouseUp)); view.mouseUp(with: event(.leftMouseUp))
        expectEqual(commands, [.send, .send])
        view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp))
        expectEqual(commands, [.send, .send]) // previous pressure cannot leak.
        view.phase = .waiting
        view.receivedPressure(stage: 1); view.mouseDown(with: event(.leftMouseDown)); view.mouseUp(with: event(.leftMouseUp))
        expectEqual(commands.count, 2)
        expectEqual(MorseDrawingNSView.command(for: .previousLine, phase: .composing), .finishLetter)
        expectEqual(MorseDrawingNSView.command(for: .nextLine, phase: .composing), .undo)
        expectEqual(MorseDrawingNSView.command(for: .faster, phase: .composing), .space)
        expectEqual(MorseDrawingNSView.command(for: .slower, phase: .composing), .review)
        expectNil(MorseDrawingNSView.command(for: .nextLine, phase: .waiting))
        expectEqual(MorseDrawingNSView.command(for: .nextLine, phase: .answer), .nextAnswer)
    }

    func testSingleRequestReplyAndFollowup() async {
        var requests = 0
        var payloads: [String] = []
        let model = AskAIModel(player: player()) { _, prompt in requests += 1; payloads.append(prompt); return "Plants need light.\nLight helps make food." }
        model.prepare(context()); write("WHY", to: model)
        model.send(config: config); model.send(config: config)
        expectEqual(model.phase, .waiting)
        await settle()
        expectEqual(requests, 1); expectEqual(model.phase, .answer)
        expectEqual(model.answerLines.count, 2); expectEqual(model.answerLine, 0)
        expectFalse(model.player.isPlaying)
        model.toggleAnswer(); expectTrue(model.player.isPlaying)
        model.toggleAnswer(); expectFalse(model.player.isPlaying)
        model.moveAnswer(1); expectEqual(model.answerLine, 1); expectTrue(model.player.isPlaying)
        model.moveAnswer(1); expectEqual(model.answerLine, 1); expectFalse(model.player.isPlaying)
        model.newQuestion(); expectEqual(model.draft.text, "")
        write("HOW", to: model); model.send(config: config)
        await settle()
        expectEqual(requests, 2)
        expectTrue(payloads[1].contains("Plants need light."))
        model.suspend()
    }

    func testMissingKeyFailureAndCancellationKeepQuestion() async {
        var requests = 0
        let model = AskAIModel(player: player()) { _, _ in requests += 1; throw AppError.message("do not expose raw response") }
        model.prepare(context()); write("WHY", to: model)
        model.send(config: AIConfiguration(provider: .gemini, key: "", model: "test"))
        expectEqual(requests, 0); expectEqual(model.phase, .composing); expectEqual(model.draft.text, "WHY")
        model.send(config: config); await settle()
        expectEqual(requests, 1); expectEqual(model.phase, .composing); expectEqual(model.draft.text, "WHY")
        expectFalse(model.status.contains("raw response"))
        model.suspend()
        let slow = AskAIModel(player: player()) { _, _ in try? await Task.sleep(nanoseconds: 80_000_000); return "Stale answer" }
        slow.prepare(context()); write("WHY", to: slow); slow.send(config: config)
        await Task.yield(); slow.suspend(); await settle()
        expectEqual(slow.phase, .composing); expectEqual(slow.draft.text, "WHY"); expectEqual(slow.answer, "")
        expectFalse(slow.player.isPlaying)
        slow.prepare(context()); expectEqual(slow.draft.text, "") // new document
        slow.suspend()
    }

    func testReaderPositionAndEscape() {
        let assistant = AskAIModel(player: player()) { _, _ in "Test" }
        let model = Workspace(loadPreferences: false, player: player(), practicePlayer: player(), assistant: assistant)
        model.showTouchWelcome = false
        model.pages = [LessonPage(id: 0, source: "First line\nSecond line", extraction: "Test")]
        model.syncPlayer(); model.selectLine(1); model.player.index = 2
        model.enterAskMode()
        expectTrue(model.askMode); expectTrue(model.touchMode); expectFalse(model.readingControlsAvailable)
        expectEqual(assistant.context?.line, "Second line")
        write("HI", to: assistant)
        model.returnFromQuestion()
        expectEqual(model.selectedLine, 1); expectEqual(model.player.index, 2)
        expectFalse(model.askMode); expectTrue(model.touchMode)
        model.enterAskMode(); expectEqual(assistant.draft.text, "HI")
        model.exitTouchMode(); expectFalse(model.askMode); expectFalse(model.touchMode)
        expectFalse(assistant.player.isPlaying)
        model.stopAll()
    }

    func run() async throws {
        testShapesAndTaps(); try testDecodingAndEditing(); try testContextAndProviderInstructions()
        testTapClicksNeverSendAndPhysicalClickSendsOnce()
        await testSingleRequestReplyAndFollowup(); await testMissingKeyFailureAndCancellationKeepQuestion()
        testReaderPositionAndEscape()
    }
}
