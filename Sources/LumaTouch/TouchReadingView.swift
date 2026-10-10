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
                    Text("Three quick clicks to begin.").font(.system(size: 26, weight: .medium))
                    Text("Click the trackpad three times with one finger.\nThe pointer will stay inside this window and disappear.")
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
                Text("ESC  ·  Pause and restore the pointer").font(.system(size: 14, weight: .semibold)).padding(.bottom, 7)
            }.padding(32).allowsHitTesting(false).accessibilityHidden(true)
            TouchControlSurface(activationOnly: welcoming, focusOnAppear: true,
                                accessibilityValue: welcoming ? "Three clicks to enter touch mode" : "\(model.lineLabel). \(player.status)", onCommand: onCommand)
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
    private let rows = [
        ("Three quick one-finger clicks", "Enter touch mode from the welcome screen", "⌘⇧T from the reader"),
        ("Double-click", "Start, pause, or resume the current line", "Space"),
        ("Two-finger swipe left", "Read the next line, including the next page", "→"),
        ("Two-finger swipe right", "Read the previous line", "←"),
        ("Two-finger secondary click", "Replay the current line from its beginning", "R"),
        ("Two-finger swipe up / down", "Read faster / slower", "↑ / ↓"),
        ("Escape", "Pause, leave touch mode, restore the pointer", "Esc")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Every control, in one place.").font(.title2.weight(.medium)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("In touch mode, the whole trackpad controls your lesson. A single click does nothing; there is no small button to find.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 15) {
                GridRow { Text("GESTURE"); Text("ACTION"); Text("KEY") }.font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(rows, id: \.0) { row in
                    GridRow { Text(row.0).fontWeight(.medium); Text(row.1); Text(row.2) }.font(.system(size: 13))
                    Divider()
                }
            }
            Text("One tick: command accepted. Two ticks: paused. Three ticks: document boundary, speed limit, or unreadable line. A quiet line ending waits for you; it never advances by itself.").font(.system(size: 13)).lineSpacing(4)
            Text("Use actual clicks, or taps if Tap to click is enabled in macOS. Replay requires secondary click to be enabled. Keyboard controls above work in touch mode. Switching apps or minimizing also releases the pointer and pauses. A helper can press Escape to import a PDF or configure an AI key.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(30).frame(width: 790)
    }
}
