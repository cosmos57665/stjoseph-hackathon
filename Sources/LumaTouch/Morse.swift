import AppKit
import Combine
import Foundation

struct MorseSymbol: Equatable {
    let character: Character
    let code: String
    let word: Int
}

enum Morse {
    static let alphabet: [Character: String] = [
        "A":".-", "B":"-...", "C":"-.-.", "D":"-..", "E":".", "F":"..-.",
        "G":"--.", "H":"....", "I":"..", "J":".---", "K":"-.-", "L":".-..",
        "M":"--", "N":"-.", "O":"---", "P":".--.", "Q":"--.-", "R":".-.",
        "S":"...", "T":"-", "U":"..-", "V":"...-", "W":".--", "X":"-..-",
        "Y":"-.--", "Z":"--..", "0":"-----", "1":".----", "2":"..---",
        "3":"...--", "4":"....-", "5":".....", "6":"-....", "7":"--...",
        "8":"---..", "9":"----.", ".":".-.-.-", ",":"--..--", "?":"..--..",
        "'":".----.", "!":"-.-.--", "/":"-..-.", "(":"-.--.", ")":"-.--.-",
        "&":".-...", ":":"---...", ";":"-.-.-.", "=":"-...-", "+":".-.-.",
        "-":"-....-", "_":"..--.-", "\"":".-..-.", "$":"...-..-", "@":".--.-."
    ]

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }

    static func encode(_ text: String) -> [MorseSymbol] {
        normalized(text).split(whereSeparator: { $0.isWhitespace }).enumerated().flatMap { index, word in
            word.compactMap { ch in alphabet[ch].map { MorseSymbol(character: ch, code: $0, word: index) } }
        }
    }

    static func unsupported(_ text: String) -> String {
        String(Set(normalized(text).filter { !$0.isWhitespace && alphabet[$0] == nil }).sorted())
    }

    static func display(_ text: String) -> String {
        normalized(text).split(whereSeparator: { $0.isWhitespace }).map { word in
            word.compactMap { alphabet[$0] }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: " / ")
    }

    static func units(_ symbols: [MorseSymbol]) -> Int {
        symbols.enumerated().reduce(0) { total, pair in
            let (i, symbol) = pair
            let marks = symbol.code.reduce(0) { $0 + ($1 == "." ? 1 : 3) }
            let gap = i + 1 < symbols.count ? (symbols[i + 1].word == symbol.word ? 3 : 7) : 0
            return total + marks + max(0, symbol.code.count - 1) + gap
        }
    }
}

@MainActor final class HapticPlayer: ObservableObject {
    @Published var symbols: [MorseSymbol] = []
    @Published var index = 0
    @Published var markIndex = -1
    @Published var isPlaying = false
    @Published var isPulsing = false
    @Published var unit: Double = 0.22
    @Published var status = "Rest a finger lightly on the trackpad."
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var cueTask: Task<Void, Never>?
    private let output: (NSHapticFeedbackManager.FeedbackPattern) -> Void
    private let startupDelay: Double

    init(startupDelay: Double = 1.2,
         output: @escaping (NSHapticFeedbackManager.FeedbackPattern) -> Void = {
             NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now)
         }) {
        self.startupDelay = startupDelay
        self.output = output
    }

    enum Cue { case ready, paused, boundary }

    func cue(_ cue: Cue) {
        cueTask?.cancel()
        let count = cue == .ready ? 1 : cue == .paused ? 2 : 3
        let delay = cue == .boundary ? 0.25 : 0.16
        let pattern: NSHapticFeedbackManager.FeedbackPattern = cue == .boundary ? .levelChange : .alignment
        // Feedback is separate from the Morse stream; play() leaves a lead-in.
        output(pattern)
        guard count > 1 else { return }
        cueTask = Task {
            for _ in 1..<count {
                do { try await sleep(delay); try Task.checkCancellation(); output(pattern) }
                catch { return }
            }
        }
    }

    var current: MorseSymbol? { symbols.indices.contains(index) ? symbols[index] : nil }
    var progress: Double { symbols.isEmpty ? 0 : Double(index) / Double(symbols.count) }
    var duration: Int { Int(ceil(Double(Morse.units(symbols)) * unit)) }

    func load(_ text: String) {
        stop()
        symbols = Morse.encode(text)
        index = 0
        status = symbols.isEmpty ? "Add some text to begin." : "Ready. Rest a finger lightly on the trackpad."
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        cueTask?.cancel()
        cueTask = nil
        isPlaying = false
        isPulsing = false
        markIndex = -1
    }

    func pause() { stop(); status = "Paused. Play repeats the current letter." }
    func reset() { stop(); index = 0; status = "Ready to replay." }
    func skipWord(_ direction: Int) {
        stop()
        guard !symbols.isEmpty else { return }
        let word = symbols[min(index, symbols.count - 1)].word
        if direction > 0 {
            index = symbols.firstIndex(where: { $0.word > word }) ?? (symbols.count - 1)
        } else {
            index = symbols.firstIndex(where: { $0.word == max(0, word - 1) }) ?? 0
        }
        status = "Word selected. Press Play."
    }

    func play() {
        guard !isPlaying, !symbols.isEmpty else { return }
        if index >= symbols.count { index = 0 }
        let token = UUID()
        generation = token
        isPlaying = true
        status = "Starting in a moment. Place a finger on the trackpad."
        task = Task {
            do {
                try await sleep(startupDelay)
                while index < symbols.count {
                    try Task.checkCancellation()
                    let symbol = symbols[index]
                    status = "Feeling letter \(symbol.character)"
                    let marks = Array(symbol.code)
                    for (offset, mark) in marks.enumerated() {
                        markIndex = offset
                        try await pulse(dash: mark == "-")
                        if offset + 1 < marks.count { try await sleep(unit) }
                    }
                    markIndex = -1
                    if index + 1 < symbols.count {
                        let gap = symbols[index + 1].word == symbol.word ? 3.0 : 7.0
                        try await sleep(unit * gap)
                    }
                    index += 1
                }
                guard generation == token else { return }
                isPlaying = false
                status = "Line finished. Swipe left for the next line, or double-click to replay."
            } catch {
                // Cancellation intentionally leaves the current letter selected.
                guard generation == token else { return }
                isPlaying = false
                isPulsing = false
                markIndex = -1
            }
        }
    }

    private func pulse(dash: Bool) async throws {
        let length = unit * (dash ? 3 : 1)
        isPulsing = true
        // AppKit exposes presets, not custom motor waveforms. A dash is an
        // approximation made from a train of preset pulses over three units.
        let count = dash ? max(3, Int(length / 0.07)) : 1
        for _ in 0..<count {
            try Task.checkCancellation()
            output(.generic)
            try await sleep(length / Double(count))
        }
        isPulsing = false
    }

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
