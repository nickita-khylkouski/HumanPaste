import Foundation

struct UncertaintyEngine {
    let config: UncertaintyConfig
    let predictor: PredictionProvider
    let falseStartPlanner: FalseStartPlanner
    let cognitivePlanner: CognitiveEventPlanner

    init(config: UncertaintyConfig, predictor: PredictionProvider) {
        self.config = config
        self.predictor = predictor
        self.falseStartPlanner = FalseStartPlanner(config: config)
        self.cognitivePlanner = CognitiveEventPlanner(config: config)
    }

    // Tracks a word or clause that was intentionally skipped during typing.
    // After enough words are typed past the skip point, a correction sequence
    // fires: pause → arrow left → type missing text → arrow right.
    private struct DeferredInsertion {
        let insertText: String           // the skipped text to insert later
        let triggerAfterWords: Int       // fire after this many words past the skip
        let firstSkipTokenIndex: Int     // first token index that was skipped
        var counting: Bool = false       // only count chars AFTER we pass the skip point
        var wordsTypedSinceSkip: Int = 0 // running word counter
        var charsTypedSinceSkip: Int = 0 // running char counter for cursor positioning
        var fired: Bool = false
    }

    func buildActions(for canonicalText: String) async -> [TypingAction] {
        guard config.enabled else { return [.type(canonicalText)] }

        let tokens = BoundaryTokenizer.tokenize(canonicalText)
        let totalWords = tokens.reduce(0) { partial, token in
            token.kind == .word ? partial + 1 : partial
        }

        guard totalWords >= config.minWordsForSyntheticEdits else {
            return [.type(canonicalText)]
        }

        var actions: [TypingAction] = []
        var state = PlannerState(totalWords: totalWords)
        var latencyBudgetUsedMs = 0
        var emittedWordIndex = 0
        var contextWords: [String] = []
        var recentWords: [String] = []
        var recentTokens: [RecentToken] = []

        // Skip-based forgotten word/clause state
        var skipIndices: Set<Int> = []
        var deferredInsertions: [DeferredInsertion] = []

        for i in tokens.indices {
            let token = tokens[i]

            // --- Fire any deferred insertions whose trigger point is reached ---
            if token.kind == .word {
                for j in deferredInsertions.indices {
                    if !deferredInsertions[j].fired
                        && deferredInsertions[j].wordsTypedSinceSkip >= deferredInsertions[j].triggerAfterWords
                        && deferredInsertions[j].charsTypedSinceSkip > 0 {
                        let ins = deferredInsertions[j]
                        let noticePauseMs = Int.random(in: 400...800)
                        let positionPauseMs = Int.random(in: 150...350)
                        let resumePauseMs = Int.random(in: 100...250)
                        actions += [
                            .pause(milliseconds: noticePauseMs),
                            .moveCursorLeft(count: ins.charsTypedSinceSkip),
                            .pause(milliseconds: positionPauseMs),
                            .syntheticType(ins.insertText),
                            .moveCursorRight(count: ins.charsTypedSinceSkip),
                            .pause(milliseconds: resumePauseMs),
                        ]
                        deferredInsertions[j].fired = true
                        latencyBudgetUsedMs += noticePauseMs + positionPauseMs + resumePauseMs
                    }
                }
            }

            // --- Skip tokens marked for forgotten word/clause ---
            if skipIndices.contains(i) {
                // Activate counting for any deferred insertion whose skip point we just reached
                for j in deferredInsertions.indices {
                    if !deferredInsertions[j].counting && deferredInsertions[j].firstSkipTokenIndex == i {
                        deferredInsertions[j].counting = true
                    }
                }
                // Don't emit .type() — this token was "forgotten"
                // Still count it as a word for event spacing
                if token.kind == .word {
                    emittedWordIndex += 1
                }
                continue
            }

            if token.kind == .word {
                let upcomingWords = collectUpcomingWords(tokens: tokens, from: i, maxWords: config.maxPredictionWords)

                // --- False start: type wrong prediction before this word ---
                if falseStartPlanner.shouldInjectFalseStart(state: state, currentWordIndex: emittedWordIndex),
                   latencyBudgetUsedMs < config.maxSyntheticLatencyBudgetMs,
                   !token.text.looksProtectedToken,
                   !upcomingWords.isEmpty {
                    let request = falseStartPlanner.predictionRequest(
                        contextWords: contextWords,
                        upcomingWords: upcomingWords
                    )

                    if let prediction = await predictor.predictFalseStart(request: request) {
                        let falseStartActions = falseStartPlanner.buildFalseStartActions(prediction: prediction)
                        if !falseStartActions.isEmpty {
                            actions.append(contentsOf: falseStartActions)
                            state.falseStartsUsed += 1
                            state.lastSyntheticEventWordIndex = emittedWordIndex
                            latencyBudgetUsedMs += estimatePause(falseStartActions)
                            recentTokens.removeAll()
                        }
                    }
                }

                // --- Cognitive events ---
                if cognitivePlanner.shouldInjectEvent(state: state, currentWordIndex: emittedWordIndex),
                   latencyBudgetUsedMs < config.maxSyntheticLatencyBudgetMs,
                   !token.text.looksProtectedToken {

                    let eventType = cognitivePlanner.pickEventType(
                        word: token.text,
                        recentTokens: recentTokens,
                        upcomingTokens: Array(tokens.suffix(from: i))
                    )

                    switch eventType {
                    case .midWordRestart where token.text.count >= 6:
                        let restartActions = cognitivePlanner.buildMidWordRestart(word: token.text)
                        if !restartActions.isEmpty {
                            actions.append(contentsOf: restartActions)
                            state.cursorEditsUsed += 1
                            state.lastSyntheticEventWordIndex = emittedWordIndex
                            latencyBudgetUsedMs += estimatePause(restartActions)
                        }

                    case .forgottenWord:
                        // Look ahead for a skippable word to "forget"
                        if let (wordIdx, spaceIdx, insertText) = findSkippableWord(tokens: tokens, from: i) {
                            skipIndices.insert(wordIdx)
                            if let si = spaceIdx { skipIndices.insert(si) }
                            let wordsAhead = Int.random(in: 2...4)
                            deferredInsertions.append(DeferredInsertion(
                                insertText: insertText,
                                triggerAfterWords: wordsAhead,
                                firstSkipTokenIndex: wordIdx
                            ))
                            state.cursorEditsUsed += 1
                            state.lastSyntheticEventWordIndex = emittedWordIndex
                            latencyBudgetUsedMs += 600 // estimated pause budget
                        }

                    case .forgottenClause:
                        // Look ahead for a clause to "forget"
                        if let (clauseIndices, insertText) = findSkippableClause(tokens: tokens, from: i) {
                            let firstIdx = clauseIndices.min() ?? 0
                            for idx in clauseIndices { skipIndices.insert(idx) }
                            let wordsAhead = Int.random(in: 2...3)
                            deferredInsertions.append(DeferredInsertion(
                                insertText: insertText,
                                triggerAfterWords: wordsAhead,
                                firstSkipTokenIndex: firstIdx
                            ))
                            state.cursorEditsUsed += 1
                            state.lastSyntheticEventWordIndex = emittedWordIndex
                            latencyBudgetUsedMs += 900 // estimated pause budget
                        }

                    case .rephraseBacktrack where !upcomingWords.isEmpty:
                        let wordsForAI = Array(upcomingWords.prefix(3))
                        let phrase = wordsForAI.joined(separator: " ")
                        let aiAlt = await fetchRephraseAlternative(phrase: phrase)
                        let rephraseActions = cognitivePlanner.buildRephraseBacktrack(
                            upcomingWords: wordsForAI,
                            aiAlternative: aiAlt
                        )
                        if !rephraseActions.isEmpty {
                            actions.append(contentsOf: rephraseActions)
                            state.cursorEditsUsed += 1
                            state.lastSyntheticEventWordIndex = emittedWordIndex
                            latencyBudgetUsedMs += estimatePause(rephraseActions)
                            recentTokens.removeAll()
                        }

                    default:
                        break
                    }
                }
            }

            // Emit canonical text for this token
            actions.append(.type(token.text))

            // Update deferred insertion char counters (only after skip point is passed)
            for j in deferredInsertions.indices where !deferredInsertions[j].fired && deferredInsertions[j].counting {
                deferredInsertions[j].charsTypedSinceSkip += token.text.count
            }

            // Track recent tokens
            recentTokens.append(RecentToken(text: token.text, isWord: token.kind == .word))
            if recentTokens.count > 30 {
                recentTokens.removeFirst(recentTokens.count - 30)
            }

            if token.kind == .word {
                contextWords.append(token.text)
                if contextWords.count > 40 {
                    contextWords.removeFirst(contextWords.count - 40)
                }
                recentWords.append(token.text)
                if recentWords.count > 5 {
                    recentWords.removeFirst(recentWords.count - 5)
                }
                emittedWordIndex += 1
                // Update deferred insertion word counters (only after skip point is passed)
                for j in deferredInsertions.indices where !deferredInsertions[j].fired && deferredInsertions[j].counting {
                    deferredInsertions[j].wordsTypedSinceSkip += 1
                }
            }
        }

        // Fire any remaining deferred insertions at end of text
        for j in deferredInsertions.indices {
            if !deferredInsertions[j].fired && deferredInsertions[j].charsTypedSinceSkip > 0 {
                let ins = deferredInsertions[j]
                let noticePauseMs = Int.random(in: 300...600)
                let positionPauseMs = Int.random(in: 150...300)
                let resumePauseMs = Int.random(in: 100...200)
                actions += [
                    .pause(milliseconds: noticePauseMs),
                    .moveCursorLeft(count: ins.charsTypedSinceSkip),
                    .pause(milliseconds: positionPauseMs),
                    .syntheticType(ins.insertText),
                    .moveCursorRight(count: ins.charsTypedSinceSkip),
                    .pause(milliseconds: resumePauseMs),
                ]
                deferredInsertions[j].fired = true
            }
        }

        return actions
    }

