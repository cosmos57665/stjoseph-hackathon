import AppKit
import Foundation

@MainActor final class ReaderControlTests {
    private func workspace(_ sources: [String]) -> Workspace {
        let model = Workspace(loadPreferences: false,
                              player: HapticPlayer(startupDelay: 0, output: { _ in }),
                              practicePlayer: HapticPlayer(startupDelay: 0, output: { _ in }))
        model.showTouchWelcome = false
        model.pages = sources.enumerated().map { LessonPage(id: $0.offset, source: $0.element, extraction: "Test fixture") }
        model.syncPlayer()
        return model
    }

    func testSourceLinesStayIntact() {
        let longLine = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen."
        let model = workspace(["  \(longLine)  \n\n \t\nSecond line.\r\nThird line."])
        expectEqual(model.readingLines, [longLine, "Second line.", "Third line."])
        expectEqual(model.currentLine, longLine)
        expectEqual(model.player.symbols, Morse.encode(longLine))
        model.selectLine(1)
        expectEqual(model.selectedLine, 1)
        expectEqual(model.currentLine, "Second line.")
        expectEqual(model.player.symbols, Morse.encode("Second line."))
        expectFalse(model.player.isPlaying)
        model.selectLine(99)
        expectEqual(model.selectedLine, 1)
        model.selectLine(-1)
        expectEqual(model.selectedLine, 1)
    }

