import SwiftUI

@main struct LumaTouchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model: Workspace
    init() {
        let verifying = CommandLine.arguments.contains("--verify-ui")
        let assistant: AskAIModel? = verifying ? AskAIModel(player: HapticPlayer(output: { _ in }), isDemonstration: true, completion: { _, prompt in
            let data = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as! [String: Any]
            precondition(["WHY", "HI"].contains(data["learner_question"] as? String ?? ""))
            precondition(data["document_excerpts"] != nil)
            try await Task.sleep(nanoseconds: 500_000_000)
            return "Demo reply. Your question is linked to the current PDF passage.\nThis response is simulated for testing, with no API request."
        }, recognition: { _, image in
            precondition(NSImage(data: image) != nil)
            try await Task.sleep(nanoseconds: 200_000_000)
            return "{\"text\":\"HI\"}"
        }) : nil
        _model = StateObject(wrappedValue: Workspace(loadPreferences: !verifying, assistant: assistant))
    }
    var body: some Scene {
        WindowGroup("Luma Touch") {
            ContentView(model: model)
                .frame(minWidth: 1070, minHeight: 770)
                .preferredColorScheme(model.dark ? .dark : .light)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if model.pages.isEmpty { model.loadStarter() }
                    if CommandLine.arguments.contains("--verify-ui") { verifyUI() }
                }
        }
        .defaultSize(width: 1190, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Import PDF…", action: model.importPDF).keyboardShortcut("o", modifiers: .command).disabled(model.busy) }
            CommandMenu("Playback") {
                Button("New communication chat") { model.assistant.clearConversation() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!model.askMode)
                Button("Write to communicate", action: model.enterHandwritingMode).keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Ask AI about this PDF", action: model.enterAskMode).keyboardShortcut("a", modifiers: [.command, .shift]).disabled(!model.readingControlsAvailable || model.pages.isEmpty)
                Button("Enter touch mode", action: model.enterTouchMode).keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.busy || model.showTextEntry || model.showPDF || model.error != nil)
                Button("Exit touch mode", action: model.exitTouchMode).keyboardShortcut(.escape, modifiers: []).disabled(!model.touchMode && !model.showTouchWelcome)
                Button("Play / Pause", action: model.toggleReading).keyboardShortcut("p", modifiers: [.command]).disabled(!model.readingControlsAvailable)
                Button("Stop all playback") { model.stopAll() }.keyboardShortcut(".", modifiers: [.command])
                Button("Previous line") { model.moveLine(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option]).disabled(!model.readingControlsAvailable)
                Button("Next line") { model.moveLine(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option]).disabled(!model.readingControlsAvailable)
            }
            CommandGroup(replacing: .help) {
                Button("Touch controls guide") { model.showControls = true }
                Button("Morse reference sheet", action: model.openReference)
            }
        }
    }

    // Deterministic local UI verification without touching keys or sending requests.
    private func verifyUI() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while model.busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("verification")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            @MainActor func snapshot(_ name: String) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                // Capture the composited window, not a costly software redraw of
                // every translucent layer. Restrict capture to this app's window.
                try? String(window.windowNumber).write(to: dir.appendingPathComponent("window-id.txt"), atomically: true, encoding: .utf8)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-o", "-l", String(window.windowNumber), dir.appendingPathComponent(name + ".png").path]
                try? process.run()
                process.waitUntilExit()
            }
            @MainActor func click(_ count: Int) {
                guard let window = NSApp.keyWindow, let content = window.contentView else { return }
                let point = content.convert(NSPoint(x: content.bounds.midX, y: content.bounds.midY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1) { window.sendEvent(event) }
                }
            }
            @MainActor func key(_ code: UInt16, _ character: String) {
                guard let window = NSApp.keyWindow,
                      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, characters: character, charactersIgnoringModifiers: character,
                                                  isARepeat: false, keyCode: code) else { return }
                window.sendEvent(event)
            }
            var checks: [String: Bool] = ["welcomeSurvivesImport": model.showTouchWelcome]
            snapshot("touch-welcome")
            click(1); click(2)
            checks["twoClicksDoNotEnter"] = model.showTouchWelcome && !model.touchMode
            click(3)
            try? await Task.sleep(nanoseconds: 700_000_000)
            checks["tripleClickEnters"] = model.touchMode && !model.player.isPlaying
            snapshot("touch-reader")
            key(49, " ")
            checks["spaceStarts"] = model.player.isPlaying
            click(2)
            checks["doubleClickPauses"] = !model.player.isPlaying
            key(53, "\u{1b}")
            try? await Task.sleep(nanoseconds: 300_000_000)
            checks["escapeExits"] = !model.touchMode && !model.showTouchWelcome && !model.player.isPlaying
            snapshot("reader")
            model.enterTouchMode()
            try? await Task.sleep(nanoseconds: 300_000_000)
            click(3)
            try? await Task.sleep(nanoseconds: 300_000_000)
            checks["readerTripleOpensAI"] = model.askMode && model.touchMode
            for character in "WHY" {
                for mark in Morse.alphabet[character]! { key(mark == "." ? 47 : 27, String(mark)) }
                key(124, "")
            }
            checks["drawnMorseDecodesQuestion"] = model.assistant.draft.text == "WHY"
            snapshot("ask-draft")
            model.dark = true
            try? await Task.sleep(nanoseconds: 300_000_000)
            snapshot("ask-draft-dark")
            model.dark = false
            click(1)
            checks["tapClickDoesNotSend"] = model.assistant.phase == .composing
            @MainActor func drawingSurface(_ view: NSView) -> MorseDrawingNSView? {
                if let drawing = view as? MorseDrawingNSView { return drawing }
                for child in view.subviews { if let drawing = drawingSurface(child) { return drawing } }
                return nil
            }
            // The transport is injected above. This placeholder never leaves the process.
            model.keys[model.provider] = "verification-placeholder-not-a-key"
            if let content = NSApp.keyWindow?.contentView { drawingSurface(content)?.receivedPressure(stage: 1) }
            click(1)
            checks["physicalClickStartsOneQuestion"] = model.assistant.phase == .waiting
            model.keys[model.provider] = ""
            try? await Task.sleep(nanoseconds: 800_000_000)
            checks["simulatedAnswerReady"] = model.assistant.phase == .answer && !model.assistant.player.isPlaying
            snapshot("ask-answer")
            key(49, " ")
            checks["answerCanPlay"] = model.assistant.player.isPlaying
            key(124, "")
            checks["answerLineNavigation"] = model.assistant.answerLine == 1
            let savedLine = model.selectedLine
            model.returnFromQuestion()
            checks["returnKeepsPDFPosition"] = !model.askMode && model.selectedLine == savedLine && model.touchMode
            key(53, "\u{1b}")
            try? await Task.sleep(nanoseconds: 300_000_000)
            model.enterHandwritingMode()
            try? await Task.sleep(nanoseconds: 300_000_000)
            checks["handwritingCapturesPointer"] = model.touchMode && model.askMode && model.assistant.handwritingMode
            let h: [[CGPoint]] = [[CGPoint(x: 0.25, y: 0.2), CGPoint(x: 0.25, y: 0.5)], [CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.5, y: 0.5)], [CGPoint(x: 0.25, y: 0.35), CGPoint(x: 0.5, y: 0.35)]]
            for stroke in h { model.assistant.addStroke(stroke) }
            model.assistant.finishLetter()
            model.assistant.addStroke([CGPoint(x: 0.4, y: 0.2), CGPoint(x: 0.4, y: 0.5)])
            snapshot("handwriting-draft")
            model.keys[model.provider] = "verification-placeholder-not-a-key"
            key(36, "\r")
            try? await Task.sleep(nanoseconds: 500_000_000)
            checks["handwritingTranscribesWithoutAsking"] = model.assistant.recognizedText == "HI" && model.assistant.phase == .composing
            snapshot("handwriting-message")
            key(125, "")
            checks["handwritingReviewPlays"] = model.assistant.player.isPlaying
            key(36, "\r")
            try? await Task.sleep(nanoseconds: 800_000_000)
            checks["chatShowsExchange"] = model.assistant.messages.count == 4 && model.assistant.phase == .answer
            snapshot("handwriting-chat")
            key(0, "a")
            checks["chatFollowupKeepsHistory"] = model.assistant.phase == .composing && model.assistant.messages.count == 4
            snapshot("handwriting-followup")
            model.keys[model.provider] = ""
            key(53, "\u{1b}")
            try? await Task.sleep(nanoseconds: 300_000_000)
            checks["handwritingEscapeReleases"] = !model.touchMode && !model.askMode
            model.showControls = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            snapshot("controls-guide")
            model.showControls = false
            try? await Task.sleep(nanoseconds: 300_000_000)
            model.screen = .practice
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("practice")
            model.screen = .connections
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("connections")
            model.dark = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("connections-dark")
            model.dark = false
            model.screen = .reader
            let result: [String: Any] = ["pages": model.pages.count, "title": model.title, "morseSymbols": model.player.symbols.count,
                                       "providers": Provider.allCases.map(\.rawValue), "networkRequests": 0, "touchChecks": checks]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) { try? data.write(to: dir.appendingPathComponent("ui-result.json")) }
            model.stopAll()
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @ObservedObject var model: Workspace
    @State private var pointer = PointerCapture()
    @State private var centeredWelcome = false
    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").font(.system(size: 23, weight: .medium)).foregroundStyle(Color.ocean)
                    Text("luma").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("TOUCH").font(.system(size: 9, weight: .bold)).tracking(2.5).foregroundStyle(.secondary).padding(.leading, 1)
                    Spacer()
                    Text("A different way to learn.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 8)
                    Button { model.dark.toggle() } label: { Image(systemName: model.dark ? "sun.max" : "moon") }.buttonStyle(.plain).help("Toggle light and dark appearance").accessibilityLabel("Toggle light and dark appearance")
                    Button { model.solid.toggle() } label: { Image(systemName: model.solid ? "square.fill" : "square.lefthalf.filled") }.buttonStyle(.plain).help("Toggle solid surfaces").accessibilityLabel("Toggle solid surfaces")
                }.padding(.horizontal, 34).padding(.top, 31).padding(.bottom, 20)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "Your space").padding(.bottom, 13).padding(.leading, 11)
                        ForEach(Screen.allCases, id: \.self) { screen in
                            Button {
                                model.stopAll()
                                model.screen = screen
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: screen.icon).font(.system(size: 16)).frame(width: 21)
                                    Text(screen.rawValue).font(.system(size: 13, weight: model.screen == screen ? .semibold : .regular)).fixedSize()
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 12).padding(.vertical, 13)
                                    .background(.white.opacity(model.screen == screen ? 0.40 : 0), in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain).accessibilityAddTraits(model.screen == screen ? [.isSelected] : [])
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "hand.point.up.braille").font(.system(size: 24)).foregroundStyle(Color.ocean)
                            Text("Small signals.\nMeaningful learning.").font(.system(size: 13, weight: .medium)).lineSpacing(4)
                            Text("An inclusive learning prototype. Built for curiosity.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        }.padding(.horizontal, 10).padding(.bottom, 20)
                        Divider()
                        Button { model.screen = .connections } label: {
                            HStack(spacing: 7) {
                                Circle().fill(model.activeKey ? Color.green : Color.orange).frame(width: 6, height: 6)
                                Text(model.activeKey ? "\(model.provider.rawValue) key ready" : "Offline mode").font(.system(size: 11))
                            }.padding(10)
                        }.buttonStyle(.plain)
                    }.padding(16).frame(width: 184)
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 1)
                    Group {
                        switch model.screen {
                        case .reader: ReaderView(model: model)
                        case .practice: PracticeView(model: model, player: model.practicePlayer)
                        case .connections: ConnectionsView(model: model)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.glass(25, solid: model.solid).padding(.horizontal, 24)
                HStack(spacing: 5) {
                    ForEach(Screen.allCases, id: \.self) { screen in
                        DockButton(icon: screen.icon, title: screen.rawValue, selected: model.screen == screen) { model.stopAll(); model.screen = screen }
                    }
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 31).padding(.horizontal, 5)
                    DockButton(icon: "doc.text", title: "Morse sheet", selected: false, action: model.openReference)
                }.padding(7).glass(24, solid: model.solid).padding(.vertical, 18)
            }.disabled(model.touchMode || model.showTouchWelcome)
                .allowsHitTesting(!model.touchMode && !model.showTouchWelcome)
                .accessibilityHidden(model.touchMode || model.showTouchWelcome)
            if model.touchMode || model.showTouchWelcome {
                if model.askMode {
                    AskAIView(model: model, assistant: model.assistant, player: model.assistant.player) { handleTouchCommand(.exitTouchMode) }
                } else {
                    TouchReadingView(model: model, player: model.player, onCommand: handleTouchCommand)
                }
            }
        }.tint(Color.ocean)
            .onAppear {
                pointer.onInterruption = { model.exitTouchMode(); model.stopAll() }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if !centeredWelcome, model.showTouchWelcome, let window = NSApp.keyWindow {
                        centeredWelcome = pointer.centerPointer(in: window)
                    }
                }
            }
            .onChange(of: model.touchMode) { _, active in
                if active {
                    guard let window = NSApp.keyWindow, pointer.capture(in: window) else {
                        model.exitTouchMode()
                        model.error = pointer.failureMessage ?? "Activate the reading window and try touch mode again."
                        return
                    }
                } else { pointer.release() }
                if CommandLine.arguments.contains("--verify-ui") {
                    let line = "\(active ? "enter" : "exit"): captured=\(pointer.isCaptured)\n"
                    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("verification/pointer-capture.txt")
                    let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    try? (previous + line).write(to: url, atomically: true, encoding: .utf8)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                pointer.release()
                if model.touchMode { model.exitTouchMode() }
                model.stopAll()
            }
            .onDisappear { pointer.release(); model.stopAll() }
            .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .sheet(isPresented: $model.showPDF) {
                VStack(spacing: 12) {
                    HStack { Text("Original PDF").font(.headline); Spacer(); Button("Done") { model.showPDF = false } }
                    if let url = model.documentURL { OriginalPDF(url: url, page: model.selectedPage) }
                }.padding(20).frame(width: 760, height: 760)
            }
            .sheet(isPresented: $model.showTextEntry) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your words, made tactile.").font(.title2.weight(.medium))
                    Text("Paste a short passage to read, listen to, or feel. This stays on your Mac.").foregroundStyle(.secondary)
                    TextEditor(text: $model.draft).font(.system(size: 17)).frame(height: 240).accessibilityLabel("Lesson text to import")
                    HStack { Button("Cancel") { model.showTextEntry = false }; Spacer(); Button("Open in reader", action: model.useText).buttonStyle(ActionStyle(prominent: true)).disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(30).frame(width: 630)
            }
            .sheet(isPresented: $model.showControls) { ControlsGuideView() }
    }

    private func handleTouchCommand(_ command: TouchCommand) {
        switch command {
        case .enterTouchMode: model.enterTouchMode()
        case .exitTouchMode: pointer.release(); model.exitTouchMode()
        case .togglePlayback: model.toggleReading()
        case .nextLine: model.moveLine(1)
        case .previousLine: model.moveLine(-1)
        case .replayLine: model.replayLine()
        case .faster: model.changeSpeed(1)
        case .slower: model.changeSpeed(-1)
        case .pause: model.pauseReading()
        case .askQuestion: model.enterAskMode()
        }
    }
}
