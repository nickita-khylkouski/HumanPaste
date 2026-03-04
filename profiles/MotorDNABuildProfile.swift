import Foundation

@main
struct MotorDNABuildProfile {
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            fputs("Usage: MotorDNABuildProfile <output_profile.json> <session1.json> [session2.json ...] [--max-gap-ms N]\n", stderr)
            exit(2)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let rest = Array(CommandLine.arguments.dropFirst(2))

        var maxGapMs = 2000.0
        var sessionPaths: [String] = []
        var i = 0
        while i < rest.count {
            if rest[i] == "--max-gap-ms", i + 1 < rest.count {
                maxGapMs = Double(rest[i + 1]) ?? maxGapMs
                i += 2
            } else {
                sessionPaths.append(rest[i])
                i += 1
            }
        }

        var sessions: [MotorDNASession] = []
        for p in sessionPaths {
            do {
                let s = try MotorDNARecorder.loadJSON(from: URL(fileURLWithPath: p))
                sessions.append(s)
            } catch {
                fputs("Failed to load session \(p): \(error.localizedDescription)\n", stderr)
                exit(2)
            }
        }

        if sessions.isEmpty {
            fputs("No sessions loaded\n", stderr)
            exit(2)
        }

        let analyzer = MotorDNAAnalyzer()
        let profile = analyzer.analyze(sessions: sessions, maxFlightGapMsForTraining: maxGapMs)

        do {
            try analyzer.saveProfile(profile, to: output)
        } catch {
            fputs("Failed to write profile: \(error.localizedDescription)\n", stderr)
            exit(2)
        }

        print("Motor DNA profile generated")
        print("- sessions: \(sessions.count)")
        print("- output: \(output.path)")
        print("- max-gap-ms: \(Int(maxGapMs))")
        print("- excluded long gaps: \(profile.excludedLongGapCount)")
        let flightBetaFmt = String(format: "%.2f", profile.personalizedCalibration.flightBeta)
        let dwellBetaFmt = String(format: "%.2f", profile.personalizedCalibration.dwellBeta)
        print("- flight alpha/beta: \(Int(profile.personalizedCalibration.flightAlphaMs)) / \(flightBetaFmt)")
        print("- dwell alpha/beta: \(Int(profile.personalizedCalibration.dwellAlphaMs)) / \(dwellBetaFmt)")
    }
}
