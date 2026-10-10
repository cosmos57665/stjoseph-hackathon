import SwiftUI
import PDFKit

struct ReaderView: View {
    @ObservedObject var model: Workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Learning, in your own way")
                        Text("Read at your pace")
                            .font(.system(size: 30, weight: .medium)).tracking(-1).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Button(action: model.importPDF) { Label("Import a PDF", systemImage: "plus").padding(.horizontal, 5) }
                            .buttonStyle(ActionStyle(prominent: true)).disabled(model.busy).keyboardShortcut("o", modifiers: .command)
                        Button("or paste your own text") { model.showTextEntry = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).disabled(model.busy)
                    }
                }
                if model.pages.isEmpty { welcome }
                else {
                    HStack(alignment: .top, spacing: 18) {
                        lesson.frame(maxWidth: .infinity, alignment: .topLeading)
                        PlayerPanel(model: model).frame(width: 280)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "lock").foregroundStyle(Color.ocean)
                        Text(model.busy ? model.activity : model.activity.isEmpty ? "Import stays on your Mac. AI transcription sends page images to \(model.provider.rawValue) when you choose it." : model.activity)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        if model.busy {
                            ProgressView().controlSize(.small)
                            if model.activity.contains("transcribing") || model.activity.contains("explanation") {
                                Button("Cancel", action: model.cancelAI).font(.caption)
                            }
                        }
                    }.padding(.horizontal, 5)
                }
            }.padding(24)
        }
    }

    var welcome: some View {
        VStack(spacing: 23) {
            ZStack {
                Circle().fill(.white.opacity(0.25)).frame(width: 125, height: 125)
                Image(systemName: "hand.point.up.braille.fill").font(.system(size: 51, weight: .light)).foregroundStyle(Color.ocean)
            }
            Text("Read it. Hear it. Feel it.").font(.system(size: 26, weight: .medium))
            Text("Turn a PDF into readable text, spoken words, and tactile Morse.\nRead one line, pause, and move forward when you are ready.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(6)
            HStack(spacing: 13) {
                Button("Open practice PDF") { model.loadStarter() }.buttonStyle(ActionStyle(prominent: true))
                Button("Try sample text", action: model.useSample).buttonStyle(ActionStyle())
            }.disabled(model.busy)
            if model.busy { ProgressView(model.activity) }
            Button("First, feel a dot and a dash") { model.screen = .practice }.buttonStyle(.plain).font(.caption)
            Button("View all controls") { model.showControls = true }.buttonStyle(.plain).font(.caption)
        }.frame(maxWidth: .infinity).padding(.vertical, 46).glass(solid: model.solid)
    }

    var lesson: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "doc.richtext").font(.system(size: 22)).foregroundStyle(Color.ocean)
                    .frame(width: 40, height: 43).background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Text("\(model.pages.count) page\(model.pages.count == 1 ? "" : "s")  ·  \(model.wordCount) words on this page")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: model.exportText) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain).help("Export all page transcripts").accessibilityLabel("Export all page transcripts")
            }
            HStack {
                Picker("Page", selection: Binding(get: { model.selectedPage }, set: model.selectPage)) {
                    ForEach(model.pages) { page in Text("Page \(page.id + 1)").tag(page.id) }
                }.frame(maxWidth: 130).disabled(model.busy)
                Spacer()
                Text(model.showSimplified ? "AI EXPLANATION" : model.page?.transcript != nil ? "AI TRANSCRIPT" : (model.page?.extraction ?? "").uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(1)
                    .padding(.horizontal, 9).padding(.vertical, 6).background(.white.opacity(0.35), in: Capsule())
            }
            Divider()
            HStack {
                Text("Choose a line to read").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(model.readingLines.count) lines").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            lineReader
            Divider()
            HStack(spacing: 8) {
                Button(action: model.speak) { Label(model.speaking ? "Stop speech" : "Listen", systemImage: model.speaking ? "stop.fill" : "speaker.wave.2") }
                    .buttonStyle(ActionStyle()).disabled(model.visibleText.isEmpty)
                Spacer(minLength: 0)
                Button { model.textSize = max(15, model.textSize - 2) } label: { Text("A−") }.accessibilityLabel("Decrease text size")
                Button { model.textSize = min(31, model.textSize + 2) } label: { Text("A+") }.accessibilityLabel("Increase text size")
            }
            if model.page?.simplified != nil {
                Toggle("Show simpler explanation", isOn: Binding(get: { model.showSimplified }, set: { value in
                    model.stopAll()
                    model.showSimplified = value
                    model.syncPlayer()
                })).font(.caption)
            }
            HStack(spacing: 10) {
                Button(action: model.simplify) { Label("Simplify", systemImage: "sparkles") }
                    .disabled(model.busy || model.visibleText.isEmpty)
                if model.documentURL != nil {
                    Menu {
                        Button("Transcribe this page") { model.transcribe(all: false) }
                        Button("Transcribe all remaining pages") { model.transcribe(all: true) }
                    } label: { Label("AI transcription", systemImage: "viewfinder") }.disabled(model.busy)
                    Button("View original") { model.showPDF = true }
                }
            }.font(.caption)
            if model.documentURL != nil {
                Text("Transcription sends page images to \(model.provider.rawValue). AI can make mistakes; compare with the original.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
            if !Morse.unsupported(model.visibleText).isEmpty {
                Text("Morse skips: \(Morse.unsupported(model.visibleText)). Original text stays unchanged.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }.padding(20).glass(solid: model.solid)
    }

    private var lineReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.readingLines.isEmpty {
                    Text("This page needs transcription. Add an AI key in Connections, then choose AI transcription.")
                        .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } else {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(model.readingLines.enumerated()), id: \.offset) { index, text in
                            Button { model.selectLine(index) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(index == model.selectedLine ? Color.ocean : Color.secondary)
                                        .frame(width: 19, alignment: .trailing).padding(.top, 5)
                                    Text(text).font(.system(size: model.textSize, design: .rounded)).lineSpacing(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(11)
                                    .background(Color.ocean.opacity(index == model.selectedLine ? 0.13 : 0.035), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ocean.opacity(index == model.selectedLine ? 0.38 : 0), lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).disabled(model.busy)
                                .accessibilityLabel("Line \(index + 1). \(text)")
                                .accessibilityValue(index == model.selectedLine ? "Selected for touch playback" : "")
                                .accessibilityAddTraits(index == model.selectedLine ? [.isSelected] : [])
                                .id(index)
                        }
                    }.padding(.trailing, 4)
                }
            }.frame(height: 220)
                .onAppear { proxy.scrollTo(model.selectedLine, anchor: .center) }
                .onChange(of: model.selectedLine) { _, value in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                }
                .onChange(of: model.selectedPage) { _, _ in proxy.scrollTo(model.selectedLine, anchor: .center) }
                .onChange(of: model.visibleText) { _, _ in proxy.scrollTo(model.selectedLine, anchor: .center) }
        }
    }
}

struct PlayerPanel: View {
    @ObservedObject var model: Workspace
    @ObservedObject var player: HapticPlayer
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    init(model: Workspace) {
        self.model = model
        self.player = model.player
    }

    var body: some View {
        VStack(spacing: 13) {
            HStack {
                Eyebrow(text: "One line at a time")
                Spacer()
                Circle().fill(player.isPlaying ? Color.orange : Color.ocean.opacity(0.5)).frame(width: 6, height: 6)
            }
            Text(model.lineLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 13) {
                ZStack {
                    Circle().stroke(.white.opacity(0.55), lineWidth: 1).frame(width: 65, height: 65)
                    Circle().fill(Color.ocean.opacity(player.isPulsing ? 0.19 : 0.06)).frame(width: player.isPulsing && !reduceMotion ? 61 : 54)
                    Text(player.current.map { String($0.character) } ?? (player.symbols.isEmpty ? "·" : "✓"))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                }.accessibilityLabel(player.current.map { "Current letter \(String($0.character))" } ?? "Playback finished")
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.currentLine.isEmpty ? "Choose a readable line" : model.currentLine)
                        .font(.system(size: 13, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    MorseMarks(code: player.current?.code ?? "", active: player.markIndex, size: 6).frame(height: 8)
                }
            }
            ProgressView(value: player.progress).tint(Color.ocean)
            HStack(spacing: 10) {
                Button { model.moveLine(-1) } label: { Image(systemName: "backward.end.fill").frame(width: 34, height: 40) }
                    .buttonStyle(.plain).help("Read previous line").accessibilityLabel("Read previous line")
                Button(action: model.toggleReading) {
                    Label(player.isPlaying ? "Pause" : "Play line", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(ActionStyle(prominent: true)).accessibilityLabel(player.isPlaying ? "Pause Morse playback" : "Play current line")
                    .disabled(player.symbols.isEmpty)
                Button { model.moveLine(1) } label: { Image(systemName: "forward.end.fill").frame(width: 34, height: 40) }
                    .buttonStyle(.plain).help("Read next line").accessibilityLabel("Read next line")
            }.disabled(model.busy || model.readingLines.isEmpty)
            HStack {
                Text("\(player.duration)s for this line").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Replay line", action: model.replayLine).font(.system(size: 11)).disabled(player.symbols.isEmpty || model.busy)
            }
            Text(player.status).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(3).frame(minHeight: 31)
            Divider()
            Button(action: model.enterTouchMode) {
                Label("Enter touch mode", systemImage: "hand.draw.fill").frame(maxWidth: .infinity)
            }.buttonStyle(ActionStyle(prominent: true)).disabled(model.busy || model.readingLines.isEmpty)
            Text("Double-click to pause. Swipe to change lines.\nEscape brings the pointer back.")
                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
            Button(action: model.enterAskMode) {
                Label("Draw a question for AI", systemImage: "pencil.and.scribble").frame(maxWidth: .infinity)
            }.buttonStyle(ActionStyle()).disabled(model.busy)
            HStack {
                Button { model.changeSpeed(-1) } label: { Label("Slower", systemImage: "minus") }
                Spacer(minLength: 4)
                Text("\(Int(player.unit * 1000)) ms").monospacedDigit().foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { model.changeSpeed(1) } label: { Label("Faster", systemImage: "plus") }
            }.font(.system(size: 10)).disabled(model.busy || player.symbols.isEmpty)
            Button("View all controls") { model.showControls = true }.font(.system(size: 11))
        }.padding(19).glass(solid: model.solid)
    }
}

struct OriginalPDF: NSViewRepresentable {
    let url: URL
    let page: Int
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(url: url); return view }
    func updateNSView(_ view: PDFView, context: Context) { if let target = view.document?.page(at: page) { view.go(to: target) } }
}

extension Workspace {
    func loadStarter() {
        if let url = Bundle.main.url(forResource: "Start-Here-Practice", withExtension: "pdf") { loadPDF(url) }
        else {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/Start-Here-Practice.pdf")
            if FileManager.default.fileExists(atPath: url.path) { loadPDF(url) } else { useSample() }
        }
    }
}
