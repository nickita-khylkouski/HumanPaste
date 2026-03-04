import Foundation

enum TypingAction: CustomStringConvertible, Equatable {
    case type(String)              // canonical text (final output)
    case syntheticType(String)     // typed text that gets deleted (false starts, cursor retypes)
    case pause(milliseconds: Int)
    case backspace(count: Int)
    case deleteForward(count: Int)
    case moveCursorLeft(count: Int)
    case moveCursorRight(count: Int)

    var description: String {
        switch self {
        case .type(let text):
            return "type(\(text))"
        case .syntheticType(let text):
            return "syntheticType(\(text))"
        case .pause(let ms):
            return "pause(\(ms)ms)"
        case .backspace(let count):
            return "backspace(\(count))"
        case .deleteForward(let count):
            return "delete_forward(\(count))"
        case .moveCursorLeft(let count):
            return "cursor_left(\(count))"
        case .moveCursorRight(let count):
            return "cursor_right(\(count))"
        }
    }
}

struct PredictionRequest: Codable {
    let precedingContext: String
    let upcomingCanonicalWords: [String]
    let mode: String
    let maxWords: Int
}

struct PredictionCandidate: Codable {
    let phrase: String
    let confidence: Double
}

struct PlannerState {
    var totalWords: Int = 0
    var falseStartsUsed: Int = 0
    var cursorEditsUsed: Int = 0
    var lastSyntheticEventWordIndex: Int = -1000
}

extension String {
    var wordCountApprox: Int {
        split { $0.isWhitespace }.count
    }

    var looksProtectedToken: Bool {
        let lower = lowercased()
        if lower.contains("http://") || lower.contains("https://") { return true }
        if contains("@") && contains(".") { return true }
        if range(of: #"^[0-9\-:\/\.]+$"#, options: .regularExpression) != nil { return true }
        if range(of: #"[{}\[\]<>`;$]"#, options: .regularExpression) != nil { return true }
        return false
    }
}
