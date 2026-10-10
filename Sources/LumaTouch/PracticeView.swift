import SwiftUI

struct PracticeView: View {
    @ObservedObject var model: Workspace
    @ObservedObject var player: HapticPlayer
    @State private var selected = "E"
    @State private var quiz = false
    @State private var answer = ""
    @State private var result = ""
    @State private var target = "E"
    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Little signals. New possibilities.")
                        Text("Learn to feel the alphabet.").font(.system(size: 34, weight: .medium)).tracking(-1)
                        Text("Start with E and T. Then try a word, one letter at a time.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.openReference() } label: { Label("Morse sheet", systemImage: "doc.text") }.buttonStyle(ActionStyle())
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Eyebrow(text: "The alphabet")
                            Spacer()
                            Text("Tap a letter to feel it").font(.caption).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 6), spacing: 9) {
                            ForEach(letters, id: \.self) { letter in
                                Button {
                                    quiz = false; selected = letter; player.load(letter); player.play()
                                } label: {
                                    VStack(spacing: 9) {
                                        Text(letter).font(.system(size: 22, weight: .medium))
                                        MorseMarks(code: Morse.display(letter), size: 3.8)
                                    }.frame(maxWidth: .infinity).frame(height: 64)
                                        .background(.white.opacity(selected == letter && !quiz ? 0.55 : 0.16), in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected == letter && !quiz ? Color.ocean.opacity(0.6) : .white.opacity(0.3)))
                                }.buttonStyle(.plain).accessibilityLabel("Feel \(letter), \(Morse.display(letter))")
                            }
                        }
                    }.padding(23).frame(maxWidth: .infinity).glass(solid: model.solid)
                    VStack(spacing: 18) {
                        VStack(spacing: 20) {
                            Eyebrow(text: quiz ? "Mystery letter" : "Feel the difference")
                            Text(quiz ? "?" : selected).font(.system(size: 77, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.4)
                                .frame(height: 92)
                            if !quiz { MorseMarks(code: player.current?.code ?? Morse.display(String(selected.prefix(1))), active: player.markIndex, size: 12).frame(height: 16) }
                            else { Text("Feel first. Then choose.").font(.caption).foregroundStyle(.secondary) }
                            Button {
                                if player.isPlaying { player.pause() }
                                else { player.load(quiz ? target : selected); player.play() }
                            } label: { Label(player.isPlaying ? "Pause" : "Feel again", systemImage: player.isPlaying ? "pause.fill" : "hand.point.up.left.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(ActionStyle(prominent: true))
                            if quiz {
                                HStack {
                                    TextField("Your letter", text: $answer).textFieldStyle(.roundedBorder).onSubmit(checkAnswer)
                                        .accessibilityLabel("Your answer to the mystery letter")
                                    Button("Check", action: checkAnswer)
                                }
                                Text(result).font(.caption).frame(minHeight: 25)
                            }
                            Button(quiz ? "Another mystery letter" : "Try a mystery letter") { startQuiz() }.font(.caption)
                        }.padding(25).glass(solid: model.solid)
                        VStack(alignment: .leading, spacing: 12) {
                            Label("First, calibrate your touch", systemImage: "hand.point.up.braille").font(.headline)
                            Text("Keep one finger lightly on the trackpad. A dot is one short pulse. A dash is a longer sequence of pulses.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                            HStack {
                                Button("Feel dot ·") { quiz = false; selected = "E"; player.load("E"); player.play() }
                                Button("Feel dash —") { quiz = false; selected = "T"; player.load("T"); player.play() }
                            }.buttonStyle(ActionStyle())
                            Text("Trackpad approximation · not raised-dot Braille. Your feedback is needed to check whether patterns are distinguishable.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        }.padding(21).glass(solid: model.solid)
                    }.frame(width: 290)
                }
                HStack(spacing: 12) {
                    Text("TRY A WORD").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                    ForEach(["HI", "SOS", "LEARN"], id: \.self) { word in
                        Button(word) { quiz = false; selected = word; player.load(word); player.play() }.buttonStyle(ActionStyle())
                    }
                    Spacer()
                    Text(player.isPlaying && quiz ? "Mystery pattern playing…" : player.status).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(30)
        }.onDisappear { player.stop() }
    }

    private func startQuiz() {
        target = ["E", "T", "A", "N", "I", "M", "S", "O"].randomElement()!
        answer = ""; result = ""; quiz = true
        player.load(target); player.play()
    }
    private func checkAnswer() {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        result = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == target ? "Correct — it was \(target)!" : "Not quite. Feel it again, or try E, T, A, N, I, M, S or O."
    }
}

extension Workspace {
    func openReference() {
        if let url = Bundle.main.url(forResource: "Morse-Reference", withExtension: "pdf") { NSWorkspace.shared.open(url) }
        else {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/Morse-Reference.pdf")
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
            else { error = "The reference sheet is in the project's docs folder." }
        }
    }
}
