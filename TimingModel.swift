import Foundation

// MARK: - Log-Logistic Distribution

func logLogisticRandom(alpha: Double, beta: Double) -> Double {
    let u = Double.random(in: 0.0001...0.9999)
    return alpha * pow(u / (1.0 - u), 1.0 / beta)
}

private func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.max(min, Swift.min(max, value))
}

// MARK: - Dataset Calibration

struct TypingCalibration: Codable {
    let source: String
    let flightAlphaMs: Double
    let flightBeta: Double
    let dwellAlphaMs: Double
    let dwellBeta: Double
    let wordStartMultiplier: Double
    let commonWordMultiplier: Double
    let crossHandMultiplier: Double
    let sameFingerMultiplier: Double
    let rowChangeMultiplier: Double
    let numberRowMultiplier: Double
    let sentencePauseAlphaMs: Double
    let clausePauseAlphaMs: Double
    let paragraphPauseAlphaMs: Double
    let shiftHesitationAlphaMs: Double
    let rolloverCrossHandProbability: Double
    let rolloverSameHandProbability: Double

    static let `default` = TypingCalibration(
        source: "built-in",
        flightAlphaMs: 170.0,
        flightBeta: 4.4,
        dwellAlphaMs: 105.0,
        dwellBeta: 6.0,
        wordStartMultiplier: 1.35,
        commonWordMultiplier: 0.9,
        crossHandMultiplier: 0.8,
        sameFingerMultiplier: 1.4,
        rowChangeMultiplier: 1.08,
        numberRowMultiplier: 1.16,
        sentencePauseAlphaMs: 900.0,
        clausePauseAlphaMs: 420.0,
        paragraphPauseAlphaMs: 2600.0,
        shiftHesitationAlphaMs: 55.0,
        rolloverCrossHandProbability: 0.30,
        rolloverSameHandProbability: 0.08
    )
}

func loadTypingCalibration() -> TypingCalibration {
    let fm = FileManager.default
    var candidates: [URL] = []

    candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("data/calibration.json"))
    candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("HumanPaste/data/calibration.json"))

    let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
    candidates.append(bundleParent.appendingPathComponent("data/calibration.json"))

    let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    candidates.append(executableDir.appendingPathComponent("data/calibration.json"))
    candidates.append(executableDir.deletingLastPathComponent().appendingPathComponent("data/calibration.json"))

    for path in candidates {
        guard fm.fileExists(atPath: path.path) else { continue }
        do {
            let data = try Data(contentsOf: path)
            let decoded = try JSONDecoder().decode(TypingCalibration.self, from: data)
            NSLog("HumanPaste: Loaded calibration from %@", path.path)
            return decoded
        } catch {
            NSLog("HumanPaste: Failed to decode calibration at %@: %@", path.path, error.localizedDescription)
        }
    }

    NSLog("HumanPaste: Using built-in calibration defaults")
    return .default
}

// MARK: - Dynamic Speed from WPM

struct SpeedProfile {
    let name: String
    let flightScale: Double
    let dwellScale: Double
    let typoMultiplier: Double
}

/// Compute speed profile from a target WPM value.
/// Accounts for: log-logistic mean > median (1.09x), fatigue avg (1.05x),
/// burst/slow avg (1.02x), word-start penalty avg (1.05x).
/// Base overhead = 1.22x on base timing.
/// Base mean per char: flight=185ms + dwell=110ms = 295ms
/// Effective base = 295 * 1.22 = 360ms ≈ 33 WPM at scale 1.0
///
/// Additional compensation for pauses + typos: cognitive pauses and typo
/// corrections add time ON TOP of flight+dwell. We run the base faster
/// to compensate, so effective WPM matches the target.
func speedProfileForWPM(_ wpm: Int, pausePct: Int = 0, typoPct: Int = 0) -> SpeedProfile {
    // Empirical overhead from pauses (thinking + cognitive pauses per char)
    // At 100% pause: adds ~55% extra time from thinking pauses, sentence/clause pauses
    let pauseOverhead = 1.0 + Double(pausePct) / 100.0 * 0.55
    // Empirical overhead from typo corrections (notice + backspace + retype)
    // At 100% typo (2.0x multiplier): adds ~50% extra time
    let typoOverhead = 1.0 + Double(typoPct) / 100.0 * 0.50

    // Run base timing faster to account for pause+typo overhead
    let compensatedWPM = Double(wpm) * pauseOverhead * typoOverhead

    let effectiveBaseMsPerChar = 360.0  // 295ms base * 1.22 overhead
    let targetMsPerChar = 12000.0 / compensatedWPM
    let scale = targetMsPerChar / effectiveBaseMsPerChar

    // Flight gets more reduction than dwell (flight dominates timing)
    let flightScale = scale * 0.92   // flight is 63% of base
    let dwellScale = scale * 1.12    // dwell is 37% of base, keep it more natural

    // Faster typists make fewer errors
    let typoMul = min(1.3, max(0.2, Double(70) / Double(wpm)))

    return SpeedProfile(
        name: "\(wpm) WPM",
        flightScale: max(0.08, flightScale),
        dwellScale: max(0.15, dwellScale),
        typoMultiplier: typoMul
    )
}

// MARK: - Pause/Typo Config (0.0 to 1.0 continuous)

struct PauseConfig {
    let thinkingScale: Double      // 0 = off, 1 = full thinking pauses
    let cognitiveScale: Double     // 0 = off, 1 = full sentence/clause pauses
    let lostThoughtEnabled: Bool
}