    func testLineNavigationCrossesPagesAndSkipsBlankPages() {
        let model = workspace(["First\nSecond", "", " \n\t", "Third\nFourth", ""])
        model.selectLine(1)
        expectTrue(model.moveLine(1))
        expectEqual(model.selectedPage, 3)
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "Third")
        expectEqual(model.player.symbols, Morse.encode("Third"))
        expectTrue(model.player.isPlaying)
        expectTrue(model.moveLine(-1))
        expectEqual(model.selectedPage, 0)
        expectEqual(model.selectedLine, 1)
        expectEqual(model.currentLine, "Second")
        expectTrue(model.player.isPlaying)
        model.stopAll()
    }

    func testDocumentBoundariesDoNotWrap() {
        let model = workspace(["First\nSecond", "", "Third", " \n"])
        model.toggleReading()
        expectTrue(model.player.isPlaying)
        expectFalse(model.moveLine(-1))
        expectEqual(model.selectedPage, 0)
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "First")
        expectFalse(model.player.isPlaying)
        model.selectPage(2)
        expectFalse(model.moveLine(1))
        expectEqual(model.selectedPage, 2)
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "Third")
        expectFalse(model.player.isPlaying)
        model.stopAll()
    }

    func testEmptyDocumentsAreSafe() {
        for sources in [[String](), ["", " \t\n"]] {
            let model = workspace(sources)
            expectEqual(model.readingLines, [])
            expectEqual(model.currentLine, "")
            expectFalse(model.moveLine(-1))
            expectFalse(model.moveLine(1))
            model.toggleReading()
            model.replayLine()
            expectFalse(model.player.isPlaying)
            expectEqual(model.player.symbols, [])
            model.stopAll()
        }
    }

    func testPageAndTranscriptChangesResetThePlaybackSelection() {
        let model = workspace(["Source one\nSource two\nSource three", "Other page\nLast line"])
        model.selectLine(2)
        model.player.index = 3
        model.pages[0].transcript = "Corrected transcript"
        model.syncPlayer()
        expectEqual(model.selectedLine, 0)
        expectEqual(model.player.index, 0)
        expectEqual(model.currentLine, "Corrected transcript")
        expectEqual(model.player.symbols, Morse.encode("Corrected transcript"))
        model.selectPage(1)
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "Other page")
        model.selectLine(1)
        model.pages[1].simplified = "Simple explanation"
        model.showSimplified = true
        model.syncPlayer()
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "Simple explanation")
        expectEqual(model.player.symbols, Morse.encode("Simple explanation"))
        model.showSimplified = false
        model.syncPlayer()
        expectEqual(model.currentLine, "Other page")
        expectEqual(model.player.symbols, Morse.encode("Other page"))
    }

    func testPastedDocumentResetsPageLineAndPlayer() {
        let model = workspace(["Old page", "Old line\nFinal line"])
        model.selectPage(1)
        model.selectLine(1, autoplay: true)
        model.showTextEntry = true
        model.draft = "  New first\n\nNew second  "
        model.useText()
        expectEqual(model.selectedPage, 0)
        expectEqual(model.selectedLine, 0)
        expectEqual(model.readingLines, ["New first", "New second"])
        expectEqual(model.player.symbols, Morse.encode("New first"))
        expectEqual(model.player.index, 0)
        expectFalse(model.player.isPlaying)
        expectFalse(model.showTextEntry)
    }

    func testModalAndNonReaderStatesCannotKeepHiddenPlayback() {
        let model = workspace(["Read this\nNext line"])
        let modalStates: [(Bool) -> Void] = [
            { model.showPDF = $0 },
            { model.showTextEntry = $0 },
            { model.error = $0 ? "A test error" : nil },
            { model.showControls = $0 },
            { model.showTouchWelcome = $0 },
            { model.busy = $0 }
        ]
        for setState in modalStates {
            model.toggleReading()
            expectTrue(model.player.isPlaying)
            setState(true)
            expectFalse(model.player.isPlaying)
            model.toggleReading()
            model.replayLine()
            expectFalse(model.player.isPlaying)
            setState(false)
        }
        model.toggleReading()
        model.screen = .connections
        expectFalse(model.player.isPlaying)
        model.toggleReading()
        expectFalse(model.player.isPlaying)
        model.stopAll()
    }

    func testTouchModeEntryAndExitStopOtherPlayback() {
        let model = workspace(["Read this"])
        model.practicePlayer.load("T")
        model.practicePlayer.play()
        model.toggleReading()
        model.enterTouchMode()
        expectTrue(model.touchMode)
        expectFalse(model.showTouchWelcome)
        expectEqual(model.screen, .reader)
        expectFalse(model.practicePlayer.isPlaying)
        expectFalse(model.player.isPlaying)
        model.toggleReading()
        expectTrue(model.player.isPlaying)
        model.exitTouchMode()
        expectFalse(model.touchMode)
        expectFalse(model.player.isPlaying)
        expectFalse(model.practicePlayer.isPlaying)
    }

    func testTouchModeEntryIsBlockedDuringLoadingAndModalTasks() {
        let model = workspace(["Read this"])
        let blockedStates: [(Bool) -> Void] = [
            { model.busy = $0 },
            { model.showPDF = $0 },
            { model.showTextEntry = $0 },
            { model.error = $0 ? "A test error" : nil }
        ]
        for setState in blockedStates {
            setState(true)
            model.showTouchWelcome = true
            let status = model.player.status
            model.enterTouchMode()
            expectFalse(model.touchMode)
            expectTrue(model.showTouchWelcome)
            expectEqual(model.player.status, status)
            setState(false)
        }
        model.enterTouchMode()
        expectTrue(model.touchMode)
        expectFalse(model.showTouchWelcome)
        model.exitTouchMode()
        model.showControls = true
        model.enterTouchMode()
        expectTrue(model.touchMode)
        expectFalse(model.showControls)
        model.stopAll()
    }

    func testStartupLoadingKeepsWelcomeButLaterLoadingReleasesTouchMode() {
        let model = Workspace(loadPreferences: false,
                              player: HapticPlayer(startupDelay: 0, output: { _ in }),
                              practicePlayer: HapticPlayer(startupDelay: 0, output: { _ in }))
        expectTrue(model.showTouchWelcome)
        model.busy = true
        expectTrue(model.showTouchWelcome)
        expectFalse(model.touchMode)
        model.enterTouchMode()
        expectTrue(model.showTouchWelcome)
        expectFalse(model.touchMode)
        model.pages = [LessonPage(id: 0, source: "Read this", extraction: "Test fixture")]
        model.syncPlayer()
        model.busy = false
        expectTrue(model.showTouchWelcome)
        model.enterTouchMode()
        model.toggleReading()
        expectTrue(model.touchMode)
        expectTrue(model.player.isPlaying)
        model.busy = true
        expectFalse(model.touchMode)
        expectFalse(model.player.isPlaying)
        expectFalse(model.showTouchWelcome)
        model.stopAll()
    }

    func testSpeedIsBoundedAndKeepsCurrentLetter() {
        let model = workspace(["ET"])
        model.player.index = 1
        model.player.unit = 0.22
        model.changeSpeed(1)
        expectTrue(model.player.unit < 0.22)
        expectEqual(model.player.index, 1)
        for _ in 0..<30 { model.changeSpeed(1) }
        expectTrue(abs(model.player.unit - 0.12) < 0.000001)
        for _ in 0..<30 { model.changeSpeed(-1) }
        expectTrue(abs(model.player.unit - 0.45) < 0.000001)
        expectEqual(model.player.index, 1)
        model.stopAll()
    }

    func testPauseAndResumeKeepCurrentLetterAndCancelPendingPulses() async {
        var outputCount = 0
        let player = HapticPlayer(startupDelay: 0, output: { _ in outputCount += 1 })
        player.unit = 0.04
        player.load("ET")
        player.play()
        await waitUntil { player.index == 1 && player.isPulsing }
        expectEqual(player.current?.character, "T")
        player.pause()
        let pausedOutput = outputCount
        expectFalse(player.isPlaying)
        expectFalse(player.isPulsing)
        expectEqual(player.index, 1)
        try? await Task.sleep(nanoseconds: 160_000_000)
        expectEqual(outputCount, pausedOutput)
        player.play()
        await waitUntil { outputCount > pausedOutput }
        expectEqual(player.index, 1)
        expectEqual(player.current?.character, "T")
        expectEqual(player.markIndex, 0)
        player.stop()
    }

    func testFinishingLineWaitsForNavigationAndReplayRestartsIt() async {
        let model = workspace(["E\nT"])
        model.player.unit = 0.01
        model.toggleReading()
        await waitUntil { !model.player.isPlaying }
        expectEqual(model.selectedLine, 0)
        expectEqual(model.currentLine, "E")
        expectEqual(model.player.index, model.player.symbols.count)
        model.replayLine()
        expectEqual(model.player.index, 0)
        expectTrue(model.player.isPlaying)
        model.pauseReading()
        expectFalse(model.player.isPlaying)
        expectTrue(model.moveLine(1))
        expectEqual(model.selectedLine, 1)
        expectEqual(model.currentLine, "T")
        expectTrue(model.player.isPlaying)
        model.stopAll()
    }

    func testReplacingTextCancelsOldPlayerTask() async {
        var outputCount = 0
        let player = HapticPlayer(startupDelay: 0, output: { _ in outputCount += 1 })
        player.unit = 0.02
        player.load("HHHH")
        player.play()
        await waitUntil { outputCount > 0 }
        player.load("E")
        expectEqual(player.index, 0)
        expectFalse(player.isPlaying)
        let beforeNewPlayback = outputCount
        player.play()
        await waitUntil { !player.isPlaying }
        expectEqual(player.symbols, Morse.encode("E"))
        expectEqual(player.index, 1)
        expectEqual(outputCount, beforeNewPlayback + 1)
        expectFalse(player.isPulsing)
        player.stop()
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        expectTrue(condition())
    }

    func testAccessToolsReleasePointerAndGuardOtherModes() {
        let model = workspace(["HELLO"])
        model.enterTouchMode()
        expectTrue(model.touchMode)
        model.openAccessTool(.spoken)
        expectEqual(model.accessTool, .spoken)
        expectFalse(model.touchMode)
        expectFalse(model.player.isPlaying)
        expectFalse(model.readingControlsAvailable)
        expectFalse(model.canActivateFeature)
        model.enterHandwritingMode()
        model.enterTouchMode()
        expectFalse(model.askMode)
        expectFalse(model.touchMode)
        model.openAccessTool(.visual)
        expectEqual(model.accessTool, .spoken)
        model.accessTool = nil
        model.openAccessTool(.visual)
        expectEqual(model.accessTool, .visual)
        model.accessTool = nil
        model.showTextEntry = true
        model.openAccessTool(.spoken)
        expectNil(model.accessTool)
    }

    func run() async {
        testAccessToolsReleasePointerAndGuardOtherModes()
        testSourceLinesStayIntact()
        testLineNavigationCrossesPagesAndSkipsBlankPages()
        testDocumentBoundariesDoNotWrap()
        testEmptyDocumentsAreSafe()
        testPageAndTranscriptChangesResetThePlaybackSelection()
        testPastedDocumentResetsPageLineAndPlayer()
        testModalAndNonReaderStatesCannotKeepHiddenPlayback()
        testTouchModeEntryAndExitStopOtherPlayback()
        testTouchModeEntryIsBlockedDuringLoadingAndModalTasks()
        testStartupLoadingKeepsWelcomeButLaterLoadingReleasesTouchMode()
        testSpeedIsBoundedAndKeepsCurrentLetter()
        await testPauseAndResumeKeepCurrentLetterAndCancelPendingPulses()
        await testFinishingLineWaitsForNavigationAndReplayRestartsIt()
        await testReplacingTextCancelsOldPlayerTask()
    }
}
