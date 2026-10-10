import SwiftUI

struct AskAIView: View {
    @ObservedObject var model: Workspace
    @ObservedObject var assistant: AskAIModel
    @ObservedObject var player: HapticPlayer
    let onExit: () -> Void
    @State private var historyIndex = 0

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("luma touch", systemImage: "waveform.path").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Color.ocean)
                    Spacer()
                    Text(assistant.isDemonstration ? "OFFLINE DEMO · NO API CALLS" : assistant.phase == .answer ? "AI REPLY" : assistant.handwritingMode ? "WRITE TO COMMUNICATE" : "DRAW TO ASK")
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(assistant.handwritingMode ? "Chat, in your own handwriting." : assistant.phase == .answer ? "A little clarity." : "A question, in your own touch.")
                            .font(.system(size: 33, weight: .medium)).tracking(-1)
                        Text("\(model.title)  ·  Page \(model.selectedPage + 1)  ·  Line \(model.selectedLine + 1)")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Label(model.provider.rawValue, systemImage: model.provider.symbol).font(.system(size: 12, weight: .semibold))
                        .padding(12).glass(14, solid: model.solid)
                }
                if assistant.handwritingMode { chatContent }
                else if assistant.phase == .answer { answerContent }
                else { composeContent }
                Spacer(minLength: 0)
                gestureGuide
                Text("Two-finger click: back to PDF  ·  Escape: leave touch mode and restore the pointer")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                Text(assistant.phase == .answer
                     ? "AI can make mistakes. Check the explanation against your PDF."
                     : assistant.handwritingMode ? "Space transcribes your drawing. Review the text, then Space sends it to AI with PDF context." : "One click sends your question, recent conversation and relevant extracted PDF text to \(model.provider.rawValue).")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }.padding(32).allowsHitTesting(false).accessibilityHidden(true)
            MorseDrawingSurface(handwriting: assistant.handwritingMode, phase: assistant.phase, value: "\(assistant.compositionText). \(assistant.status)",
                                onStroke: assistant.addStroke, onPreview: { assistant.stroke = $0 }, onCommand: handle)
        }
    }

    private var chatContent: some View {
        VStack(spacing: 14) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if assistant.messages.isEmpty && !assistant.awaitingReply {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30)).foregroundStyle(Color.ocean)
                                Text("What would you like to talk about?").font(.system(size: 22, weight: .medium))
                                Text("Write a message below. Ask a question, talk through an idea, or explore your PDF.")
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(assistant.messages) { message in
                            chatBubble(message.text, user: message.isUser).id(message.id)
                        }
                        if assistant.awaitingReply {
                            chatBubble(assistant.submittedQuestion, user: true)
                            HStack { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }.padding(12)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(18)
                }
                .onChange(of: historyIndex) { _, index in
                    if assistant.messages.indices.contains(index) { proxy.scrollTo(assistant.messages[index].id, anchor: .top) }
                }
                .onChange(of: assistant.messages.count) { _, _ in historyIndex = max(0, assistant.messages.count - 1); proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: assistant.phase) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .onChange(of: assistant.awaitingReply) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).glass(solid: model.solid)
            if assistant.phase == .answer {
                HStack(spacing: 18) {
                    Image(systemName: "waveform").foregroundStyle(Color.ocean)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reply · line \(assistant.answerLine + 1) of \(assistant.answerLines.count)").font(.caption.weight(.semibold))
                        Text(assistant.currentAnswerLine).font(.system(size: 15)).lineLimit(2)
                        Text("Space: play / pause. Return: write your next message.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Write a reply  ↗").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ocean)
                }.padding(18).glass(solid: model.solid)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HANDWRITING PAD").font(.system(size: 10, weight: .bold)).tracking(1)
                        Canvas { context, size in
                            let scale = min(size.width, size.height / 0.7)
                            let offset = (size.width - scale) / 2
                            for stroke in assistant.handwriting.current + [assistant.stroke] {
                                guard let first = stroke.first else { continue }
                                var path = Path()
                                path.move(to: CGPoint(x: offset + first.x * scale, y: size.height - first.y * scale))
                                for p in stroke.dropFirst() { path.addLine(to: CGPoint(x: offset + p.x * scale, y: size.height - p.y * scale)) }
                                if stroke.count == 1 { path.addEllipse(in: CGRect(x: offset + first.x * scale - 2, y: size.height - first.y * scale - 2, width: 4, height: 4)) }
                                context.stroke(path, with: .color(.ocean), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            }
                        }.frame(width: 230, height: 120).background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        Text("\(assistant.handwriting.cells.count) saved · → saves each letter").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(assistant.recognizedText ?? "Write your message…")
                            .font(.system(size: 21, weight: .medium)).foregroundStyle(assistant.recognizedText == nil ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 45, alignment: .topLeading)
                        Text(assistant.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                        HStack {
                            Text("? = uncertain · ← to correct").font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            if assistant.phase == .waiting { ProgressView().controlSize(.small) }
                            else { Label(assistant.recognizedText == nil ? "Space to transcribe" : "Space to send", systemImage: "arrow.up.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ocean) }
                        }
                    }
                }.padding(18).glass(solid: model.solid)
            }
            Text("Fn ↑ / ↓: browse messages · AI remembers last two exchanges · ⌘⇧N: new chat")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func chatBubble(_ text: String, user: Bool) -> some View {
        HStack(alignment: .top) {
            if user { Spacer(minLength: 120) }
            VStack(alignment: .leading, spacing: 6) {
                Text(user ? "YOU" : "LUMA · AI").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(user ? Color.white.opacity(0.8) : Color.ocean)
                Text(text).font(.system(size: 16)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }.padding(16).foregroundStyle(user ? Color.white : Color.primary)
                .background(user ? Color.ocean : Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            if !user { Spacer(minLength: 100) }
        }
    }

    private var composeContent: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Your trackpad is the pen")
                Canvas { context, size in
                    guard let first = assistant.stroke.first else { return }
                    let scale = min(size.width, size.height / 0.7)
                    let offset = (size.width - scale) / 2
                    var path = Path()
                    path.move(to: CGPoint(x: offset + first.x * scale, y: size.height - first.y * scale))
                    for point in assistant.stroke.dropFirst() { path.addLine(to: CGPoint(x: offset + point.x * scale, y: size.height - point.y * scale)) }
                    context.stroke(path, with: .color(.ocean), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }.frame(height: 190).background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if assistant.stroke.isEmpty {
                            VStack(spacing: 13) {
                                Text("·       —").font(.system(size: 48, weight: .light))
                                Text("Light tap = dot   ·   Line = dash").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                HStack {
                    Text("LETTER").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    MorseMarks(code: assistant.draft.pending, size: 9)
                    Spacer()
                    Text(assistant.draft.letter.map(String.init) ?? "·").font(.system(size: 30, weight: .medium, design: .rounded))
                }.frame(height: 38)
                Text("Tap without pressing for a dot.\nSwipe right to finish the letter.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(22).glass(solid: model.solid).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                HStack { Eyebrow(text: "Your question"); Spacer(); Text("\(assistant.draft.text.count) / \(MorseDraft.limit)").font(.caption).foregroundStyle(.secondary) }
                Text(assistant.draft.text.isEmpty ? "Your decoded words appear here." : assistant.draft.text)
                    .font(.system(size: 22, weight: .medium, design: .rounded)).lineSpacing(6).lineLimit(6)
                    .foregroundStyle(assistant.draft.text.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                if !assistant.draft.pending.isEmpty {
                    Text("Current letter: \(assistant.draft.letter.map(String.init) ?? "incomplete") · included when you send")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Divider()
                if assistant.phase == .waiting {
                    HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Thinking with your PDF…").font(.system(size: 16, weight: .medium)) }
                } else {
                    Label("Press to click once and send", systemImage: "paperplane.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.ocean)
                }
                Text(assistant.status).font(.system(size: 13)).lineSpacing(4).lineLimit(4).frame(minHeight: 53, alignment: .topLeading)
                if assistant.isReviewing { ProgressView(value: player.progress).tint(Color.ocean) }
            }.padding(22).glass(solid: model.solid).frame(maxWidth: .infinity)
        }
    }

    private var answerContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("YOU ASKED  ·  \(assistant.submittedQuestion)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Eyebrow(text: "Answer line \(assistant.answerLine + 1) of \(assistant.answerLines.count)")
                Spacer()
                Text(player.current.map { String($0.character) } ?? "✓").font(.system(size: 30, weight: .light, design: .rounded))
                MorseMarks(code: player.current?.code ?? "", active: player.markIndex, size: 8)
            }
            Text(assistant.currentAnswerLine).font(.system(size: 27, weight: .medium, design: .rounded))
                .lineSpacing(7).lineLimit(6).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            ProgressView(value: player.progress).tint(Color.ocean)
            Text(player.isPlaying ? player.status : assistant.status).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            if !Morse.unsupported(assistant.answer).isEmpty {
                Text("Morse cannot express: \(Morse.unsupported(assistant.answer)). These characters are skipped during playback.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(26).glass(solid: model.solid)
    }

    private var gestureGuide: some View {
        HStack(spacing: 15) {
            if assistant.phase == .answer {
                guide("Space", "Play / pause")
                guide("← / →", "Previous / next line")
                guide("↑ / ↓", "Faster / slower")
                guide("Return", "Write next message")
            } else {
                guide("→", "Finish letter")
                guide("↑", "Word space")
                guide("←", "Undo")
                guide("↓", assistant.handwritingMode ? "Feel message" : "Feel question")
            }
        }.padding(20).glass(solid: model.solid)
    }
    private func guide(_ gesture: String, _ meaning: String) -> some View {
        VStack(spacing: 7) { Text(gesture).font(.system(size: 14, weight: .semibold)); Text(meaning).font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
    private func handle(_ command: DrawingCommand) {
        switch command {
        case .previousMessage: historyIndex = max(0, historyIndex - 1)
        case .nextMessage: historyIndex = min(max(0, assistant.messages.count - 1), historyIndex + 1)
        case .dot: assistant.add(.dot)
        case .dash: assistant.add(.dash)
        case .finishLetter: assistant.finishLetter()
        case .space: assistant.addSpace()
        case .undo: assistant.undo()
        case .review: assistant.review()
        case .send: assistant.send(config: model.configuration())
        case .returnToPDF: model.returnFromQuestion()
        case .exit: onExit()
        case .toggleAnswer: assistant.toggleAnswer()
        case .nextAnswer: assistant.moveAnswer(1)
        case .previousAnswer: assistant.moveAnswer(-1)
        case .faster: assistant.changeSpeed(1)
        case .slower: assistant.changeSpeed(-1)
        case .replayAnswer: assistant.replayAnswer()
        case .newQuestion: assistant.newQuestion()
        }
    }
}
