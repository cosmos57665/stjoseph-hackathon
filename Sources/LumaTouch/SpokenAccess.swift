import AppKit
import AVFoundation
import Speech
import SwiftUI
import UniformTypeIdentifiers

/// Speech access has its own lifecycle; leaving the sheet stops speech and recognition.
@MainActor final class SpokenAccess: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var text = ""
    @Published var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @Published var localeIdentifier = "en-US"
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var status = "Paste text, use the current PDF page, or import a video."
    @Published private(set) var partialTranscript = ""
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var work: Task<Void, Never>?
    private var job = UUID()
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionContinuation: CheckedContinuation<String, Error>?
    private var recognitionID: UUID?
    private var timeout: Task<Void, Never>?
    private var exporter: AVAssetExportSession?
    private let requestAuthorization: () async -> SFSpeechRecognizerAuthorizationStatus

    init(authorization: @escaping () async -> SFSpeechRecognizerAuthorizationStatus = { await SpokenAccess.authorization() }) {
        self.requestAuthorization = authorization
        super.init(); synthesizer.delegate = self
    }
    var canSpeak: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTranscribing }

    func speak() {
        guard canSpeak else { return }
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)
        utterance.rate = Float(rate.clamped(to: 0.25...0.65))
        activeUtterance = utterance; isSpeaking = true; isPaused = false
        status = "Reading aloud. Command–Option–P pauses or resumes; Command–Option–period stops."
        synthesizer.speak(utterance)
    }
    func togglePause() {
        guard isSpeaking else { return }
        if isPaused { isPaused = !synthesizer.continueSpeaking() }
        else { isPaused = synthesizer.pauseSpeaking(at: .immediate) }
        status = isPaused ? "Speech paused." : "Reading aloud."
    }
    func stopSpeaking() {
        activeUtterance = nil; synthesizer.stopSpeaking(at: .immediate)
        if isSpeaking { status = "Speech stopped." }
        isSpeaking = false; isPaused = false
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.isSpeaking = false; self.isPaused = false; self.activeUtterance = nil
            self.status = "Finished reading."
        }
    }

    func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose a video or audio clip up to 10 minutes. Its spoken dialogue is transcribed on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribe(url: url)
    }

    func transcribe(url: URL) {
        cancelTranscription(); stopSpeaking()
        let identifier = UUID(); job = identifier
        let locale = localeIdentifier
        isTranscribing = true; partialTranscript = ""
        status = "Checking speech permission…"
        work = Task { [weak self] in
            guard let self else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("luma-speech-\(identifier.uuidString)")
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
                try? FileManager.default.removeItem(at: directory)
                if self.job == identifier { self.isTranscribing = false; self.work = nil; self.exporter = nil }
            }
            do {
                try Task.checkCancellation()
                let authorization = await self.requestAuthorization()
                try Task.checkCancellation()
                guard authorization == .authorized else { throw SpokenAccessError.permission }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
                      recognizer.supportsOnDeviceRecognition else { throw SpokenAccessError.localUnavailable }
                guard recognizer.isAvailable else { throw SpokenAccessError.unavailable }
                self.status = "Checking video audio…"
                let asset = AVURLAsset(url: url)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                try Task.checkCancellation()
                guard !audio.isEmpty else { throw SpokenAccessError.noAudio }
                let duration = try await asset.load(.duration).seconds
                try Task.checkCancellation()
                let chunks = try Self.chunkRanges(duration: duration)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var paragraphs: [String] = []
                for (index, range) in chunks.enumerated() {
                    try Task.checkCancellation()
                    self.status = "Transcribing part \(index + 1) of \(chunks.count) on this Mac…"
                    let audioURL = directory.appendingPathComponent("part-\(index).m4a")
                    try await self.export(asset: asset, range: range, to: audioURL)
                    try Task.checkCancellation()
                    let recognized = try await self.recognize(url: audioURL, using: recognizer)
                    try Task.checkCancellation()
                    if !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { paragraphs.append(recognized) }
                    self.partialTranscript = paragraphs.joined(separator: "\n\n")
                    try? FileManager.default.removeItem(at: audioURL)
                }
                guard !paragraphs.isEmpty else { throw SpokenAccessError.noSpeech }
                guard self.job == identifier else { return }
                self.text = paragraphs.joined(separator: "\n\n")
                self.status = "Transcript ready. Press Command–Return to read it aloud. Recognition can make mistakes."
            } catch is CancellationError {
                if self.job == identifier { self.status = "Transcription cancelled. Your previous text is unchanged." }
            } catch {
                if self.job == identifier {
                    self.status = (error as? SpokenAccessError)?.message ?? "Could not transcribe this clip. Try a shorter clip with clear speech, check your speech language, and try again. Your previous text is unchanged."
                }
            }
        }
    }

    func cancelTranscription() {
        job = UUID(); work?.cancel(); work = nil; exporter?.cancelExport(); exporter = nil
        recognition?.cancel(); recognition = nil; timeout?.cancel(); timeout = nil
        recognitionID = nil
        let pending = recognitionContinuation; recognitionContinuation = nil
        pending?.resume(throwing: CancellationError())
        if isTranscribing { status = "Transcription cancelled. Your previous text is unchanged." }
        isTranscribing = false
    }
    func shutdown() { cancelTranscription(); stopSpeaking() }

    static func chunkRanges(duration: Double) throws -> [CMTimeRange] {
        guard duration.isFinite, duration > 0 else { throw SpokenAccessError.invalidDuration }
        guard duration <= 600 else { throw SpokenAccessError.tooLong }
        return stride(from: 0.0, to: duration, by: 45.0).map {
            CMTimeRange(start: CMTime(seconds: $0, preferredTimescale: 600),
                        duration: CMTime(seconds: min(45, duration - $0), preferredTimescale: 600))
        }
    }
    static func authorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
    private func export(asset: AVAsset, range: CMTimeRange, to url: URL) async throws {
        try Task.checkCancellation()
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpokenAccessError.exportFailed
        }
        session.outputURL = url; session.outputFileType = .m4a; session.timeRange = range
        exporter = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        try Task.checkCancellation()
        guard session.status == .completed else { throw SpokenAccessError.exportFailed }
        exporter = nil
    }
    private func recognize(url: URL, using recognizer: SFSpeechRecognizer) async throws -> String {
        try Task.checkCancellation()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let identifier = UUID(); recognitionID = identifier
        return try await withCheckedThrowingContinuation { continuation in
            recognitionContinuation = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 90_000_000_000) } catch { return }
                self?.finishRecognition(identifier, result: .failure(SpokenAccessError.timeout))
            }
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let finalText = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                Task { @MainActor in
                    if let finalText { self?.finishRecognition(identifier, result: .success(finalText)) }
                    else if error != nil { self?.finishRecognition(identifier, result: .failure(SpokenAccessError.recognitionFailed)) }
                }
            }
        }
    }
    private func finishRecognition(_ identifier: UUID, result: Result<String, Error>) {
        guard recognitionID == identifier else { return }
        recognitionID = nil; timeout?.cancel(); timeout = nil
        let pending = recognitionContinuation; recognitionContinuation = nil
        recognition?.cancel(); recognition = nil
        pending?.resume(with: result)
    }
}