    // MARK: - Forgotten Word: Find a skippable word in upcoming tokens

    /// Scans ahead from `startIndex` looking for a word to skip.
    /// Picks common small words ~50% of the time, any non-long word otherwise.
    /// Returns (wordTokenIndex, trailingSpaceTokenIndex?, textToInsert) or nil.
    private func findSkippableWord(
        tokens: [BoundaryToken],
        from startIndex: Int
    ) -> (Int, Int?, String)? {
        let searchEnd = min(startIndex + 14, tokens.count)
        var wordsSeen = 0
        var candidates: [(idx: Int, word: String)] = []

        for idx in startIndex..<searchEnd {
            guard tokens[idx].kind == .word else { continue }
            wordsSeen += 1
            if wordsSeen < 2 { continue }  // don't skip the very first word
            if wordsSeen > 6 { break }

            let word = tokens[idx].text
            if word.looksProtectedToken { continue }
            // Any word up to 10 chars is a candidate (people skip all kinds of words)
            if word.count <= 10 {
                candidates.append((idx, word))
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Prefer common small words ~50% of the time for realism
        let commonCandidates = candidates.filter {
            CognitiveEventPlanner.skippableWords.contains($0.word.lowercased())
        }
        let pick: (idx: Int, word: String)
        if !commonCandidates.isEmpty && Double.random(in: 0...1) < 0.5 {
            pick = commonCandidates.randomElement()!
        } else {
            pick = candidates.randomElement()!
        }

        var insertText = pick.word
        var spaceIdx: Int? = nil
        if pick.idx + 1 < tokens.count && tokens[pick.idx + 1].kind == .whitespace {
            insertText += tokens[pick.idx + 1].text
            spaceIdx = pick.idx + 1
        }
        return (pick.idx, spaceIdx, insertText)
    }

    // MARK: - Forgotten Clause: Find a clause to skip in upcoming tokens

    /// Scans ahead from `startIndex` looking for a clause between punctuation boundaries.
    /// Returns (Set<tokenIndices>, textToInsert) or nil.
    private func findSkippableClause(
        tokens: [BoundaryToken],
        from startIndex: Int
    ) -> (Set<Int>, String)? {
        let searchEnd = min(startIndex + 30, tokens.count)

        // Find punctuation boundaries ahead
        var boundaries: [Int] = []
        for idx in startIndex..<searchEnd {
            if tokens[idx].kind == .punctuation {
                let t = tokens[idx].text.trimmingCharacters(in: .whitespaces)
                if t == "." || t == "," || t == ";" {
                    boundaries.append(idx)
                }
            }
        }

        guard boundaries.count >= 2 else { return nil }

        // Pick first available clause (between first two boundaries)
        let clauseStart = boundaries[0] + 1
        let clauseEnd = boundaries[1]
        guard clauseEnd > clauseStart else { return nil }

        // Collect the clause tokens
        var clauseIndices: Set<Int> = []
        var clauseText = ""
        for idx in clauseStart...clauseEnd {
            clauseIndices.insert(idx)
            clauseText += tokens[idx].text
        }
        // Include trailing whitespace if present
        if clauseEnd + 1 < tokens.count && tokens[clauseEnd + 1].kind == .whitespace {
            clauseIndices.insert(clauseEnd + 1)
            clauseText += tokens[clauseEnd + 1].text
        }

        // Sanity: clause must be 8-80 chars and not protected
        guard clauseText.count >= 8 && clauseText.count <= 80 else { return nil }
        guard !clauseText.looksProtectedToken else { return nil }

        return (clauseIndices, clauseText)
    }

    // MARK: - Helpers

    private func fetchRephraseAlternative(phrase: String) async -> String? {
        let request = PredictionRequest(
            precedingContext: "Rephrase in different words: " + phrase,
            upcomingCanonicalWords: phrase.split(separator: " ").map(String.init),
            mode: config.mode,
            maxWords: min(4, phrase.split(separator: " ").count + 1)
        )
        if let candidate = await predictor.predictFalseStart(request: request) {
            return candidate.phrase
        }
        return nil
    }

    private func estimatePause(_ actions: [TypingAction]) -> Int {
        actions.reduce(0) { partial, action in
            if case .pause(let ms) = action { return partial + ms }
            return partial
        }
    }

    /// Get the actual text from the token buffer that covers the last N words.
    private func actualTokenText(recentTokens: [RecentToken], wordCount: Int) -> String {
        guard wordCount > 0, !recentTokens.isEmpty else { return "" }

        var wordsFound = 0
        var startIdx = recentTokens.count
        for j in stride(from: recentTokens.count - 1, through: 0, by: -1) {
            if recentTokens[j].isWord {
                wordsFound += 1
            }
            startIdx = j
            if wordsFound >= wordCount { break }
        }

        return recentTokens[startIdx...].map(\.text).joined()
    }

    private func collectUpcomingWords(tokens: [BoundaryToken], from index: Int, maxWords: Int) -> [String] {
        guard maxWords > 0 else { return [] }
        var out: [String] = []
        var i = index
        while i < tokens.count, out.count < maxWords {
            if tokens[i].kind == .word {
                out.append(tokens[i].text)
            }
            i += 1
        }
        return out
    }
}
