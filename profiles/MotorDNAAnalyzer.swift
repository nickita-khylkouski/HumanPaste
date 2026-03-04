import Foundation

private enum Hand { case left, right }
private enum Finger: Int { case pinky = 0, ring = 1, middle = 2, index = 3, thumb = 4 }

private struct KeyGeom {
    let hand: Hand
    let finger: Finger
    let row: Int
    let x: Double
    let y: Double
}

private let geom: [Character: KeyGeom] = [
    "1": .init(hand: .left, finger: .pinky, row: 2, x: 0.0, y: 0),
    "2": .init(hand: .left, finger: .ring, row: 2, x: 1.0, y: 0),
    "3": .init(hand: .left, finger: .middle, row: 2, x: 2.0, y: 0),
    "4": .init(hand: .left, finger: .index, row: 2, x: 3.0, y: 0),
    "5": .init(hand: .left, finger: .index, row: 2, x: 4.0, y: 0),
    "6": .init(hand: .right, finger: .index, row: 2, x: 5.0, y: 0),
    "7": .init(hand: .right, finger: .index, row: 2, x: 6.0, y: 0),
    "8": .init(hand: .right, finger: .middle, row: 2, x: 7.0, y: 0),
    "9": .init(hand: .right, finger: .ring, row: 2, x: 8.0, y: 0),
    "0": .init(hand: .right, finger: .pinky, row: 2, x: 9.0, y: 0),

    "q": .init(hand: .left, finger: .pinky, row: 1, x: 0.2, y: 1),
    "w": .init(hand: .left, finger: .ring, row: 1, x: 1.2, y: 1),
    "e": .init(hand: .left, finger: .middle, row: 1, x: 2.2, y: 1),
    "r": .init(hand: .left, finger: .index, row: 1, x: 3.2, y: 1),
    "t": .init(hand: .left, finger: .index, row: 1, x: 4.2, y: 1),
    "y": .init(hand: .right, finger: .index, row: 1, x: 5.2, y: 1),
    "u": .init(hand: .right, finger: .index, row: 1, x: 6.2, y: 1),
    "i": .init(hand: .right, finger: .middle, row: 1, x: 7.2, y: 1),
    "o": .init(hand: .right, finger: .ring, row: 1, x: 8.2, y: 1),
    "p": .init(hand: .right, finger: .pinky, row: 1, x: 9.2, y: 1),

    "a": .init(hand: .left, finger: .pinky, row: 0, x: 0.5, y: 2),
    "s": .init(hand: .left, finger: .ring, row: 0, x: 1.5, y: 2),
    "d": .init(hand: .left, finger: .middle, row: 0, x: 2.5, y: 2),
    "f": .init(hand: .left, finger: .index, row: 0, x: 3.5, y: 2),
    "g": .init(hand: .left, finger: .index, row: 0, x: 4.5, y: 2),
    "h": .init(hand: .right, finger: .index, row: 0, x: 5.5, y: 2),
    "j": .init(hand: .right, finger: .index, row: 0, x: 6.5, y: 2),
    "k": .init(hand: .right, finger: .middle, row: 0, x: 7.5, y: 2),
    "l": .init(hand: .right, finger: .ring, row: 0, x: 8.5, y: 2),

    "z": .init(hand: .left, finger: .pinky, row: 1, x: 0.9, y: 3),
    "x": .init(hand: .left, finger: .ring, row: 1, x: 1.9, y: 3),
    "c": .init(hand: .left, finger: .middle, row: 1, x: 2.9, y: 3),
    "v": .init(hand: .left, finger: .index, row: 1, x: 3.9, y: 3),
    "b": .init(hand: .left, finger: .index, row: 1, x: 4.9, y: 3),
    "n": .init(hand: .right, finger: .index, row: 1, x: 5.9, y: 3),
    "m": .init(hand: .right, finger: .index, row: 1, x: 6.9, y: 3),

    " ": .init(hand: .right, finger: .thumb, row: 0, x: 4.8, y: 4.0),
]

private struct Press {
    let key: Character
    let downMs: Double
    var upMs: Double?
    let character: Character?
}

