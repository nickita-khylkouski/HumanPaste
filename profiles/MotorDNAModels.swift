import Foundation

enum MotorEventKind: String, Codable {
    case keyDown
    case keyUp
    case backspace
    case deleteForward
    case cursorLeft
    case cursorRight
}

struct MotorDNAEvent: Codable {
    let tMs: Double
    let kind: MotorEventKind
    let key: String?
    let keyCode: Int?
    let character: String?
    let app: String?
    let cursorIndex: Int?
}

struct MotorDNASessionMeta: Codable {
    let sessionId: String
    let createdAtISO8601: String
    let userId: String
    let consentToken: String
    let captureContent: Bool
    let appContext: String
    let promptId: String?
    let promptText: String?
}

struct MotorDNASession: Codable {
    let meta: MotorDNASessionMeta
    let events: [MotorDNAEvent]
}

struct DistributionSummary: Codable {
    let count: Int
    let min: Double
    let p05: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p95: Double
    let max: Double
    let mean: Double
    let stddev: Double
}

struct DigraphSummary: Codable {
    let pair: String
    let count: Int
    let medianFlightMs: Double
    let meanFlightMs: Double
}

struct KeyDistanceSummary: Codable {
    let count: Int
    let meanDistance: Double
    let p50Distance: Double
    let p95Distance: Double
}

struct PauseTierSummary: Codable {
    let motorPct: Double      // <200ms
    let thinkingPct: Double   // 200ms..2000ms
    let planningPct: Double   // >2000ms
}

struct PersonalCalibration: Codable {
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
}

struct MotorDNAProfile: Codable {
    let generatedAtISO8601: String
    let userId: String
    let sessionCount: Int
    let totalEvents: Int

    let dwellMs: DistributionSummary
    let flightMs: DistributionSummary

    let keyDistance: KeyDistanceSummary
    let rolloverRate: Double
    let backspaceRate: Double
    let deleteForwardRate: Double
    let pauseTiers: PauseTierSummary
    let longGapThresholdMs: Double
    let excludedLongGapCount: Int

    let topDigraphs: [DigraphSummary]
    let personalizedCalibration: PersonalCalibration

    let notes: [String]
}

// MARK: - Stats

func percentile(_ values: [Double], _ q: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let s = values.sorted()
    let qq = max(0, min(1, q))
    let idx = Int(Double(s.count - 1) * qq)
    return s[idx]
}

func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

func stddev(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let m = mean(values)
    let varSum = values.reduce(0) { $0 + (($1 - m) * ($1 - m)) }
    return sqrt(varSum / Double(values.count))
}

func summarize(_ values: [Double]) -> DistributionSummary {
    let s = values.sorted()
    if s.isEmpty {
        return DistributionSummary(count: 0, min: 0, p05: 0, p25: 0, p50: 0, p75: 0, p95: 0, max: 0, mean: 0, stddev: 0)
    }
    return DistributionSummary(
        count: s.count,
        min: s.first ?? 0,
        p05: percentile(s, 0.05),
        p25: percentile(s, 0.25),
        p50: percentile(s, 0.50),
        p75: percentile(s, 0.75),
        p95: percentile(s, 0.95),
        max: s.last ?? 0,
        mean: mean(s),
        stddev: stddev(s)
    )
}

func fitLogLogisticBeta(_ values: [Double], fallback: Double) -> Double {
    guard values.count >= 20 else { return fallback }
    let q25 = percentile(values, 0.25)
    let q75 = percentile(values, 0.75)
    guard q25 > 0, q75 > q25 else { return fallback }
    let denom = log(q75 / q25)
    guard denom > 0 else { return fallback }
    // beta = 2*ln(3) / ln(q75/q25)
    let beta = (2.0 * log(3.0)) / denom
    return max(1.2, min(12.0, beta))
}

func nowISO8601() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    max(low, min(high, value))
}
