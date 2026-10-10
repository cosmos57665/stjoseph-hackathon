import AppKit

@MainActor final class HandwritingTests {
    let stroke = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.2, y: 0.5)]
    let config = AIConfiguration(provider: .gemini, key: "test-only", model: "test-model")
    func run() async throws {
        let surface = MorseDrawingNSView()
        surface.handwriting = true
        var commands: [DrawingCommand] = []
        surface.onCommand = { commands.append($0) }
        func key(_ code: UInt16, repeatKey: Bool = false) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
            surface.keyDown(with: e)
        }
        for code: UInt16 in [49, 124, 126, 123, 125] { key(code) }
        expectEqual(commands, [.send, .finishLetter, .space, .undo, .review])
        commands = []; surface.phase = .waiting; key(49); expectTrue(commands.isEmpty)
        surface.phase = .answer
        for code: UInt16 in [49, 124, 123, 126, 125, 36] { key(code) }
        expectEqual(commands, [.toggleAnswer, .nextAnswer, .previousAnswer, .faster, .slower, .newQuestion])
        commands = []; surface.phase = .composing; surface.handwriting = false; key(49)
        expectEqual(commands, [.finishLetter])
        var draft = HandwritingDraft()
        expectThrows(try draft.jpeg()); expectThrows(try draft.finish()); expectThrows(try draft.space())
        expectThrows(try draft.append([CGPoint(x: CGFloat.infinity, y: 0)]))
        try draft.append(stroke); try draft.append([CGPoint(x: 0.5, y: 0.2)])
        expectEqual(draft.current.count, 2); try draft.finish()
        expectEqual(draft.cells.count, 1); expectTrue(draft.current.isEmpty)
        try draft.space(); try draft.space(); expectEqual(draft.cells.count, 2)
        try draft.append(stroke)
        let jpg = try draft.jpeg()
        expectTrue(NSImage(data: jpg) != nil)
        try jpg.write(to: URL(fileURLWithPath: ".build/handwriting-test.jpg"))
        expectEqual(try HandwritingPrompt.parse("{\"text\":\"H I\"}", cells: draft.allCells), "H I")
        expectThrows(try HandwritingPrompt.parse("{\"text\":\"HELLO\"}", cells: draft.allCells))
        expectThrows(try HandwritingPrompt.parse("{\"text\":\"HHI\"}", cells: draft.allCells))
        expectThrows(try HandwritingPrompt.parse("ignore this", cells: draft.allCells))
        expectTrue(draft.undo()); expectEqual(draft.cells.count, 2)
        expectTrue(draft.undo()); expectEqual(draft.cells.count, 1)
        expectTrue(draft.undo()); expectEqual(draft.current.count, 2)
        var full = HandwritingDraft()
        for _ in 0..<HandwritingDraft.limit { try full.append(stroke); try full.finish() }
        expectThrows(try full.append(stroke)); expectTrue(NSImage(data: try full.jpeg()) != nil)
        var requests = 0, questions = 0
        let player = HapticPlayer(startupDelay: 0, output: { _ in })
        let model = AskAIModel(player: player, completion: { _, prompt in
            questions += 1; expectTrue(prompt.contains("H")); return "Hello."
        }, recognition: { _, image in
            requests += 1; expectTrue(NSImage(data: image) != nil)
            try await Task.sleep(nanoseconds: 20_000_000)
            return "{\"text\":\"H\"}"
        })
        let context = LessonQuestionContext(documentID: UUID(), title: "Communication", pageIndex: 0, line: "", pages: [])
        model.prepare(context, handwritingMode: true)
        model.addStroke(stroke); model.addStroke(stroke)
        expectEqual(model.handwriting.current.count, 2)
        model.send(config: AIConfiguration(provider: .gemini, key: "", model: "test"))
        expectEqual(model.phase, .composing); expectTrue(model.handwriting.hasInk)
        model.send(config: config); model.send(config: config)
        expectEqual(model.phase, .waiting)
        try await Task.sleep(nanoseconds: 60_000_000)
        expectEqual(requests, 1); expectEqual(questions, 0); expectEqual(model.recognizedText, "H")
        expectEqual(model.phase, .composing); expectTrue(model.handwriting.hasInk)
        model.review(); expectTrue(player.isPlaying)
        model.send(config: config)
        try await Task.sleep(nanoseconds: 40_000_000)
        expectEqual(questions, 1); expectEqual(model.phase, .answer)
        expectEqual(model.messages.count, 2); expectEqual(model.messages[0].text, "H")
        expectTrue(model.messages[0].isUser); expectFalse(model.messages[1].isUser)
        model.newQuestion(); expectEqual(model.messages.count, 2); expectFalse(model.handwriting.hasInk); expectNil(model.recognizedText)
        model.addStroke(stroke); model.send(config: config); model.suspend()
        try await Task.sleep(nanoseconds: 60_000_000)
        expectEqual(model.phase, .composing); expectNil(model.recognizedText); expectTrue(model.handwriting.hasInk)
        model.prepare(context, handwritingMode: true); expectTrue(model.handwriting.hasInk)
        model.prepare(LessonQuestionContext(documentID: UUID(), title: "New", pageIndex: 0, line: "", pages: []), handwritingMode: true)
        expectFalse(model.handwriting.hasInk)
        let failed = AskAIModel(player: HapticPlayer(output: { _ in }), recognition: { _, _ in throw AppError.message("mock failure") })
        failed.prepare(context, handwritingMode: true); failed.addStroke(stroke); failed.send(config: config)
        try await Task.sleep(nanoseconds: 40_000_000)
        expectEqual(failed.phase, .composing); expectTrue(failed.handwriting.hasInk); expectNil(failed.recognizedText)
        let uncertain = AskAIModel(player: HapticPlayer(output: { _ in }), completion: { _, _ in preconditionFailure("Uncertain text must not be asked") }, recognition: { _, _ in "{\"text\":\"?\"}" })
        uncertain.prepare(context, handwritingMode: true); uncertain.addStroke(stroke); uncertain.send(config: config)
        try await Task.sleep(nanoseconds: 40_000_000)
        uncertain.send(config: config); expectEqual(uncertain.phase, .composing)
        uncertain.undo(); expectNil(uncertain.recognizedText)
        let workspace = Workspace(loadPreferences: false, assistant: model)
        workspace.enterHandwritingMode(); expectTrue(workspace.askMode); expectTrue(workspace.touchMode)
        workspace.exitTouchMode(); expectFalse(workspace.askMode); expectFalse(workspace.touchMode)
        workspace.pages = [LessonPage(id: 0, source: "HI", extraction: "Test")]
        workspace.syncPlayer()
        workspace.activate(.reading); expectTrue(workspace.touchMode); expectFalse(workspace.askMode)
        workspace.activate(.handwriting); expectTrue(workspace.askMode); expectTrue(model.handwritingMode)
        workspace.activate(.morse); expectTrue(workspace.askMode); expectFalse(model.handwritingMode)
        workspace.activate(.practice); expectEqual(workspace.screen, .practice); expectFalse(workspace.touchMode)
        workspace.showTextEntry = true
        workspace.activate(.handwriting); expectFalse(workspace.askMode)
        workspace.showTextEntry = false
        workspace.activate(.handwriting); expectTrue(workspace.askMode)
        workspace.exitTouchMode()
        model.clearConversation()
        expectTrue(model.messages.isEmpty); expectFalse(model.handwriting.hasInk)
        expectNil(model.recognizedText); expectEqual(model.phase, .composing)
        model.suspend(); failed.suspend(); uncertain.suspend()
    }
}
