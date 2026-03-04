import Foundation

// MARK: - HumanTyper v3 Engine

class HumanTyper {
    // Thread-safe state (accessed from main + typingQueue + event tap thread)
    private let stateLock = NSLock()
    private var _isTyping = false
    private var _shouldCancel = false
    private var typingQueue = DispatchQueue(label: "com.humanpaste.typing", qos: .userInteractive)

    // Configuration (can be changed from settings)
    var speedProfile: SpeedProfile = speedProfileForWPM(80)
    var targetWPM: Int = 80
    var typoProfile: TypoProfile = typoProfiles["normal"]!
    var typoMultiplier: Double = 1.0
    var pauseConfig: PauseConfig = pauseConfigFromPercent(15)
    var flightCapMs: Double = 700.0
    var thinkCapMs: Double = 600.0
    var uncertaintyEnabled: Bool = false
    var uncertaintyConfig: UncertaintyConfig = .default
    var openaiApiKey: String = ""
    var correctionSpeedPct: Int = 100   // 100=normal, 200=fast corrections, 50=slow
    var burstWords: Int = 5             // words per burst phase
    var capsErrorRate: Double = 0.03    // 3% of sentence-start uppercase letters fumble shift
    var postErrorSlowdown: Bool = true  // slow down 2-3 chars after error correction (research: IKI doubles)
    let calibration: TypingCalibration

    // Callbacks
    var onTypingStarted: (() -> Void)?
    var onTypingStopped: (() -> Void)?
    var logCallback: ((String) -> Void)?
    var verboseLog: Bool = false

    init(calibration: TypingCalibration = loadTypingCalibration()) {
        self.calibration = calibration
    }

    // MARK: - Thread-Safe Accessors

