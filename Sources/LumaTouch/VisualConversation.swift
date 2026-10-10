import AppKit
import AVFoundation
import Speech

struct VisualMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// A session-only face-to-face conversation. Audio is requested explicitly and never saved.
@MainActor final class VisualConversation: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let phrases = ["Hello. I communicate by typing.", "Please face me while we talk.", "Please type your reply here.", "Could you repeat that?", "Yes", "No", "Thank you.", "I need help."]
    @Published var draft = ""
    @Published var localeIdentifier = "en-IN"
    @Published private(set) var messages: [VisualMessage] = []
    @Published private(set) var captions = ""
    @Published private(set) var isListening = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var status = "Microphone off"
    @Published var showMessage = false
    @Published private(set) var displayedMessage = ""
    private let speaker = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapInstalled = false
    // Invalidated before cancellation so delayed permission and recognition callbacks cannot restart capture.
    private(set) var captureGeneration = UUID()
    private var prepareTask: Task<Void, Never>?
    var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    override init() { super.init(); speaker.delegate = self }

    func usePhrase(_ text: String) { draft = text }

    @discardableResult func shareDraft() -> Bool {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !text.isEmpty else { return false }
        stopListening()
        displayedMessage = text
        if messages.last?.text != text {
            messages.append(VisualMessage(text: text))
            if messages.count > 50 { messages.removeFirst(messages.count - 50) }
        }
        showMessage = true
        return true
    }

    func speakDraft() {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !text.isEmpty else { return }
        stopListening()
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)
        speaker.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() { speaker.stopSpeaking(at: .immediate); isSpeaking = false }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = synthesizer.isSpeaking }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.isSpeaking = synthesizer.isSpeaking }
    }

    func startListening() {
        guard !isPreparing && !isListening else { return }
        stopSpeaking()
        stopListening()
        let generation = captureGeneration
        isPreparing = true
        status = "Requesting microphone and speech permission…"
        prepareTask = Task { [weak self] in
            guard let self else { return }
            let permission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard self.captureGeneration == generation, !Task.isCancelled else { return }
            guard permission == .authorized else {
                self.fail("Speech permission is off. Enable Luma Touch in System Settings → Privacy & Security → Speech Recognition, or type a reply.")
                return
            }
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard self.captureGeneration == generation, !Task.isCancelled else { return }
            guard allowed else {
                self.fail("Microphone permission is off. Enable Luma Touch in System Settings → Privacy & Security → Microphone, or type a reply.")
                return
            }
            guard NSApplication.shared.isActive else {
                self.fail("Permission checked. Return to Luma Touch and press Start captions again.")
                return
            }
            self.beginCapture(generation: generation)
        }
    }

    private func beginCapture(generation: UUID) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            fail("Captions are unavailable for this language right now. Choose another language, or ask your partner to type.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            fail("On-device captions are unavailable for this language on this Mac. Choose another language, or ask your partner to type.")
            return
        }
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone is available. Connect one, then try again.")
            return
        }
        self.engine = engine; self.request = request; self.recognizer = recognizer
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.captureGeneration == generation else { return }
                if let text { self.receiveCaption(text, generation: generation) }
                if final {
                    self.stopListening()
                    self.status = "Caption segment finished. Start captions again to continue."
                } else if failed {
                    self.fail("Captions stopped. Check your microphone and try Start captions again. Your last text is still here.")
                }
            }
        }
        do {
            engine.prepare(); try engine.start()
            captions = ""
            isPreparing = false; isListening = true
            status = "Listening · microphone on · captions may contain mistakes"
        } catch {
            fail("The microphone could not start. Check your audio input in System Settings, then try again.")
        }
    }

    // Bounded state update separated from microphone capture for regression tests.
    func receiveCaption(_ text: String, generation: UUID) {
        guard generation == captureGeneration else { return }
        captions = String(text.suffix(12000))
    }

    private func fail(_ message: String) { stopListening(); status = message }

    func stopListening() {
        captureGeneration = UUID()
        prepareTask?.cancel(); prepareTask = nil
        isPreparing = false; isListening = false
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        request?.endAudio(); recognition?.cancel()
        recognition = nil; request = nil; engine = nil; recognizer = nil
        status = "Microphone off"
    }

    func stopAll() { stopListening(); stopSpeaking() }
    func clear() {
        stopAll(); draft = ""; captions = ""; messages = []; displayedMessage = ""; showMessage = false
    }
}
