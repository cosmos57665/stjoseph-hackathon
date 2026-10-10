import SwiftUI

struct TouchReadingView: View {
    @ObservedObject var model: Workspace
    @ObservedObject var player: HapticPlayer
    let onCommand: (TouchCommand) -> Void
    var welcoming: Bool { model.showTouchWelcome }

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 14) {
                HStack {
                    Label("luma touch", systemImage: "waveform.path").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(welcoming ? "WELCOME" : "TOUCH MODE").font(.system(size: 10, weight: .bold)).tracking(2)
                }.foregroundStyle(Color.ocean)
                Spacer(minLength: 0)
                if welcoming {
                    Image(systemName: "hand.point.up.braille.fill").font(.system(size: 58, weight: .light)).foregroundStyle(Color.ocean)
                    Text("Your touch. Your pace.").font(.system(size: 42, weight: .medium)).tracking(-1.5)
                    Text("Press Space to begin.").font(.system(size: 26, weight: .medium))
                    Text("Or click three times, up to one second apart.\nKeep the pointer over this window until it disappears.")
                        .font(.system(size: 17)).foregroundStyle(.secondary).lineSpacing(6).multilineTextAlignment(.center)
                    if model.busy { ProgressView(model.activity) }
                    else { Label("Practice PDF ready · no API key needed", systemImage: "doc.text").font(.system(size: 13)).foregroundStyle(.secondary) }
                } else {
                    Text(model.lineLabel.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                    Text(model.currentLine.isEmpty ? "No readable text on this page." : model.currentLine)
                        .font(.system(size: 30, weight: .medium, design: .rounded)).lineSpacing(6)
                        .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 850)
                    ZStack {
                        Circle().fill(Color.ocean.opacity(player.isPulsing ? 0.20 : 0.07)).frame(width: 90, height: 90)
                        Text(player.current.map { String($0.character) } ?? (player.symbols.isEmpty ? "·" : "✓"))
                            .font(.system(size: 58, weight: .light, design: .rounded))
                    }
                    MorseMarks(code: player.current?.code ?? "", active: player.markIndex, size: 13).frame(height: 16)
                    ProgressView(value: player.progress).tint(Color.ocean).frame(maxWidth: 400)
                    Text(player.status).font(.system(size: 15)).multilineTextAlignment(.center).frame(height: 42)
                }
                Spacer(minLength: 0)
                HStack(spacing: 34) {
                    gesture("2 clicks", "Play / pause", "pause.circle")
                    gesture("Swipe left / right", "Next / previous line", "arrow.left.arrow.right")
                    gesture("2-finger click", "Replay line", "arrow.counterclockwise")
                    gesture("Swipe up / down", "Faster / slower", "arrow.up.arrow.down")
                }.padding(20).glass(solid: model.solid)
                Text("Keep a finger resting on the trackpad to feel the pulses. Each line waits for your next action.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(welcoming ? "ESC  ·  Open standard controls" : "3 clicks  ·  Ask AI about this PDF     |     ESC  ·  Restore the pointer")
                    .font(.system(size: 14, weight: .semibold)).padding(.bottom, 7)
            }.padding(32).allowsHitTesting(false).accessibilityHidden(true)
            TouchControlSurface(enabled: !model.busy, activationOnly: welcoming, focusOnAppear: true, allowsQuestionEntry: !welcoming,
                                accessibilityValue: welcoming ? "Space or three clicks to enter touch mode" : "\(model.lineLabel). \(player.status)", onCommand: onCommand)
                .id(welcoming)
            if welcoming {
                VStack {
                    HStack { Spacer(); Button("Use standard controls  ↗") { onCommand(.exitTouchMode) }.buttonStyle(ActionStyle()) }
                    Spacer()
                }.padding(.top, 84).padding(.trailing, 42)
            }
        }
    }

    private func gesture(_ action: String, _ meaning: String, _ icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 23)).foregroundStyle(Color.ocean)
            Text(action).font(.system(size: 14, weight: .semibold))
            Text(meaning).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct ControlsGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    private var asking: Bool { section == 1 }
    private var writing: Bool { section == 2 }
    private var rows: [(String, String, String)] { writing ? [
        ("Draw with one finger", "Print a letter; lift between its strokes", "⌘⇧H opens this mode"),
        ("Two-finger swipe right", "Save the letter and clear the drawing pad", "→"),
        ("Two-finger swipe up", "Finish the letter and add a word space", "↑"),
        ("Two-finger swipe left", "Undo a stroke or reopen the saved letter", "← / Delete"),
        ("One physical click", "Transcribe the drawing into a message", "Space / Return"),
        ("Two-finger swipe down", "Review the transcription in Morse", "↓"),
        ("Another physical click", "Ask AI about the recognized message", "Space / Return"),
        ("Two-finger secondary click", "Return to the reader, keeping the draft", "Esc releases pointer")
    ] : asking ? [
        ("Light one-finger tap", "Add a Morse dot without pressing", "."),
        ("One-finger horizontal stroke", "Add a Morse dash, then lift", "−"),
        ("Two-finger swipe right", "Finish the current letter", "→ / Space"),
        ("Two-finger swipe up", "Finish the word and insert a space", "↑"),
        ("Two-finger swipe left", "Undo a mark, letter or word space", "← / Delete"),
        ("Two-finger swipe down", "Feel the drafted question in Morse", "↓"),
        ("One physical press-and-click", "Send the question to the selected AI", "Return"),
        ("Two-finger secondary click", "Return to PDF; cancel a pending request", "Esc exits mode")
    ] : [
        ("Three quick one-finger clicks", "Enter touch mode from the welcome screen", "⌘⇧T from the reader"),
        ("Double-click", "Start, pause, or resume the current line", "Space"),
        ("Two-finger swipe left", "Read the next line, including the next page", "→"),
        ("Two-finger swipe right", "Read the previous line", "←"),
        ("Two-finger secondary click", "Replay the current line from its beginning", "R"),
        ("Two-finger swipe up / down", "Read faster / slower", "↑ / ↓"),
        ("Triple-click while reading", "Open Draw to Ask AI", "⌘⇧A"),
        ("Escape", "Pause, leave touch mode, restore the pointer", "Esc")
    ] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Every control, in one place.").font(.title2.weight(.medium)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("⌘↑ PDF reading  ·  ⌘↓ Handwriting chat  ·  ⌘→ Morse questions  ·  ⌘← Practice").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ocean)
            Picker("Controls for", selection: $section) { Text("Reading").tag(0); Text("Morse questions").tag(1); Text("Handwriting").tag(2) }.pickerStyle(.segmented)
            Text(writing ? "The pointer stays fixed. Print one letter at a time, with as many strokes as needed. No Morse input is required." : asking ? "The pointer stays fixed. A light tap enters a dot; a physical click sends. Swipe to separate letters at your own pace." : "In touch mode, the whole trackpad controls your lesson. A single click does nothing; there is no small button to find.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 15) {
                GridRow { Text("GESTURE"); Text("ACTION"); Text("KEY") }.font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(rows, id: \.0) { row in
                    GridRow { Text(row.0).fontWeight(.medium); Text(row.1); Text(row.2) }.font(.system(size: 13))
                    Divider()
                }
            }
            Text(writing ? "First click: transcribe. The message is displayed for communication. Review it, then click again only to ask AI. An uncertain ? must be corrected before asking. Undo reopens saved letters so they can be redrawn." : asking ? "The app echoes recognized marks and completed letters. Replies wait for a double-click, then use the reading gestures. Triple-click on a reply for a follow-up; two-finger click returns to your saved PDF line." : "One tick: command accepted. Two ticks: paused. Three ticks: document boundary, speed limit, or unreadable line. A quiet line ending waits for you; it never advances by itself.").font(.system(size: 13)).lineSpacing(4)
            Text(writing ? "Uses an image-capable model and your key in Connections. Only the drawing is sent for transcription; a later question includes relevant PDF context. Tactile review still uses Morse. Escape cancels requests and restores the pointer." : asking ? "Light taps enter dots even when macOS Tap to click is enabled. Sending requires a physical Force Touch click; Return is a keyboard alternative. The selected provider receives your question and relevant PDF text only when you send. Escape releases the pointer and cancels a pending request." : "Use actual clicks, or taps if Tap to click is enabled in macOS. Replay requires secondary click to be enabled. Keyboard controls above work in touch mode. Switching apps or minimizing also releases the pointer and pauses. A helper can press Escape to import a PDF or configure an AI key.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(30).frame(width: 790)
    }
}