    private var isTyping: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isTyping }
        set { stateLock.lock(); defer { stateLock.unlock() }; _isTyping = newValue }
    }

    private var shouldCancel: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _shouldCancel }
        set { stateLock.lock(); defer { stateLock.unlock() }; _shouldCancel = newValue }
    }

    // MARK: - Public API

    func cancel() {
        shouldCancel = true
    }

    var typing: Bool { isTyping }

    /// Correction timing multiplier: 100/pct. At 100%=1.0x, 200%=0.5x (faster), 50%=2.0x (slower)
    private var correctionMultiplier: Double {
        return 100.0 / max(25.0, Double(correctionSpeedPct))
    }

    /// Log to both NSLog and the live log callback (always shows)
    private func hpLog(_ format: String, _ args: CVarArg...) {
        let msg = String(format: format, arguments: args)
        NSLog("%@", msg)
        if let cb = logCallback {
            if headlessMode {
                cb(msg)
            } else {
                DispatchQueue.main.async { cb(msg) }
            }
        }
    }

    /// Verbose-only log — only shows in UI when verbose mode is on (always goes to NSLog)
    private func hpLogV(_ format: String, _ args: CVarArg...) {
        let msg = String(format: format, arguments: args)
        NSLog("%@", msg)
        guard verboseLog else { return }
        if let cb = logCallback {
            if headlessMode {
                cb(msg)
            } else {
                DispatchQueue.main.async { cb(msg) }
            }
        }
    }

    func typeText(_ text: String) {
        guard !isTyping else { return }
        isTyping = true
        shouldCancel = false

        DispatchQueue.main.async { self.onTypingStarted?() }

        typingQueue.async { [weak self] in
            guard let self = self else { return }
            self.performTyping(text)
            self.isTyping = false
            DispatchQueue.main.async { self.onTypingStopped?() }
        }
    }

    // MARK: - Core Typing Loop

    private func performTyping(_ text: String) {
        let cal = calibration
        let pause = pauseConfig
        let chars = Array(text)
        var i = 0
        var prevChar: Character? = nil

        // Build uncertainty injection map (empty if disabled)
        let injections = buildInjectionMap(for: text)

        // Estimate false-start overhead and speed up raw typing to compensate.
        // Each false start: ~avgPhraseLen chars typed + pause + avgPhraseLen backspaces ≈ 4-6s
        // We speed up the per-char timing by a factor so effective WPM stays near target.
        var syntheticSpeedCompensation: Double = 1.0
        if !injections.isEmpty {
            let fsCount = injections.values.reduce(0) { sum, actions in
                sum + actions.filter { if case .backspace = $0 { return true }; return false }.count.signum()
            }
            // Each false start adds ~4s overhead. Target: chars.count / targetWPM*12 seconds of pure typing.
            let targetCharsPerSec = Double(targetWPM) * 5.0 / 60.0
            let pureTypingTime = Double(chars.count) / targetCharsPerSec
            let estimatedOverhead = Double(fsCount) * 4.0  // ~4s per false start
            let totalTime = pureTypingTime + estimatedOverhead
            // Speed up raw typing so total time ≈ pureTypingTime
            syntheticSpeedCompensation = max(0.5, pureTypingTime / totalTime)
            if syntheticSpeedCompensation < 0.95 {
                hpLogV("HP: compensating for %d false starts: speed x%.2f", fsCount, 1.0 / syntheticSpeedCompensation)
            }
        }

        // Fatigue state
        var totalCharsTyped = 0
        var fatigueFactor: Double = 1.0
        var charsSinceSecondWind = 0
        var nextSecondWindAt = Int.random(in: 200...500)

        // Thinking pause state
        var charsSinceThinkingPause = 0
        var nextThinkingPauseAt = Int.random(in: 25...90)

        // "Lost thought" pause — rare, ultra-long (2% per ~300 chars)
        var charsSinceLostThought = 0
        var nextLostThoughtAt = Int.random(in: 200...500)

        // Burst state
        var burstRemaining = 0
        var burstSpeedMultiplier: Double = 1.0
        var inSlowPhase = false
        var slowRemaining = 0

        // Post-error slowing: research says IKI ~doubles after correction, decays over 3 chars
        var postErrorCharsRemaining = 0
        var postErrorTotal = 0  // how many chars total in this slowdown window

        let startTime = CFAbsoluteTimeGetCurrent()
        var charStartTime = startTime

        while i < chars.count {
            if shouldCancel { return }

            // Execute any synthetic actions at this position (false starts, cursor edits)
            if let synthetic = injections[i] {
                executeSyntheticActions(synthetic, atCharIndex: i)
                if shouldCancel { return }
            }

            charStartTime = CFAbsoluteTimeGetCurrent()

            let char = chars[i]
            let nextChar: Character? = (i + 1 < chars.count) ? chars[i + 1] : nil
            var delays: [(String, Double)] = []  // (reason, ms)

            // --- Pre-compute context ---
            let currentWord = extractCurrentWord(chars: chars, at: i)
            let wordFamMod = wordFamiliarityMultiplier(for: currentWord)

            // --- Thinking pauses (cognitive planning) ---
            if pause.thinkingScale > 0 {
                charsSinceThinkingPause += 1
                if charsSinceThinkingPause >= nextThinkingPauseAt {
                    if char == " " || prevChar == "." || prevChar == "!" || prevChar == "?" || prevChar == "\n" {
                        let rawThinkMs = logLogisticRandom(alpha: 1200.0 * pause.thinkingScale, beta: 2.2)
                        let thinkMs = min(rawThinkMs, self.thinkCapMs)
                        delays.append(("THINK", thinkMs))
                        Thread.sleep(forTimeInterval: thinkMs / 1000.0)
                        charsSinceThinkingPause = 0
                        nextThinkingPauseAt = Int.random(in: 40...120)  // less frequent
                    }
                }
            }

            // --- "Lost thought" pause ---
            if pause.lostThoughtEnabled {
                charsSinceLostThought += 1
                if charsSinceLostThought >= nextLostThoughtAt {
                    if char == " " || prevChar == "." || prevChar == "\n" {
                        if Double.random(in: 0...1) < 0.02 {
                            let lostMs = logLogisticRandom(alpha: 5000.0, beta: 2.0)
                            delays.append(("LOST_THOUGHT", lostMs))
                            Thread.sleep(forTimeInterval: lostMs / 1000.0)
                        }
                        charsSinceLostThought = 0
                        nextLostThoughtAt = Int.random(in: 200...500)
                    }
                }
            }

            // --- Fatigue modeling ---
            totalCharsTyped += 1
            charsSinceSecondWind += 1
            fatigueFactor = 1.0 + Double(totalCharsTyped) * 0.0005
            fatigueFactor = min(fatigueFactor, 1.20)
            if charsSinceSecondWind >= nextSecondWindAt {
                fatigueFactor = max(1.0, fatigueFactor - Double.random(in: 0.05...0.12))
                charsSinceSecondWind = 0
                nextSecondWindAt = Int.random(in: 200...500)
            }

            // --- Burst/slow phase management ---
            if burstRemaining <= 0 && slowRemaining <= 0 {
                let bw = Int.random(in: max(1, burstWords - 2)...(burstWords + 1))
                burstRemaining = bw * 5
                burstSpeedMultiplier = Double.random(in: 0.82...0.95)
                inSlowPhase = false
            }
            if burstRemaining > 0 {
                burstRemaining -= 1
                if burstRemaining == 0 {
                    slowRemaining = Int.random(in: 5...15)
                    inSlowPhase = true
                }
            } else if slowRemaining > 0 {
                slowRemaining -= 1
                if slowRemaining == 0 { inSlowPhase = false }
            }

            // --- Handle special characters ---
            if char == "\n" {
                emitReturn()
                let rawPauseMs = computeCognitivePause(char: char, nextChar: nextChar, calibration: cal)
                let newlinePauseMs = rawPauseMs * pause.cognitiveScale
                if newlinePauseMs > 0 {
                    delays.append(("NEWLINE", newlinePauseMs))
                    Thread.sleep(forTimeInterval: newlinePauseMs / 1000.0)
                } else if pause.cognitiveScale > 0 {
                    let fallback = logLogisticRandom(alpha: 300.0, beta: 3.0) * pause.cognitiveScale
                    delays.append(("NEWLINE", fallback))
                    Thread.sleep(forTimeInterval: fallback / 1000.0)
                }
                let elapsed = (CFAbsoluteTimeGetCurrent() - charStartTime) * 1000
                if elapsed > 300 {
                    let parts = delays.map { "\($0.0)=\(Int($0.1))ms" }.joined(separator: " ")
                    hpLogV("HP[%d] '\\n' %dms total | %@", i, Int(elapsed), parts)
                }
                prevChar = char
                i += 1
                continue
            }
            if char == "\t" {
                emitTab()
                let tabMs = logLogisticRandom(alpha: 150.0, beta: 4.0)
                Thread.sleep(forTimeInterval: tabMs / 1000.0)
                prevChar = char
                i += 1
                continue
            }

            // --- Error check ---
            // Fatigue increases error rate: research says accuracy drops first, then speed
            // fatigueFactor goes 1.0→1.20; map to error boost of 1.0→1.40 (front-loaded)
            let fatigueErrorBoost = 1.0 + (fatigueFactor - 1.0) * 2.0  // 2x leverage
            if let errorType = rollForError(char: char, profile: typoProfile, speedMultiplier: typoMultiplier * fatigueErrorBoost) {
                let consumed = executeError(errorType, chars: chars, at: i, prevChar: prevChar)
                if consumed > 0 {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - charStartTime) * 1000
                    let typoDesc: String
                    switch errorType {
                    case .substitution: typoDesc = "wrong key '\(char)'"
                    case .omission:     typoDesc = "skipped '\(char)', typed ahead \(consumed) chars, fixed"
                    case .insertion:    typoDesc = "extra key before '\(char)'"
                    case .transposition: typoDesc = "swapped '\(char)' with next char"
                    }
                    hpLog("Typo: %@ (%dms)", typoDesc, Int(elapsed))
                    prevChar = chars[min(i + consumed - 1, chars.count - 1)]
                    if postErrorSlowdown {
                        postErrorCharsRemaining = Int.random(in: 2...4)
                        postErrorTotal = postErrorCharsRemaining
                    }
                    i += consumed
                    continue
                }
            }

            // --- Capitalization fumble (missed shift at sentence start) ---
            if char.isUppercase && char.isLetter && isSentenceStart(chars: chars, at: i) {
                if Double.random(in: 0...1) < capsErrorRate {
                    let lowercase = Character(char.lowercased())
                    let dwellMs = computeDwellTime(for: lowercase, profile: speedProfile, calibration: cal)
                    emitKeystroke(lowercase, dwellMs: dwellMs)
                    // Fast notice — caps errors are caught almost immediately
                    let noticeMs = noticeDelay() * 0.6 * correctionMultiplier
                    Thread.sleep(forTimeInterval: noticeMs / 1000.0)
                    emitBackspace()
                    Thread.sleep(forTimeInterval: backspaceDelay() * correctionMultiplier / 1000.0)
                    Thread.sleep(forTimeInterval: postCorrectionPause() * correctionMultiplier / 1000.0)
                    let elapsed = (CFAbsoluteTimeGetCurrent() - charStartTime) * 1000
                    hpLog("Caps fumble: typed '%@' instead of '%@', fixed (%dms)", String(lowercase), String(char), Int(elapsed))
                    if postErrorSlowdown {
                        postErrorCharsRemaining = Int.random(in: 2...3)
                        postErrorTotal = postErrorCharsRemaining
                    }
                    // Fall through to normal shift hesitation + keystroke below
                }
            }

            // --- Compute timing ---
            let burstMod = inSlowPhase ? Double.random(in: 1.08...1.20) : burstSpeedMultiplier

            // Shift hesitation
            let shiftMs = shiftHesitation(for: char, calibration: cal)
            if shiftMs > 0 {
                delays.append(("SHIFT", shiftMs))
                Thread.sleep(forTimeInterval: shiftMs / 1000.0)
            }

            // Flight time (digraph-aware), capped to prevent fat-tail outliers
            var flightMs = computeFlightTime(from: prevChar, to: char, profile: speedProfile, calibration: cal, familiarityMod: wordFamMod)
            flightMs *= burstMod * fatigueFactor * syntheticSpeedCompensation

            // Intra-word speed gradient: word-initial is slowest, accelerates through word
            // Research: word-initial char has motor planning overhead, mid-word flows, word-final fastest
            // wordStartMultiplier already handles char 0 (after space) in computeFlightTime.
            // We add gradient for chars 1-2 (decaying slowdown) and a small speedup for word-final.
            // Only apply gradient slowdown for words with 3+ letters (2-letter words are too short).
            let wordPos = positionInCurrentWord(chars: chars, at: i)
            let wordLen = currentWord.count
            if wordLen >= 3 {
                if wordPos == 1 {
                    flightMs *= Double.random(in: 1.10...1.20)  // char 2: still planning
                } else if wordPos == 2 {
                    flightMs *= Double.random(in: 1.02...1.08)  // char 3: almost up to speed
                }
            }
            // Word-final speedup: last char before space/punct is fastest (activation gradient peak)
            if let nc = nextChar, !nc.isLetter && char.isLetter && wordPos >= 1 {
                flightMs *= Double.random(in: 0.88...0.94)
            }

            // Post-error slowing: IKI ~doubles after correction, decaying over 2-4 chars
            // Use position from start (not remaining) so first char always gets strongest slowdown
            if postErrorCharsRemaining > 0 {
                let charsSinceError = postErrorTotal - postErrorCharsRemaining  // 0 = first char
                let slowFactor: Double
                switch charsSinceError {
                case 0:    slowFactor = Double.random(in: 1.6...2.0)   // first char: strongest
                case 1:    slowFactor = Double.random(in: 1.2...1.5)   // second char: moderate
                default:   slowFactor = Double.random(in: 1.05...1.15) // third+: tapering off
                }
                flightMs *= slowFactor
                postErrorCharsRemaining -= 1
                delays.append(("POST_ERR(\(charsSinceError + 1))", flightMs * (slowFactor - 1.0)))
            }

            // Jitter: ±8% random noise on final timing to prevent detectable patterns
            // Research: detectors flag low entropy; deterministic modifiers make timing too regular
            flightMs *= Double.random(in: 0.92...1.08)

            flightMs = min(flightMs, self.flightCapMs)
            delays.append(("flight", flightMs))

            // Dwell time (finger-specific)
            let dwellMs = computeDwellTime(for: char, profile: speedProfile, calibration: cal)
            delays.append(("dwell", dwellMs))

            // Rollover check
            let doRollover = prevChar != nil
                && char.isLetter
                && prevChar!.isLetter
                && shouldUseRollover(prev: prevChar!, cur: char, calibration: cal)

            if doRollover, let prev = prevChar {
                let overlapMs = Double.random(in: 15...40)
                let adjustedFlight = max(10, flightMs - overlapMs)
                Thread.sleep(forTimeInterval: adjustedFlight / 1000.0)
                emitKeystrokeWithRollover(prev: prev, cur: char, prevDwellRemaining: overlapMs, curDwellMs: dwellMs)
                delays.append(("ROLLOVER", overlapMs))
            } else {
                Thread.sleep(forTimeInterval: flightMs / 1000.0)
                emitKeystroke(char, dwellMs: dwellMs)
            }

            // --- Post-character cognitive pause ---
            if pause.cognitiveScale > 0 {
                let cogPauseMs = computeCognitivePause(char: char, nextChar: nextChar, calibration: cal) * pause.cognitiveScale
                if cogPauseMs > 0 {
                    delays.append(("COG", cogPauseMs))
                    Thread.sleep(forTimeInterval: cogPauseMs / 1000.0)
                }
            }

            // --- Log this character ---
            let elapsed = (CFAbsoluteTimeGetCurrent() - charStartTime) * 1000
            let elapsedTotal = CFAbsoluteTimeGetCurrent() - startTime
            let charsPerSec = Double(i + 1) / elapsedTotal
            let effectiveWPM = Int(charsPerSec * 60.0 / 5.0)

            // Per-character detail (verbose only)
            let charDisplay = char == " " ? "SPC" : String(char)
            if elapsed > 300 || i < 5 || i % 20 == 0 {
                let parts = delays.map { "\($0.0)=\(Int($0.1))ms" }.joined(separator: " ")
                hpLogV("HP[%d] '%@' %dms | %@ | wpm=%d fatigue=%.2f %@",
                       i, charDisplay, Int(elapsed), parts, effectiveWPM, fatigueFactor,
                       inSlowPhase ? "SLOW" : "burst"
                )
            }

            prevChar = char
            i += 1
        }

        // Final summary
        let totalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        let finalWPM = Int(Double(chars.count) / totalElapsed * 60.0 / 5.0)
        hpLog("Done: %d chars in %.1fs, %d WPM effective (target %d)", chars.count, totalElapsed, finalWPM, targetWPM)
    }

    // MARK: - Error Execution

    private func executeError(_ type: TypoType, chars: [Character], at index: Int, prevChar: Character?) -> Int {
        let cal = calibration
        let char = chars[index]
        let cm = correctionMultiplier  // correction speed scaling

        switch type {
        case .substitution:
            guard let wrongKey = nearbyWrongKey(for: char) else { return 0 }
            let dwellMs = computeDwellTime(for: wrongKey, profile: speedProfile, calibration: cal)
            emitKeystroke(wrongKey, dwellMs: dwellMs)
            Thread.sleep(forTimeInterval: noticeDelay() * cm / 1000.0)
            emitBackspace()
            Thread.sleep(forTimeInterval: backspaceDelay() * cm / 1000.0)
            Thread.sleep(forTimeInterval: postCorrectionPause() * cm / 1000.0)
            let correctDwell = computeDwellTime(for: char, profile: speedProfile, calibration: cal)
            emitKeystroke(char, dwellMs: correctDwell)
            return 1

        case .omission:
            let aheadCount = min(charsBeforeOmissionNotice(), chars.count - index - 1)
            guard aheadCount > 0 else { return 0 }

            for j in 1...aheadCount {
                let nextChar = chars[index + j]
                let dwell = computeDwellTime(for: nextChar, profile: speedProfile, calibration: cal)
                let flight = computeFlightTime(from: j == 1 ? prevChar : chars[index + j - 1],
                                                to: nextChar, profile: speedProfile, calibration: cal, familiarityMod: 1.0)
                Thread.sleep(forTimeInterval: flight / 1000.0)
                emitKeystroke(nextChar, dwellMs: dwell)
            }

            Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 400.0, beta: 2.5) * cm / 1000.0)

            for _ in 0..<aheadCount {
                emitBackspace()
                Thread.sleep(forTimeInterval: backspaceDelay() * cm / 1000.0)
            }

            Thread.sleep(forTimeInterval: postCorrectionPause() * cm / 1000.0)

            for j in 0...aheadCount {
                let c = chars[index + j]
                let dwell = computeDwellTime(for: c, profile: speedProfile, calibration: cal)
                if j == 0 {
                    Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 120.0, beta: 4.0) / 1000.0)
                }
                emitKeystroke(c, dwellMs: dwell)
                if j < aheadCount {
                    let nextC = chars[index + j + 1]
                    let flight = computeFlightTime(from: c, to: nextC, profile: speedProfile, calibration: cal, familiarityMod: 1.0)
                    Thread.sleep(forTimeInterval: flight / 1000.0)
                }
            }

            return aheadCount + 1

        case .insertion:
            guard let extraKey = nearbyWrongKey(for: char) else { return 0 }
            let extraDwell = computeDwellTime(for: extraKey, profile: speedProfile, calibration: cal)
            emitKeystroke(extraKey, dwellMs: extraDwell)
            Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 60.0, beta: 5.0) / 1000.0)
            let charDwell = computeDwellTime(for: char, profile: speedProfile, calibration: cal)
            emitKeystroke(char, dwellMs: charDwell)
            Thread.sleep(forTimeInterval: noticeDelay() * cm / 1000.0)
            emitBackspace()
            Thread.sleep(forTimeInterval: backspaceDelay() * cm / 1000.0)
            emitBackspace()
            Thread.sleep(forTimeInterval: postCorrectionPause() * cm / 1000.0)
            emitKeystroke(char, dwellMs: charDwell)
            return 1

        case .transposition:
            guard index + 1 < chars.count else { return 0 }
            let nextChar = chars[index + 1]
            guard nextChar.isLetter else { return 0 }

            let dwell1 = computeDwellTime(for: nextChar, profile: speedProfile, calibration: cal)
            emitKeystroke(nextChar, dwellMs: dwell1)
            let flight = computeFlightTime(from: nextChar, to: char, profile: speedProfile, calibration: cal, familiarityMod: 1.0)
            Thread.sleep(forTimeInterval: flight / 1000.0)
            let dwell2 = computeDwellTime(for: char, profile: speedProfile, calibration: cal)
            emitKeystroke(char, dwellMs: dwell2)

            Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 350.0, beta: 3.0) * cm / 1000.0)

            emitBackspace()
            Thread.sleep(forTimeInterval: backspaceDelay() * cm / 1000.0)
            emitBackspace()
            Thread.sleep(forTimeInterval: postCorrectionPause() * cm / 1000.0)

            emitKeystroke(char, dwellMs: computeDwellTime(for: char, profile: speedProfile, calibration: cal))
            let flight2 = computeFlightTime(from: char, to: nextChar, profile: speedProfile, calibration: cal, familiarityMod: 1.0)
            Thread.sleep(forTimeInterval: flight2 / 1000.0)
            emitKeystroke(nextChar, dwellMs: computeDwellTime(for: nextChar, profile: speedProfile, calibration: cal))

            return 2
        }
    }

    // MARK: - Uncertainty Integration

    /// Build injection map from UncertaintyEngine actions.
    /// Maps character indices to synthetic actions that should execute before typing that char.
    private func buildInjectionMap(for text: String) -> [Int: [TypingAction]] {
        guard uncertaintyEnabled else { return [:] }

        let engine = UncertaintyEngine(
            config: uncertaintyConfig,
            predictor: PredictionProviderFactory.make(config: uncertaintyConfig, apiKeyOverride: openaiApiKey.isEmpty ? nil : openaiApiKey)
        )

        // Bridge async→sync (deterministic provider has no actual I/O)
        var actionList: [TypingAction] = []
        let sem = DispatchSemaphore(value: 0)
        Task {
            actionList = await engine.buildActions(for: text)
            sem.signal()
        }
        sem.wait()

        // Walk actions and record synthetic events at character positions.
        // Only .type() is canonical text (advances charIndex).
        // .syntheticType() and other actions are injected at the current position.
        var charIndex = 0
        var pending: [TypingAction] = []
        var injections: [Int: [TypingAction]] = [:]

        for action in actionList {
            if case .type(let chunk) = action {
                // Canonical text — flush pending synthetic actions, advance index
                if !pending.isEmpty {
                    injections[charIndex] = (injections[charIndex] ?? []) + pending
                    pending = []
                }
                charIndex += chunk.count
            } else {
                // All non-canonical actions (syntheticType, pause, backspace, etc.)
                pending.append(action)
            }
        }
        // Trailing synthetic actions
        if !pending.isEmpty {
            injections[charIndex] = (injections[charIndex] ?? []) + pending
        }

        if !injections.isEmpty {
            hpLog("Planned %d synthetic events (false starts, forgotten words, rephrases)", injections.count)
        }
        return injections
    }

    /// Execute synthetic actions (false starts, cursor edits) at injection points.
    private func executeSyntheticActions(_ actions: [TypingAction], atCharIndex idx: Int) {
        logSyntheticEvent(actions, atCharIndex: idx)
        for action in actions {
            if shouldCancel { return }

            switch action {
            case .type:
                break  // canonical .type() should never appear in injections

            case .syntheticType(let text):
                // False-start phrase or cursor retype — type with realistic timing
                var prev: Character? = nil
                for ch in text {
                    if shouldCancel { return }
                    let flightMs = computeFlightTime(from: prev, to: ch, profile: speedProfile, calibration: calibration, familiarityMod: 1.0)
                    let dwellMs = computeDwellTime(for: ch, profile: speedProfile, calibration: calibration)
                    Thread.sleep(forTimeInterval: min(flightMs, flightCapMs) / 1000.0)
                    if ch == "\n" {
                        emitReturn()
                    } else {
                        emitKeystroke(ch, dwellMs: dwellMs)
                    }
                    prev = ch
                }
                hpLogV("HP[%d] SYNTHETIC type(%d chars) \"%@\"", idx, text.count,
                       text.count > 30 ? String(text.prefix(30)) + "..." : text)

            case .pause(let ms):
                Thread.sleep(forTimeInterval: Double(ms) / 1000.0)
                hpLogV("HP[%d] SYNTHETIC pause(%dms)", idx, ms)

            case .backspace(let count):
                if count <= 4 {
                    // Short deletion: individual taps (natural)
                    for _ in 0..<count {
                        if shouldCancel { return }
                        emitBackspace()
                        Thread.sleep(forTimeInterval: backspaceDelay() / 1000.0)
                    }
                } else {
                    // Long deletion: simulate held backspace with key-repeat
                    // Real humans hold backspace — initial delay ~400ms, then repeat ~35ms
                    // First tap is always individual
                    emitBackspace()
                    Thread.sleep(forTimeInterval: backspaceDelay() / 1000.0)
                    // 1-2 more individual taps before committing to hold
                    let tapsBefore = Int.random(in: 1...2)
                    for _ in 0..<min(tapsBefore, count - 1) {
                        if shouldCancel { return }
                        emitBackspace()
                        Thread.sleep(forTimeInterval: backspaceDelay() / 1000.0)
                    }
                    // Key-repeat phase: faster, more uniform timing
                    let remaining = count - 1 - tapsBefore
                    if remaining > 0 {
                        // Initial key-repeat delay (OS-level: ~400ms but we already tapped some)
                        Thread.sleep(forTimeInterval: Double.random(in: 25...50) / 1000.0)
                        for j in 0..<remaining {
                            if shouldCancel { return }
                            emitBackspace()
                            // Key-repeat speed: ~30-45ms per char, slight acceleration
                            let repeatMs = Double.random(in: 28...42) - Double(min(j, 10)) * 0.3
                            Thread.sleep(forTimeInterval: max(20, repeatMs) / 1000.0)
                        }
                    }
                }
                hpLogV("HP[%d] SYNTHETIC backspace(%d)%@", idx, count, count > 4 ? " [held]" : "")

            case .deleteForward(let count):
                for _ in 0..<count {
                    if shouldCancel { return }
                    emitForwardDelete()
                    Thread.sleep(forTimeInterval: backspaceDelay() / 1000.0)
                }
                hpLogV("HP[%d] SYNTHETIC deleteForward(%d)", idx, count)

            case .moveCursorLeft(let count):
                for k in 0..<count {
                    if shouldCancel { return }
                    emitArrowLeft()
                    if k < count - 1 {
                        // Arrow key repeat: held arrow is faster than individual taps
                        let arrowMs = count > 5
                            ? Double.random(in: 22...35)    // held arrow: key-repeat speed
                            : Double.random(in: 40...65)    // individual taps
                        Thread.sleep(forTimeInterval: arrowMs / 1000.0)
                    }
                }
                hpLogV("HP[%d] SYNTHETIC cursorLeft(%d)", idx, count)

            case .moveCursorRight(let count):
                for k in 0..<count {
                    if shouldCancel { return }
                    emitArrowRight()
                    if k < count - 1 {
                        let arrowMs = count > 5
                            ? Double.random(in: 22...35)
                            : Double.random(in: 40...65)
                        Thread.sleep(forTimeInterval: arrowMs / 1000.0)
                    }
                }
                hpLogV("HP[%d] SYNTHETIC cursorRight(%d)", idx, count)
            }
        }
    }

    /// Log a high-level synthetic event summary (always shows in compact mode)
    private func logSyntheticEvent(_ actions: [TypingAction], atCharIndex idx: Int) {
        // Classify what kind of event this is
        let synthTexts = actions.compactMap { a -> String? in
            if case .syntheticType(let t) = a { return t }; return nil
        }
        let backspaces = actions.compactMap { a -> Int? in
            if case .backspace(let n) = a { return n }; return nil
        }
        let cursorLefts = actions.compactMap { a -> Int? in
            if case .moveCursorLeft(let n) = a { return n }; return nil
        }
        let pauses = actions.compactMap { a -> Int? in
            if case .pause(let ms) = a { return ms }; return nil
        }
        let totalPause = pauses.reduce(0, +)

        if !cursorLefts.isEmpty && synthTexts.count == 1 && backspaces.isEmpty {
            // Forgotten word/clause via cursor
            let word = synthTexts[0].trimmingCharacters(in: .whitespaces)
            if word.count <= 8 {
                hpLog("Forgot word: skipped \"%@\", went back to insert it (%dms pause)", word, totalPause)
            } else {
                hpLog("Forgot clause: skipped \"%@\", went back to insert it (%dms pause)",
                      word.count > 35 ? String(word.prefix(35)) + "..." : word, totalPause)
            }
        } else if synthTexts.count == 1 && backspaces.count == 1 {
            let typed = synthTexts[0].trimmingCharacters(in: .whitespaces)
            if typed.count <= 5 && !typed.contains(" ") {
                hpLog("Mid-word restart: typed \"%@\", hesitated, deleted it (%dms)", typed, totalPause)
            } else {
                hpLog("False start: typed \"%@\", realized wrong, deleted (%dms)",
                      typed.count > 35 ? String(typed.prefix(35)) + "..." : typed, totalPause)
            }
        } else if synthTexts.count == 1 && backspaces.count == 1 && synthTexts[0].contains(" ") {
            hpLog("Rephrase: tried \"%@\", changed mind, went back to original (%dms)",
                  synthTexts[0].trimmingCharacters(in: .whitespaces), totalPause)
        } else if synthTexts.count >= 1 {
            hpLog("Edit: %d synthetic chars, %d backspaces (%dms pause)",
                  synthTexts.reduce(0) { $0 + $1.count }, backspaces.reduce(0, +), totalPause)
        }
    }

    // MARK: - Helpers

    /// Returns the 0-based position of char within its word (0 = first letter, 1 = second, etc.)
    /// Non-letter chars return 0.
    private func positionInCurrentWord(chars: [Character], at index: Int) -> Int {
        guard chars[index].isLetter else { return 0 }
        var pos = 0
        var j = index - 1
        while j >= 0 && chars[j].isLetter {
            pos += 1
            j -= 1
        }
        return pos
    }

    private func extractCurrentWord(chars: [Character], at index: Int) -> String {
        var start = index
        while start > 0 && chars[start - 1].isLetter {
            start -= 1
        }
        var end = index
        while end < chars.count && chars[end].isLetter {
            end += 1
        }
        return String(chars[start..<end]).lowercased()
    }

    /// Returns true if position i is the start of a new sentence (where uppercase is expected).
    /// Looks back past whitespace to find the actual preceding punctuation.
    private func isSentenceStart(chars: [Character], at i: Int) -> Bool {
        if i == 0 { return true }  // start of text
        // Walk backwards past all whitespace (spaces, tabs, newlines) to find the real preceding char
        var j = i - 1
        while j >= 0 && (chars[j] == " " || chars[j] == "\t" || chars[j] == "\n") {
            j -= 1
        }
        if j < 0 { return true }  // only whitespace before us = start of text
        let prev = chars[j]
        return prev == "." || prev == "!" || prev == "?"
    }
}
