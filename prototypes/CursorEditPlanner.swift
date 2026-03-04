import Foundation

/// Cognitive events that simulate real human editing behavior beyond simple typos.
/// These all preserve the canonical text but add realistic hesitation patterns.
struct CognitiveEventPlanner {
    let config: UncertaintyConfig

    enum EventType {
        case midWordRestart    // hesitate mid-word, backspace partial, retype from scratch
        case rephraseBacktrack // backspace a few words, try AI alternative, go back to original
        case forgottenWord     // skip a word, type ahead, realize it's missing, go back and insert
        case forgottenClause   // skip an entire clause/sentence, type ahead, realize, go back and insert
    }

    // Words humans commonly skip when typing fast (public for UncertaintyEngine access)
    static let skippableWords: Set<String> = [
        "a", "an", "the", "in", "on", "at", "to", "for", "of", "with",
        "is", "it", "we", "he", "she", "be", "as", "by", "or", "and",
        "but", "not", "that", "this", "has", "had", "was", "are", "can",
        "will", "from", "have", "been", "also", "very", "just", "more",
        "some", "than", "then", "when", "into", "each", "only",
    ]

    func shouldInjectEvent(state: PlannerState, currentWordIndex: Int) -> Bool {
        if state.cursorEditsUsed >= config.maxCursorEditsPerMessage { return false }
        if currentWordIndex < config.minWordsForSyntheticEdits { return false }
        if currentWordIndex - state.lastSyntheticEventWordIndex < config.cooldownWordsBetweenSyntheticEvents {
            return false
        }

        let eligibleWords = max(1, state.totalWords - config.minWordsForSyntheticEdits)
        let targetCount = Double(config.maxCursorEditsPerMessage)
        let probability = min(0.12, targetCount / Double(eligibleWords) * 1.5)
        return Double.random(in: 0...1) < probability
    }

    /// Pick event type based on what's available in the upcoming and recent context.
    func pickEventType(word: String, recentTokens: [RecentToken], upcomingTokens: [BoundaryToken]) -> EventType {
        // Forgotten clause: need upcoming punctuation boundaries
        if upcomingTokens.count >= 10 {
            let boundaryCount = upcomingTokens.prefix(30).filter { token in
                token.kind == .punctuation && ".;,".contains(token.text.trimmingCharacters(in: .whitespaces))
            }.count
            if boundaryCount >= 2 && Double.random(in: 0...1) < 0.30 {
                return .forgottenClause
            }
        }

        // Forgotten word: check if upcoming tokens have a skippable word
        if upcomingTokens.count >= 4 {
            var wordsSeen = 0
            let hasSkippable = upcomingTokens.prefix(12).contains { token in
                if token.kind == .word { wordsSeen += 1 }
                return wordsSeen >= 2
                    && token.kind == .word
                    && Self.skippableWords.contains(token.text.lowercased())
            }
            if hasSkippable && Double.random(in: 0...1) < 0.45 {
                return .forgottenWord
            }
        }

        // Mid-word restart for long words
        if word.count >= 6 && Double.random(in: 0...1) < 0.35 {
            return .midWordRestart
        }

        return .rephraseBacktrack
    }

    // MARK: - Mid-Word Restart
    // Human behavior: start typing "implementation", get to "impl", hesitate, backspace, start over.

    func buildMidWordRestart(word: String) -> [TypingAction] {
        guard word.count >= 6 else { return [] }

        let partialLen = min(word.count - 2, Int.random(in: 2...4))
        let partial = String(word.prefix(partialLen))
        let pauseMs = Int.random(in: 200...500)

        return [
            .syntheticType(partial),
            .pause(milliseconds: pauseMs),
            .backspace(count: partialLen)
        ]
    }

    // MARK: - Rephrase Backtrack
    // Human behavior: start typing an alternative phrasing, pause, realize
    // the original wording was better, backspace the alternative.
    // Then canonical .type() tokens continue with the correct text.

    func buildRephraseBacktrack(upcomingWords: [String], aiAlternative: String?) -> [TypingAction] {
        let altPhrase: String
        if let ai = aiAlternative, !ai.isEmpty, ai.wordCountApprox >= 2 {
            altPhrase = ai
        } else {
            // No AI alternative — just do a brief hesitation pause
            return [.pause(milliseconds: Int.random(in: 300...600))]
        }

        let typePauseMs = Int.random(in: 400...800)
        let revertPauseMs = Int.random(in: 200...400)

        return [
            .syntheticType(altPhrase + " "),
            .pause(milliseconds: typePauseMs),
            .backspace(count: altPhrase.count + 1),
            .pause(milliseconds: revertPauseMs),
        ]
    }
}

/// Tracks recently emitted tokens for cognitive event planning
struct RecentToken {
    let text: String
    let isWord: Bool
}