struct MotorDNAAnalyzer {
    func analyze(sessions: [MotorDNASession], maxFlightGapMsForTraining: Double = 2000) -> MotorDNAProfile {
        var dwell: [Double] = []
        var flightRawAll: [Double] = []
        var flight: [Double] = []
        var crossFlights: [Double] = []
        var sameFingerFlights: [Double] = []
        var rowChangeFlights: [Double] = []
        var toNumberRowFlights: [Double] = []
        var wordStartFlights: [Double] = []

        var digraphMap: [String: [Double]] = [:]
        var distances: [Double] = []

        var totalEvents = 0
        var totalKeyDowns = 0
        var backspaces = 0
        var deleteForwards = 0

        var rolloverCount = 0
        var rolloverCross = 0
        var rolloverCrossDen = 0
        var rolloverSame = 0
        var rolloverSameDen = 0
        var excludedLongGapCount = 0

        for session in sessions {
            let events = session.events.sorted { $0.tMs < $1.tMs }
            totalEvents += events.count

            var presses: [Press] = []
            var openIdxByKey: [Character: [Int]] = [:]

            for e in events {
                switch e.kind {
                case .keyDown:
                    guard let keyChar = normalizeKey(e) else { continue }
                    let p = Press(key: keyChar, downMs: e.tMs, upMs: nil, character: e.character?.first)
                    presses.append(p)
                    openIdxByKey[keyChar, default: []].append(presses.count - 1)
                    totalKeyDowns += 1

                case .keyUp:
                    guard let keyChar = normalizeKey(e), var arr = openIdxByKey[keyChar], !arr.isEmpty else { continue }
                    let idx = arr.removeFirst()
                    openIdxByKey[keyChar] = arr
                    presses[idx].upMs = e.tMs

                case .backspace:
                    backspaces += 1
                case .deleteForward:
                    deleteForwards += 1
                case .cursorLeft, .cursorRight:
                    continue
                }
            }

            let downs = presses.sorted { $0.downMs < $1.downMs }
            for p in downs {
                if let up = p.upMs, up > p.downMs {
                    dwell.append(up - p.downMs)
                }
            }

            if downs.count < 2 {
                continue
            }

            for i in 1..<downs.count {
                let prev = downs[i - 1]
                let cur = downs[i]
                let f = cur.downMs - prev.downMs
                if f <= 0 { continue }
                flightRawAll.append(f)
                if f > maxFlightGapMsForTraining {
                    excludedLongGapCount += 1
                    continue
                }
                flight.append(f)

                if let pg = geom[prev.key], let cg = geom[cur.key] {
                    let dx = cg.x - pg.x
                    let dy = cg.y - pg.y
                    distances.append(sqrt(dx * dx + dy * dy))

                    if pg.hand != cg.hand {
                        crossFlights.append(f)
                        rolloverCrossDen += 1
                    } else {
                        rolloverSameDen += 1
                    }

                    if pg.hand == cg.hand && pg.finger == cg.finger {
                        sameFingerFlights.append(f)
                    }

                    if pg.row != cg.row {
                        rowChangeFlights.append(f)
                    }

                    if cg.row == 2 {
                        toNumberRowFlights.append(f)
                    }
                }

                if let c1 = prev.character, let c2 = cur.character, c1.isLetter, c2.isLetter {
                    let pair = String(c1).lowercased() + String(c2).lowercased()
                    digraphMap[pair, default: []].append(f)
                }

                if prev.character == " " {
                    wordStartFlights.append(f)
                }

                if let prevUp = prev.upMs, cur.downMs < prevUp {
                    rolloverCount += 1
                    if let pg = geom[prev.key], let cg = geom[cur.key], pg.hand != cg.hand {
                        rolloverCross += 1
                    } else {
                        rolloverSame += 1
                    }
                }
            }
        }

        let dwellSummary = summarize(dwell)
        let flightSummary = summarize(flight)

        let pauseSummary = buildPauseTiers(flightRawAll)
        let topDigraphs = topDigraphSummaries(digraphMap)

        let calib = buildCalibration(
            dwell: dwell,
            flight: flight,
            wordStartFlights: wordStartFlights,
            crossFlights: crossFlights,
            sameFingerFlights: sameFingerFlights,
            rowChangeFlights: rowChangeFlights,
            toNumberRowFlights: toNumberRowFlights,
            rolloverCross: rolloverCross,
            rolloverCrossDen: rolloverCrossDen,
            rolloverSame: rolloverSame,
            rolloverSameDen: rolloverSameDen
        )

        let keyDownCount = max(1, totalKeyDowns)
        let transitions = max(1, flight.count)
        let profile = MotorDNAProfile(
            generatedAtISO8601: nowISO8601(),
            userId: sessions.first?.meta.userId ?? "unknown",
            sessionCount: sessions.count,
            totalEvents: totalEvents,
            dwellMs: dwellSummary,
            flightMs: flightSummary,
            keyDistance: KeyDistanceSummary(
                count: distances.count,
                meanDistance: mean(distances),
                p50Distance: percentile(distances, 0.5),
                p95Distance: percentile(distances, 0.95)
            ),
            rolloverRate: Double(rolloverCount) / Double(transitions),
            backspaceRate: Double(backspaces) / Double(keyDownCount),
            deleteForwardRate: Double(deleteForwards) / Double(keyDownCount),
            pauseTiers: pauseSummary,
            longGapThresholdMs: maxFlightGapMsForTraining,
            excludedLongGapCount: excludedLongGapCount,
            topDigraphs: topDigraphs,
            personalizedCalibration: calib,
            notes: [
                "Consent-based calibration sessions only.",
                "By default, use timing features and avoid storing arbitrary plaintext.",
                "Long gaps above threshold are excluded from calibration features.",
                "Load personalizedCalibration into the main engine after review by software team."
            ]
        )

        return profile
    }

