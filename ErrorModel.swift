import Foundation

// MARK: - Error Types

enum TypoType {
    case substitution   // wrong adjacent key
    case omission       // skip a character
    case insertion      // extra character
    case transposition  // swap two adjacent chars
}

// MARK: - Typo Rate Profiles

struct TypoProfile {
    let name: String
    let substitutionRate: Double
    let omissionRate: Double
    let insertionRate: Double
    let transpositionRate: Double

    var totalRate: Double {
        substitutionRate + omissionRate + insertionRate + transpositionRate
    }
}

let typoProfiles: [String: TypoProfile] = [
    "off":    TypoProfile(name: "Off",    substitutionRate: 0,      omissionRate: 0,     insertionRate: 0,      transpositionRate: 0),
    "light":  TypoProfile(name: "Light",  substitutionRate: 0.005,  omissionRate: 0.002,  insertionRate: 0.002, transpositionRate: 0.0002),
    "normal": TypoProfile(name: "Normal", substitutionRate: 0.014,  omissionRate: 0.0025, insertionRate: 0.0029, transpositionRate: 0.0006),
    "heavy":  TypoProfile(name: "Heavy",  substitutionRate: 0.028,  omissionRate: 0.005,  insertionRate: 0.006,  transpositionRate: 0.0012),
]

// MARK: - Error Decision

func rollForError(char: Character, profile: TypoProfile, speedMultiplier: Double) -> TypoType? {
    guard char.isLetter else { return nil }

    let roll = Double.random(in: 0...1)
    let sub = profile.substitutionRate * speedMultiplier
    let omi = profile.omissionRate * speedMultiplier
    let ins = profile.insertionRate * speedMultiplier
    let tra = profile.transpositionRate * speedMultiplier

    if roll < sub { return .substitution }
    if roll < sub + omi { return .omission }
    if roll < sub + omi + ins { return .insertion }
    if roll < sub + omi + ins + tra { return .transposition }
    return nil
}

// MARK: - Error Execution Helpers

/// How long to pause before noticing an error (ms)
/// Research: ~60% immediate catches, ~40% delayed realization
func noticeDelay() -> Double {
    if Double.random(in: 0...1) < 0.6 {
        return logLogisticRandom(alpha: 80.0, beta: 5.0)   // quick: 50-120ms
    } else {
        return logLogisticRandom(alpha: 250.0, beta: 3.5)  // slow: 150-500ms
    }
}

/// Inter-backspace delay (rapid, frustrated deletion) in ms
/// Research: correction-related inter-event timings ~100-170ms bands
func backspaceDelay() -> Double {
    return logLogisticRandom(alpha: 100.0, beta: 5.0)  // 65-150ms, realistic
}

/// Pause after correction before resuming normal typing (ms)
/// Research: post-correction recovery ~160-200ms
func postCorrectionPause() -> Double {
    return logLogisticRandom(alpha: 165.0, beta: 3.8)  // 100-280ms, regaining rhythm
}

/// For omission: how many chars typed before noticing the skip
func charsBeforeOmissionNotice() -> Int {
    return Int.random(in: 1...3)
}

/// For late correction: how many chars back to correct
func lateNoticeDistance() -> Int {
    return Int.random(in: 2...4)
}