func pauseConfigFromPercent(_ pct: Int) -> PauseConfig {
    let p = Double(pct) / 100.0
    return PauseConfig(
        thinkingScale: p,
        cognitiveScale: p,
        lostThoughtEnabled: pct >= 70
    )
}

// Typo rate as a percentage (0 = off, 100 = heavy)
func typoMultiplierFromPercent(_ pct: Int) -> Double {
    return Double(pct) / 50.0  // 50% = 1.0x (normal), 100% = 2.0x (heavy), 0 = off
}

// MARK: - Flight Time Calculator

func computeFlightTime(
    from prev: Character?,
    to cur: Character,
    profile: SpeedProfile,
    calibration: TypingCalibration,
    familiarityMod: Double = 1.0
) -> Double {
    guard let prev else {
        return logLogisticRandom(
            alpha: calibration.flightAlphaMs * profile.flightScale * calibration.wordStartMultiplier,
            beta: calibration.flightBeta
        )
    }

    var alpha = calibration.flightAlphaMs * profile.flightScale
    let beta = calibration.flightBeta

    if prev == " " || prev == "\n" || prev == "\t" {
        alpha *= calibration.wordStartMultiplier
    }

    let pInfo = keyInfo(for: prev)
    let cInfo = keyInfo(for: cur)

    guard let p = pInfo, let c = cInfo else {
        return clamp(logLogisticRandom(alpha: alpha, beta: beta), min: 18.0, max: 2500.0)
    }

    if prev.lowercased() == cur.lowercased() {
        alpha *= 0.85
        return clamp(logLogisticRandom(alpha: alpha, beta: beta), min: 18.0, max: 2500.0)
    }

    if p.hand != c.hand {
        let digraph = String(prev).lowercased() + String(cur).lowercased()
        alpha *= calibration.crossHandMultiplier
        if fastDigraphs.contains(digraph) {
            alpha *= 0.85
        }
    } else if p.finger != c.finger {
        let fingerDist = abs(p.finger.rawValue - c.finger.rawValue)
        if fingerDist == 1 {
            alpha *= 1.15  // adjacent fingers: biomechanical interference (slower)
        } else {
            alpha *= 1.05  // non-adjacent same-hand: less interference
        }
    } else {
        alpha *= calibration.sameFingerMultiplier
    }

    let rowDist = abs(p.row - c.row)
    if rowDist > 0 {
        alpha *= calibration.rowChangeMultiplier
    }
    if c.row == 2 {
        alpha *= calibration.numberRowMultiplier
    }

    alpha *= familiarityMod

    return clamp(logLogisticRandom(alpha: alpha, beta: beta), min: 18.0, max: 2500.0)
}

// MARK: - Dwell Time Calculator

func computeDwellTime(
    for char: Character,
    profile: SpeedProfile,
    calibration: TypingCalibration
) -> Double {
    let baseAlpha = calibration.dwellAlphaMs * profile.dwellScale
    guard let info = keyInfo(for: char) else {
        return clamp(logLogisticRandom(alpha: baseAlpha, beta: calibration.dwellBeta), min: 25.0, max: 550.0)
    }

    var alpha = baseAlpha

    switch info.finger {
    case .index:  alpha *= 0.90
    case .middle: alpha *= 1.00
    case .ring:   alpha *= 1.08
    case .pinky:  alpha *= 1.22
    case .thumb:  alpha *= 0.84
    }

    return clamp(logLogisticRandom(alpha: alpha, beta: calibration.dwellBeta), min: 25.0, max: 550.0)
}

// MARK: - Cognitive Pause Calculator

func computeCognitivePause(
    char: Character,
    nextChar: Character?,
    calibration: TypingCalibration
) -> Double {
    if char == "\n", let nextChar, nextChar == "\n" {
        return clamp(logLogisticRandom(alpha: calibration.paragraphPauseAlphaMs, beta: 2.7), min: 300.0, max: 9000.0)
    }

    if char == "." || char == "!" || char == "?" {
        return clamp(logLogisticRandom(alpha: calibration.sentencePauseAlphaMs, beta: 3.0), min: 120.0, max: 8000.0)
    }

    if char == "," || char == ";" || char == ":" {
        return clamp(logLogisticRandom(alpha: calibration.clausePauseAlphaMs, beta: 3.2), min: 80.0, max: 5000.0)
    }

    if char == " " && Double.random(in: 0...1) < 0.08 {
        return clamp(logLogisticRandom(alpha: 650.0, beta: 2.8), min: 100.0, max: 4000.0)
    }

    return 0
}

// MARK: - Rollover

func shouldUseRollover(
    prev: Character,
    cur: Character,
    calibration: TypingCalibration
) -> Bool {
    guard let p = keyInfo(for: prev), let c = keyInfo(for: cur) else { return false }
    let probability: Double
    if p.hand != c.hand {
        probability = calibration.rolloverCrossHandProbability
    } else {
        probability = calibration.rolloverSameHandProbability
    }
    return Double.random(in: 0...1) < probability
}

// MARK: - Shift Hesitation

func shiftHesitation(for char: Character, calibration: TypingCalibration) -> Double {
    if char.isUppercase && char.isLetter {
        return clamp(logLogisticRandom(alpha: calibration.shiftHesitationAlphaMs, beta: 4.0), min: 8.0, max: 500.0)
    }
    return 0
}

// MARK: - Utility

func boundedMsToSeconds(_ ms: Double) -> TimeInterval {
    let bounded = clamp(ms, min: 0.0, max: 15000.0)
    return bounded / 1000.0
}