enum SpokenAccessError: Error {
    case permission, localUnavailable, unavailable, noAudio, noSpeech, invalidDuration, tooLong, exportFailed, recognitionFailed, timeout
    var message: String {
        switch self {
        case .permission: return "Speech permission is off. Enable Luma Touch in System Settings → Privacy & Security → Speech Recognition, then import again."
        case .localUnavailable: return "On-device speech recognition is unavailable for this language. Try another language or install the matching macOS speech resources. No audio was uploaded. You can still paste a transcript and read it aloud."
        case .unavailable: return "Speech recognition is temporarily unavailable. Try again later, or paste a transcript to read aloud."
        case .noAudio: return "This video has no audio track. Add or paste a transcript to read aloud."
        case .noSpeech: return "No speech was recognized. Try a clip with clear dialogue and the matching language."
        case .invalidDuration: return "This clip has an unreadable duration. Try a local MP4, MOV, or audio file."
        case .tooLong: return "Choose a clip up to 10 minutes. Trim longer videos into shorter parts first."
        case .exportFailed: return "Could not read the audio in this clip. Try an unprotected MP4 or MOV file."
        case .recognitionFailed: return "Speech could not be recognized. Try a shorter clip with clear dialogue and the matching language. Your previous text is unchanged."
        case .timeout: return "Speech recognition took too long. Try a shorter clip. Your previous text is unchanged."
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(range.upperBound, max(range.lowerBound, self)) }
}