    func saveProfile(_ profile: MotorDNAProfile, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(profile)
        try data.write(to: url)
    }

    private func normalizeKey(_ e: MotorDNAEvent) -> Character? {
        if let k = e.key?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
            if k.lowercased() == "space" { return " " }
            if k.count == 1 { return Character(k.lowercased()) }
        }
        if let code = e.keyCode, let fromCode = keyFromCode(code) {
            return fromCode
        }
        if let c = e.character?.first {
            return Character(String(c).lowercased())
        }
        return nil
    }

    private func keyFromCode(_ code: Int) -> Character? {
        switch code {
        case 49: return " "   // space
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        default: return nil
        }
    }

    private func buildPauseTiers(_ flights: [Double]) -> PauseTierSummary {
        guard !flights.isEmpty else {
            return PauseTierSummary(motorPct: 0, thinkingPct: 0, planningPct: 0)
        }
        var motor = 0
        var thinking = 0
        var planning = 0
        for f in flights {
            if f < 200 { motor += 1 }
            else if f <= 2000 { thinking += 1 }
            else { planning += 1 }
        }
        let n = Double(flights.count)
        return PauseTierSummary(
            motorPct: Double(motor) / n,
            thinkingPct: Double(thinking) / n,
            planningPct: Double(planning) / n
        )
    }

    private func topDigraphSummaries(_ map: [String: [Double]]) -> [DigraphSummary] {
        map.compactMap { pair, vals in
            guard vals.count >= 6 else { return nil }
            return DigraphSummary(
                pair: pair,
                count: vals.count,
                medianFlightMs: percentile(vals, 0.5),
                meanFlightMs: mean(vals)
            )
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.medianFlightMs < rhs.medianFlightMs
            }
            return lhs.count > rhs.count
        }
        .prefix(30)
        .map { $0 }
    }

    private func buildCalibration(
        dwell: [Double],
        flight: [Double],
        wordStartFlights: [Double],
        crossFlights: [Double],
        sameFingerFlights: [Double],
        rowChangeFlights: [Double],
        toNumberRowFlights: [Double],
        rolloverCross: Int,
        rolloverCrossDen: Int,
        rolloverSame: Int,
        rolloverSameDen: Int
    ) -> PersonalCalibration {
        let dwellAlpha = clamp(percentile(dwell, 0.5), 45, 220)
        let dwellBeta = fitLogLogisticBeta(dwell, fallback: 5.5)

        let flightAlpha = clamp(percentile(flight, 0.5), 70, 600)
        let flightBeta = fitLogLogisticBeta(flight, fallback: 3.8)

        let wordStart = clamp(percentile(wordStartFlights, 0.5) / max(1, flightAlpha), 1.05, 2.2)
        let cross = clamp(percentile(crossFlights, 0.5) / max(1, flightAlpha), 0.55, 1.1)
        let sameFinger = clamp(percentile(sameFingerFlights, 0.5) / max(1, flightAlpha), 1.0, 2.6)
        let rowChange = clamp(percentile(rowChangeFlights, 0.5) / max(1, flightAlpha), 0.95, 1.4)
        let numRow = clamp(percentile(toNumberRowFlights, 0.5) / max(1, flightAlpha), 1.0, 1.6)

        let crossRoll = clamp(Double(rolloverCross) / Double(max(1, rolloverCrossDen)), 0.0, 0.8)
        let sameRoll = clamp(Double(rolloverSame) / Double(max(1, rolloverSameDen)), 0.0, 0.4)

        return PersonalCalibration(
            source: "motordna_personal_profile",
            flightAlphaMs: flightAlpha,
            flightBeta: flightBeta,
            dwellAlphaMs: dwellAlpha,
            dwellBeta: dwellBeta,
            wordStartMultiplier: wordStart,
            commonWordMultiplier: 0.90,
            crossHandMultiplier: cross,
            sameFingerMultiplier: sameFinger,
            rowChangeMultiplier: rowChange,
            numberRowMultiplier: numRow,
            sentencePauseAlphaMs: 920,
            clausePauseAlphaMs: 430,
            paragraphPauseAlphaMs: 2700,
            shiftHesitationAlphaMs: 58,
            rolloverCrossHandProbability: crossRoll,
            rolloverSameHandProbability: sameRoll
        )
    }
}
