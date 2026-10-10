import SwiftUI

@MainActor struct VisualConversationView: View {
    @StateObject private var model: VisualConversation
    @Environment(\.dismiss) private var dismiss
    init(model: VisualConversation? = nil) {
        _model = StateObject(wrappedValue: model ?? VisualConversation())
    }
    @State private var confirmClear = false

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Face-to-face communication")
                        Text("Your words. In full view.").font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("Type your message. Read your partner’s words.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear conversation") { confirmClear = true }.buttonStyle(ActionStyle())
                    Button("Done") { model.stopAll(); dismiss() }.buttonStyle(ActionStyle()).keyboardShortcut(.cancelAction)
                }
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(alignment: .top, spacing: 20) {
                            composePanel.frame(maxWidth: .infinity)
                            captionsPanel.frame(maxWidth: .infinity)
                        }
                        if !model.messages.isEmpty { history }
                    }.padding(2)
                }
                Text("Your conversation stays in this app session. Captions use on-device recognition when available. Check important details with your partner.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(28)
            if model.showMessage { messageBoard }
        }
        .frame(minWidth: 850, minHeight: 650)
        .alert("Clear this conversation?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { model.clear() }
        } message: { Text("This removes typed messages and captions from this session and stops the microphone.") }
        .onDisappear { model.stopAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if model.isListening || model.isSpeaking { model.stopAll() }
        }
    }

    private var composePanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Say it your way", systemImage: "text.bubble.fill").font(.title3.bold())
            Text("Type a message, or choose a phrase and edit it.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $model.draft)
                .font(.system(size: 23)).scrollContentBackground(.hidden)
                .padding(10).frame(height: 150)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Message to your conversation partner")
                .onChange(of: model.draft) { _, text in
                    if text.count > 4000 { model.draft = String(text.prefix(4000)) }
                }
            Text("\(model.draft.count) / 4000 characters").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { model.shareDraft() } label: { Label("Show large", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(ActionStyle(prominent: true)).disabled(!model.hasDraft)
                Button { model.speakDraft() } label: { Label("Speak", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(ActionStyle()).disabled(!model.hasDraft)
                if model.isSpeaking {
                    Button("Stop voice") { model.stopSpeaking() }.buttonStyle(ActionStyle())
                }
            }
            Text("Speak reads your typed message aloud to a hearing partner.").font(.caption).foregroundStyle(.secondary)
            Eyebrow(text: "Quick phrases")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(VisualConversation.phrases, id: \.self) { phrase in
                    Button { model.usePhrase(phrase) } label: {
                        Text(phrase).font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, minHeight: 37, alignment: .leading).padding(10)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(22).glass()
    }

    private var captionsPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Read their reply", systemImage: "captions.bubble.fill").font(.title3.bold())
            Text("Ask your partner to speak toward the Mac, or let them type in the message box.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Language", selection: $model.localeIdentifier) {
                Text("English (India)").tag("en-IN")
                Text("English (US)").tag("en-US")
                Text("Hindi").tag("hi-IN")
                Text("Tamil").tag("ta-IN")
            }.disabled(model.isListening || model.isPreparing || model.isSpeaking)
            HStack {
                if model.isListening || model.isPreparing {
                    Button { model.stopListening() } label: { Label("Stop captions", systemImage: "stop.fill") }
                        .buttonStyle(ActionStyle(prominent: true))
                } else {
                    Button { model.startListening() } label: { Label("Start captions", systemImage: "mic.fill") }
                        .buttonStyle(ActionStyle(prominent: true))
                }
            }
            Label(model.status, systemImage: model.isListening ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(model.isListening ? Color.ocean : Color.primary)
                .accessibilityLabel(model.status)
            ScrollView {
                Text(model.captions.isEmpty ? "Their spoken words will appear here." : model.captions)
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .foregroundStyle(model.captions.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.frame(minHeight: 210, maxHeight: 340)
                .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            Text("Start captions asks for microphone and speech permission. No audio is saved. Captions stop when you leave this screen or switch apps.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).glass()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Messages you showed")
            ForEach(model.messages) { message in
                HStack(alignment: .top) {
                    Text(message.text).font(.title3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Use again") { model.draft = message.text }.buttonStyle(ActionStyle())
                }
                Divider()
            }
        }.padding(22).glass()
    }

    private var messageBoard: some View {
        VStack(spacing: 24) {
            HStack {
                Eyebrow(text: "My message to you")
                Spacer()
                Button("Back to conversation") { model.showMessage = false }.buttonStyle(ActionStyle()).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(model.displayedMessage).font(.system(size: 48, weight: .semibold, design: .rounded))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .center).padding(30)
            }
            Text("You can reply by typing, or use live captions in the conversation.").font(.title3).foregroundStyle(.secondary)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .accessibilityAddTraits(.isModal)
    }
}
