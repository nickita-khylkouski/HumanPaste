import Foundation

private func syntheticSession() -> MotorDNASession {
    let meta = MotorDNASessionMeta(
        sessionId: UUID().uuidString,
        createdAtISO8601: nowISO8601(),
        userId: "test-user",
        consentToken: "consent-test",
        captureContent: true,
        appContext: "self-test",
        promptId: "p1",
        promptText: "the quick brown fox"
    )

    var t: Double = 0
    var events: [MotorDNAEvent] = []

    func key(_ ch: Character, dwell: Double, flightAfter: Double) {
        events.append(MotorDNAEvent(tMs: t, kind: .keyDown, key: String(ch), keyCode: nil, character: String(ch), app: "self-test", cursorIndex: nil))
        t += dwell
        events.append(MotorDNAEvent(tMs: t, kind: .keyUp, key: String(ch), keyCode: nil, character: String(ch), app: "self-test", cursorIndex: nil))
        t += flightAfter
    }

    for ch in "the quick brown fox jumps over the lazy dog" {
        if ch == " " {
            key(" ", dwell: 72, flightAfter: 118)
        } else {
            let dwell = Double.random(in: 80...120)
            let flight = Double.random(in: 95...220)
            key(ch, dwell: dwell, flightAfter: flight)
        }

        if Double.random(in: 0...1) < 0.04 {
            events.append(MotorDNAEvent(tMs: t, kind: .backspace, key: "Backspace", keyCode: 51, character: nil, app: "self-test", cursorIndex: nil))
            t += 65
        }
    }

    return MotorDNASession(meta: meta, events: events)
}

@main
struct MotorDNASelfTest {
    static func main() {
        var sessions: [MotorDNASession] = []
        for _ in 0..<5 {
            sessions.append(syntheticSession())
        }

        let analyzer = MotorDNAAnalyzer()
        let profile = analyzer.analyze(sessions: sessions)

        var failures: [String] = []
        if profile.sessionCount != 5 { failures.append("session_count") }
        if profile.totalEvents <= 0 { failures.append("total_events") }
        if profile.dwellMs.p50 <= 0 { failures.append("dwell_p50") }
        if profile.flightMs.p50 <= 0 { failures.append("flight_p50") }
        if profile.personalizedCalibration.flightAlphaMs <= 0 { failures.append("flight_alpha") }
        if profile.personalizedCalibration.dwellAlphaMs <= 0 { failures.append("dwell_alpha") }

        print("MotorDNA self-test")
        print("- sessions: \(profile.sessionCount)")
        print("- total events: \(profile.totalEvents)")
        print("- dwell p50: \(Int(profile.dwellMs.p50))ms")
        print("- flight p50: \(Int(profile.flightMs.p50))ms")
        let rolloverFmt = String(format: "%.3f", profile.rolloverRate)
        let backspaceFmt = String(format: "%.3f", profile.backspaceRate)
        print("- rollover rate: \(rolloverFmt)")
        print("- backspace rate: \(backspaceFmt)")
        print("- result: \(failures.isEmpty ? "PASS" : "FAIL")")

        if !failures.isEmpty {
            print("- failures: \(failures.joined(separator: ", "))")
            exit(2)
        }

        let out = URL(fileURLWithPath: "/tmp/motordna_profile_selftest.json")
        do {
            try analyzer.saveProfile(profile, to: out)
            print("- wrote: \(out.path)")
        } catch {
            print("- save failed: \(error.localizedDescription)")
            exit(2)
        }
    }
}
