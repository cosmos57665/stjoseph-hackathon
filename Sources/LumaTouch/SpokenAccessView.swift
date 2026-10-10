import SwiftUI

struct SpokenAccessView: View {
    let pdfText: String
    @StateObject private var speech = SpokenAccess()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Eyebrow(text: "Listen & learn")
                    Text("Your words, read aloud.").font(.system(size: 32, weight: .medium))
                    Text("Text, your PDF page, or the spoken dialogue in a video.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { speech.shutdown(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                Button { speech.stopSpeaking(); speech.text = pdfText } label: {
                    Label("Use current PDF page", systemImage: "doc.text")
                }.disabled(pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.isTranscribing)
                Button { speech.importVideo() } label: { Label("Import video or audio", systemImage: "film") }
                    .keyboardShortcut("o", modifiers: [.command, .option]).disabled(speech.isTranscribing)
                Spacer()
                if speech.isTranscribing {
                    ProgressView().controlSize(.small)
                    Button("Cancel transcription") { speech.cancelTranscription() }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Text to read").font(.headline)
                TextEditor(text: $speech.text).font(.system(size: 18)).padding(8)
                    .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 190, maxHeight: 260)
                    .accessibilityLabel("Text to read aloud. Paste or edit text here.")
                    .disabled(speech.isTranscribing)
                if speech.isTranscribing && !speech.partialTranscript.isEmpty {
                    Text("Completed transcript parts are being collected. Your existing text is kept until the whole clip finishes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                Picker("Speech language", selection: $speech.localeIdentifier) {
                    Text("English (US)").tag("en-US")
                    Text("English (India)").tag("en-IN")
                    Text("Hindi").tag("hi-IN")
                    Text("Tamil").tag("ta-IN")
                }.frame(width: 270).disabled(speech.isTranscribing || speech.isSpeaking)
                Slider(value: $speech.rate, in: 0.25...0.65) { Text("Reading speed") }
                    .accessibilityValue(String(format: "%.0f percent", speech.rate / 0.5 * 100))
                    .disabled(speech.isSpeaking)
                Text("Slower / faster").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { speech.speak() } label: { Label("Read aloud", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(ActionStyle(prominent: true)).keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!speech.canSpeak || speech.isSpeaking)
                Button(speech.isPaused ? "Resume" : "Pause") { speech.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .option]).disabled(!speech.isSpeaking)
                Button("Stop") { speech.stopSpeaking() }
                    .keyboardShortcut(".", modifiers: [.command, .option]).disabled(!speech.isSpeaking)
                Spacer()
                Button("Clear text") { speech.stopSpeaking(); speech.text = "" }
                    .disabled(speech.isTranscribing || speech.text.isEmpty)
            }
            Text(speech.status).font(.callout.weight(.medium)).foregroundStyle(Color.ocean)
                .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Speech status: \(speech.status)")
            Text("Video transcription uses on-device Apple Speech when available, with no API key. Import a local clip up to 10 minutes. It transcribes spoken dialogue; it does not describe visual scenes. Review recognition mistakes before relying on the transcript.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("⌘⌥O import · ⌘Return read · ⌘⌥P pause/resume · ⌘⌥. stop · Escape close")
                .font(.caption.weight(.medium))
        }.padding(28).frame(width: 790).background(.regularMaterial)
            .onDisappear { speech.shutdown() }
    }
}
