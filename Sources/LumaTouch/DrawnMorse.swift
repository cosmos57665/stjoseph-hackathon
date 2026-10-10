import Foundation

enum DrawnMorse {
    enum Mark: String { case dot = ".", dash = "-" }

    static func isTap(_ points: [CGPoint], duration: TimeInterval) -> Bool {
        guard let first = points.first, (0.025...0.55).contains(duration) else { return false }
        return points.allSatisfy { hypot($0.x - first.x, $0.y - first.y) < 0.02 }
    }

    // Shape recognition uses trackpad coordinates, independent of pointer
    // acceleration, screen resolution and where the learner starts the stroke.
    static func recognize(_ points: [CGPoint]) -> Mark? {
        guard points.count >= 3, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
        let distance = hypot(points.last!.x - points.first!.x, points.last!.y - points.first!.y)
        let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard length >= 0.05 else { return nil } // Resting/tapping is never a dot.
        if width >= 0.09, height <= max(0.025, width * 0.30), distance / length >= 0.80,
           abs(points.last!.x - points.first!.x) >= width * 0.85 { return .dash }
        let diameter = max(width, height)
        if (0.025...0.25).contains(diameter), min(width, height) >= 0.018,
           (0.45...2.2).contains(width / height), distance <= diameter * 0.45,
           length >= diameter * 1.9, length <= diameter * 6 { return .dot }
        return nil
    }
}

struct MorseDraft: Equatable {
    private(set) var text = ""
    private(set) var pending = ""
    static let limit = 240
    static let reverse = Dictionary(uniqueKeysWithValues: Morse.alphabet.map { ($0.value, $0.key) })
    var letter: Character? { Self.reverse[pending] }
    var preview: String { text + (letter.map(String.init) ?? "") }

    mutating func append(_ mark: DrawnMorse.Mark) throws {
        guard text.count < Self.limit else { throw AppError.message("Question limit reached. Send it or undo a letter.") }
        let candidate = pending + mark.rawValue
        guard Self.reverse.keys.contains(where: { $0.hasPrefix(candidate) }) else {
            throw AppError.message("That pattern cannot form a Morse character. The last mark was not added; swipe left to undo.")
        }
        pending = candidate
    }

    @discardableResult mutating func finishLetter() throws -> Character {
        guard let letter else { throw AppError.message(pending.isEmpty ? "Draw a letter first." : "Incomplete Morse letter. Add another mark or undo.") }
        guard text.count < Self.limit else { throw AppError.message("Question limit reached.") }
        text.append(letter)
        pending = ""
        return letter
    }

    mutating func space() throws {
        if !pending.isEmpty { try finishLetter() }
        guard !text.isEmpty else { throw AppError.message("Draw a word first.") }
        if !text.hasSuffix(" "), text.count < Self.limit { text.append(" ") }
    }

    @discardableResult mutating func undo() -> Bool {
        if !pending.isEmpty { pending.removeLast(); return true }
        if !text.isEmpty { text.removeLast(); return true }
        return false
    }

    mutating func question() throws -> String {
        if !pending.isEmpty { try finishLetter() }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AppError.message("Draw a question before clicking to send.") }
        return result
    }
}
