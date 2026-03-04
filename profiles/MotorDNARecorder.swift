import Foundation

/// Consent-based recorder for calibration sessions only.
/// This recorder is not a global keylogger; wire it only into explicit calibration flows.
final class MotorDNARecorder {
    private(set) var meta: MotorDNASessionMeta
    private(set) var events: [MotorDNAEvent] = []
    private let startedAt = CFAbsoluteTimeGetCurrent()

    init(
        userId: String,
        consentToken: String,
        captureContent: Bool,
        appContext: String,
        promptId: String? = nil,
        promptText: String? = nil
    ) {
        precondition(!userId.isEmpty, "userId required")
        precondition(!consentToken.isEmpty, "consentToken required")

        self.meta = MotorDNASessionMeta(
            sessionId: UUID().uuidString,
            createdAtISO8601: nowISO8601(),
            userId: userId,
            consentToken: consentToken,
            captureContent: captureContent,
            appContext: appContext,
            promptId: promptId,
            promptText: promptText
        )
    }

    private func tMs() -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0
    }

    func recordKeyDown(key: String, keyCode: Int? = nil, character: Character?, app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(
            tMs: tMs(),
            kind: .keyDown,
            key: key,
            keyCode: keyCode,
            character: meta.captureContent ? character.map { String($0) } : nil,
            app: app,
            cursorIndex: cursorIndex
        ))
    }

    func recordKeyUp(key: String, keyCode: Int? = nil, character: Character?, app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(
            tMs: tMs(),
            kind: .keyUp,
            key: key,
            keyCode: keyCode,
            character: meta.captureContent ? character.map { String($0) } : nil,
            app: app,
            cursorIndex: cursorIndex
        ))
    }

    func recordBackspace(app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(tMs: tMs(), kind: .backspace, key: "Backspace", keyCode: 51, character: nil, app: app, cursorIndex: cursorIndex))
    }

    func recordDeleteForward(app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(tMs: tMs(), kind: .deleteForward, key: "DeleteForward", keyCode: 117, character: nil, app: app, cursorIndex: cursorIndex))
    }

    func recordCursorLeft(app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(tMs: tMs(), kind: .cursorLeft, key: "LeftArrow", keyCode: 123, character: nil, app: app, cursorIndex: cursorIndex))
    }

    func recordCursorRight(app: String? = nil, cursorIndex: Int? = nil) {
        events.append(MotorDNAEvent(tMs: tMs(), kind: .cursorRight, key: "RightArrow", keyCode: 124, character: nil, app: app, cursorIndex: cursorIndex))
    }

    func finalizeSession() -> MotorDNASession {
        MotorDNASession(meta: meta, events: events.sorted { $0.tMs < $1.tMs })
    }

    func saveJSON(to url: URL) throws {
        let session = finalizeSession()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(session)
        try data.write(to: url)
    }

    static func loadJSON(from url: URL) throws -> MotorDNASession {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MotorDNASession.self, from: data)
    }
}
