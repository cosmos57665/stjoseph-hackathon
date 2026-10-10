import SwiftUI
import PDFKit

struct ReaderView: View {
    @ObservedObject var model: Workspace
    @State private var passage = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Learning, in your own way")
                        Text(model.pages.isEmpty ? "Every lesson.\nA new way to connect." : "A little touch.\nA world to discover.")
                            .font(.system(size: 37, weight: .medium)).tracking(-1.4).lineSpacing(-1)
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
                    HStack(alignment: .top, spacing: 20) {
                        lesson.frame(maxWidth: .infinity, alignment: .topLeading)
                        VStack(spacing: 16) {
                            PlayerPanel(player: model.player, solid: model.solid)
                            VStack(alignment: .leading, spacing: 13) {
                                Eyebrow(text: "One small passage at a time")
                                Picker("Passage", selection: $passage) {
                                    ForEach(Array(model.sentences.enumerated()), id: \.offset) { index, text in
                                        Text("\(index + 1). \(text.prefix(34))…").tag(index)
                                    }
                                }.labelsHidden().accessibilityLabel("Choose passage for Morse playback")
                                    .onChange(of: passage) { _, value in
                                        if model.sentences.indices.contains(value) { model.player.load(model.sentences[value]) }
                                    }
                                Text(model.sentences.indices.contains(passage) ? model.sentences[passage] : "No readable text on this page yet.")
                                    .font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                if !Morse.unsupported(model.visibleText).isEmpty {
                                    Label("Morse skips: \(Morse.unsupported(model.visibleText))", systemImage: "info.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text("Touch mode supports Latin letters, numbers and common punctuation. Original text is preserved.").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.padding(20).glass(solid: model.solid)
                        }.frame(width: 285)
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
            }.padding(30)
        }.onChange(of: model.selectedPage) { _, _ in passage = 0 }
            .onChange(of: model.title) { _, _ in passage = 0 }
            .onChange(of: model.showSimplified) { _, _ in passage = 0 }
    }

    var welcome: some View {
        VStack(spacing: 23) {
            ZStack {
                Circle().fill(.white.opacity(0.25)).frame(width: 125, height: 125)
                Image(systemName: "hand.point.up.braille.fill").font(.system(size: 51, weight: .light)).foregroundStyle(Color.ocean)
            }
            Text("Read it. Hear it. Feel it.").font(.system(size: 26, weight: .medium))
            Text("Turn a PDF into readable text, spoken words, and tactile Morse.\nStart small. A sentence can open a whole new world.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(6)
            HStack(spacing: 13) {
                Button("Open practice PDF") { model.loadStarter() }.buttonStyle(ActionStyle(prominent: true))
                Button("Try sample text", action: model.useSample).buttonStyle(ActionStyle())
            }.disabled(model.busy)
            if model.busy { ProgressView(model.activity) }
            Button("First, feel a dot and a dash") { model.screen = .practice }.buttonStyle(.plain).font(.caption)
        }.frame(maxWidth: .infinity).padding(.vertical, 46).glass(solid: model.solid)
    }

    var lesson: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                Image(systemName: "doc.richtext").font(.system(size: 22)).foregroundStyle(Color.ocean)
                    .frame(width: 45, height: 49).background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
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
            Text(model.visibleText.isEmpty ? "This page needs transcription. Add an AI key in Connections, then choose Transcribe page." : model.visibleText)
                .font(.system(size: model.textSize, weight: .regular, design: .rounded)).lineSpacing(9)
                .frame(maxWidth: .infinity, minHeight: 185, alignment: .topLeading).textSelection(.enabled)
                .accessibilityLabel("Lesson text").accessibilityValue(model.visibleText)
            Divider()
            HStack(spacing: 10) {
                Button(action: model.speak) { Label(model.speaking ? "Stop speech" : "Listen", systemImage: model.speaking ? "stop.fill" : "speaker.wave.2") }
                    .buttonStyle(ActionStyle()).disabled(model.visibleText.isEmpty)
                Button(action: model.simplify) { Label("Simplify", systemImage: "sparkles") }
                    .buttonStyle(ActionStyle()).disabled(model.busy || model.visibleText.isEmpty)
                Spacer(minLength: 0)
                Button { model.textSize = max(15, model.textSize - 2) } label: { Text("A−") }.accessibilityLabel("Decrease text size")
                Button { model.textSize = min(31, model.textSize + 2) } label: { Text("A+") }.accessibilityLabel("Increase text size")
            }
            if model.page?.simplified != nil {
                Toggle("Show simpler explanation", isOn: $model.showSimplified).font(.caption)
                    .onChange(of: model.showSimplified) { _, _ in model.stopAll(); model.syncPlayer() }
            }
            if model.documentURL != nil {
                HStack(spacing: 12) {
                    Menu {
                        Button("Transcribe this page") { model.transcribe(all: false) }
                        Button("Transcribe all remaining pages") { model.transcribe(all: true) }
                    } label: { Label("AI transcription", systemImage: "viewfinder") }.disabled(model.busy)
                    Button("View original") { model.showPDF = true }
                }.font(.caption)
                Text("Transcription sends page images to \(model.provider.rawValue). AI can make mistakes; compare with the original.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }.padding(24).glass(solid: model.solid)
    }
}

struct PlayerPanel: View {
    @ObservedObject var player: HapticPlayer
    var solid: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        VStack(spacing: 17) {
            HStack {
                Eyebrow(text: "Touch player")
                Spacer()
                Circle().fill(player.isPlaying ? Color.orange : Color.ocean.opacity(0.5)).frame(width: 6, height: 6)
            }
            ZStack {
                Circle().stroke(.white.opacity(0.55), lineWidth: 1).frame(width: 128, height: 128)
                Circle().fill(Color.ocean.opacity(player.isPulsing ? 0.19 : 0.06)).frame(width: player.isPulsing && !reduceMotion ? 117 : 102)
                Text(player.current.map { String($0.character) } ?? (player.symbols.isEmpty ? "·" : "✓"))
                    .font(.system(size: 56, weight: .light, design: .rounded))
            }.accessibilityLabel(player.current.map { "Current letter \(String($0.character))" } ?? "Playback finished")
            MorseMarks(code: player.current?.code ?? "", active: player.markIndex, size: 9).frame(height: 12)
            ProgressView(value: player.progress).tint(Color.ocean)
            HStack(spacing: 19) {
                Button { player.skipWord(-1) } label: { Image(systemName: "backward.end.fill") }.help("Previous word").accessibilityLabel("Previous word")
                Button { player.isPlaying ? player.pause() : player.play() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                        .foregroundStyle(.white).frame(width: 52, height: 52).background(Color.ocean, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(player.isPlaying ? "Pause Morse playback" : "Play Morse passage")
                    .disabled(player.symbols.isEmpty)
                Button { player.skipWord(1) } label: { Image(systemName: "forward.end.fill") }.help("Next word").accessibilityLabel("Next word")
            }.buttonStyle(.plain)
            HStack {
                Text("Slower").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $player.unit, in: 0.12...0.45).environment(\.layoutDirection, .rightToLeft)
                    .accessibilityLabel("Morse unit duration").disabled(player.isPlaying)
                Text("Faster").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Text("\(player.duration)s per passage").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Restart") { player.reset() }.font(.system(size: 10))
            }
            Text(player.status).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(minHeight: 31)
            Text("Trackpad pulse approximation · keep a finger in contact")
                .font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(22).glass(solid: solid)
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
