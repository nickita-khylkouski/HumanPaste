import Foundation

protocol PredictionProvider {
    func predictFalseStart(request: PredictionRequest) async -> PredictionCandidate?
}

struct PredictionProviderFactory {
    /// If an API key is available (env or passed), use OpenAI. Otherwise deterministic fallback.
    static func make(config: UncertaintyConfig, apiKeyOverride: String? = nil) -> PredictionProvider {
        let key = apiKeyOverride
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""

        if !key.isEmpty {
            NSLog("HP PREDICTION: using OpenAI (%@)", config.openAIModel)
            return OpenAIPredictionProvider(
                apiKey: key,
                model: config.openAIModel,
                timeoutMs: config.openAITimeoutMs
            )
        }

        NSLog("HP PREDICTION: using deterministic fallback (set OPENAI_API_KEY or paste key in settings)")
        return DeterministicPredictionProvider()
    }
}

// MARK: - OpenAI Provider (primary — just asks LLM to continue the text)

struct OpenAIPredictionProvider: PredictionProvider {
    let apiKey: String
    let model: String
    let timeoutMs: Int

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_completion_tokens: Int
    }

    private struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    func predictFalseStart(request: PredictionRequest) async -> PredictionCandidate? {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return nil
        }

        // Dead simple: just continue the text. The LLM doesn't know the real next words,
        // so its prediction will naturally be different but contextually plausible.
        let prompt = """
        Continue this text with exactly \(request.maxWords) words. Output ONLY the \(request.maxWords) words, nothing else. No punctuation at the end.

        ...\(request.precedingContext.suffix(300))
        """

        let payload = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "user", content: prompt)
            ],
            temperature: 0.9,
            max_completion_tokens: 30
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            req.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else { return nil }

            // Clean: strip quotes, punctuation, trim to maxWords
            let cleaned = content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .punctuationCharacters)

            let words = cleaned.split(separator: " ").prefix(request.maxWords)
            let phrase = words.joined(separator: " ").lowercased()

            guard phrase.wordCountApprox >= 2 else { return nil }
            guard !phrase.looksProtectedToken else { return nil }

            return PredictionCandidate(phrase: phrase, confidence: 0.8)
        } catch {
            NSLog("HP PREDICTION error: %@", error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Deterministic Fallback (no API key — less good but works offline)

struct DeterministicPredictionProvider: PredictionProvider {

    // Common continuation phrases grouped by last-word patterns
    private static let continuations: [String: [String]] = [
        "the": ["process of", "development of", "implementation", "significance of", "overall impact"],
        "a": ["comprehensive approach", "significant amount", "different perspective", "fundamental change"],
        "to": ["effectively manage", "better understand", "significantly improve", "properly address"],
        "in": ["various aspects", "the context of", "many different", "a similar fashion"],
        "of": ["these particular", "the underlying", "various different", "a comprehensive"],
        "and": ["subsequently the", "furthermore the", "additionally we", "moreover this"],
        "is": ["fundamentally about", "particularly important", "essentially the", "primarily focused"],
        "that": ["would potentially", "could significantly", "might eventually", "has consistently"],
        "with": ["considerable effort", "the understanding", "various different", "particular emphasis"],
        "for": ["the development", "a comprehensive", "various reasons", "the implementation"],
        "have": ["consistently shown", "significantly improved", "fundamentally changed", "recently discovered"],
        "are": ["particularly well", "fundamentally different", "increasingly common", "primarily designed"],
        "from": ["a different", "the perspective", "various sources", "multiple angles"],
        "by": ["carefully analyzing", "implementing various", "considering the", "exploring different"],
        "has": ["significantly impacted", "fundamentally altered", "consistently demonstrated", "recently emerged"],
        "been": ["consistently improving", "significantly reduced", "fundamentally transformed", "widely recognized"],
    ]

    private static let genericPhrases: [String] = [
        "the underlying mechanisms",
        "a different approach",
        "various important aspects",
        "the fundamental principles",
        "significantly more effective",
        "particularly in cases",
        "the overall performance",
        "increasingly sophisticated methods",
        "a comprehensive framework",
        "the development process",
        "multiple different factors",
        "considerable progress in",
        "the resulting improvements",
        "important considerations for",
        "effectively addressing the",
        "the practical implications",
        "a systematic approach",
        "the relevant factors",
        "substantial improvements in",
        "the broader context",
    ]

    func predictFalseStart(request: PredictionRequest) async -> PredictionCandidate? {
        guard !request.upcomingCanonicalWords.isEmpty else { return nil }

        let contextWords = request.precedingContext
            .split(separator: " ")
            .map { String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) }
        let lastWord = contextWords.last ?? ""

        let upcomingSet = Set(request.upcomingCanonicalWords.map { $0.lowercased() })

        if let candidates = Self.continuations[lastWord] {
            let filtered = candidates.filter { phrase in
                !phrase.split(separator: " ").contains { upcomingSet.contains(String($0).lowercased()) }
            }
            if let pick = filtered.randomElement() {
                let words = pick.split(separator: " ").prefix(request.maxWords)
                let phrase = words.joined(separator: " ")
                if phrase.wordCountApprox >= request.maxWords - 1 {
                    return PredictionCandidate(phrase: phrase, confidence: 0.55)
                }
            }
        }

        let shuffled = Self.genericPhrases.shuffled()
        for phrase in shuffled {
            let phraseWords = Set(phrase.split(separator: " ").map { String($0).lowercased() })
            if phraseWords.isDisjoint(with: upcomingSet) {
                let trimmed = phrase.split(separator: " ").prefix(request.maxWords).joined(separator: " ")
                return PredictionCandidate(phrase: trimmed, confidence: 0.42)
            }
        }

        if let phrase = shuffled.first {
            let trimmed = phrase.split(separator: " ").prefix(request.maxWords).joined(separator: " ")
            return PredictionCandidate(phrase: trimmed, confidence: 0.3)
        }

        return nil
    }
}

// MARK: - Cloud Provider (custom endpoint)

struct CloudPredictionProvider: PredictionProvider {
    let endpoint: URL
    let apiKey: String?
    let timeoutMs: Int

    private struct CloudRequest: Codable {
        let preceding_context: String
        let upcoming_canonical_words: [String]
        let mode: String
        let max_words: Int
    }

    func predictFalseStart(request: PredictionRequest) async -> PredictionCandidate? {
        var urlReq = URLRequest(url: endpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlReq.timeoutInterval = TimeInterval(timeoutMs) / 1000.0

        let payload = CloudRequest(
            preceding_context: request.precedingContext,
            upcoming_canonical_words: request.upcomingCanonicalWords,
            mode: request.mode,
            max_words: request.maxWords
        )

        do {
            urlReq.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await URLSession.shared.data(for: urlReq)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let candidate = try JSONDecoder().decode(PredictionCandidate.self, from: data)
            return sanitize(candidate: candidate, maxWords: request.maxWords)
        } catch {
            return nil
        }
    }
}

private func sanitize(candidate: PredictionCandidate, maxWords: Int) -> PredictionCandidate? {
    let phrase = candidate.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !phrase.isEmpty else { return nil }
    if phrase.looksProtectedToken { return nil }
    if phrase.wordCountApprox < 2 || phrase.wordCountApprox > maxWords { return nil }

    let confidence = max(0.0, min(1.0, candidate.confidence))
    return PredictionCandidate(phrase: phrase, confidence: confidence)
}
