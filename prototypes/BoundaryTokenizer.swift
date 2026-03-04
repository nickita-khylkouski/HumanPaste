import Foundation

enum TokenKind {
    case word
    case punctuation
    case whitespace
}

struct BoundaryToken {
    let text: String
    let kind: TokenKind
}

struct BoundaryTokenizer {
    /// Keeps punctuation boundaries so planners can trigger false-starts at natural boundaries.
    static func tokenize(_ input: String) -> [BoundaryToken] {
        guard !input.isEmpty else { return [] }

        var tokens: [BoundaryToken] = []
        var buffer = ""
        var bufferKind: TokenKind? = nil

        func flush() {
            guard !buffer.isEmpty, let kind = bufferKind else { return }
            tokens.append(BoundaryToken(text: buffer, kind: kind))
            buffer = ""
            bufferKind = nil
        }

        for scalar in input.unicodeScalars {
            let ch = Character(scalar)
            let kind: TokenKind

            if ch.isWhitespace {
                kind = .whitespace
            } else if ".,!?;:".contains(ch) {
                kind = .punctuation
            } else {
                kind = .word
            }

            if let currentKind = bufferKind, currentKind == kind {
                buffer.append(ch)
            } else {
                flush()
                bufferKind = kind
                buffer = String(ch)
            }
        }

        flush()
        return tokens
    }

    static func wordWindows(from tokens: [BoundaryToken], size: Int) -> [[String]] {
        let words = tokens.compactMap { $0.kind == .word ? $0.text : nil }
        guard size > 0, !words.isEmpty else { return [] }

        var windows: [[String]] = []
        var i = 0
        while i < words.count {
            let end = min(i + size, words.count)
            windows.append(Array(words[i..<end]))
            i = end
        }
        return windows
    }
}
