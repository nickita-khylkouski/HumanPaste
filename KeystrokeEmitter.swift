import Cocoa

// MARK: - Headless Mode (no CGEvents, for testing)

/// When true, all CGEvent posting is skipped (emitters become no-ops).
/// Set by --headless CLI flag. Timing/logic still executes normally.
var headlessMode = false

// MARK: - CGEvent Keystroke Emitter

/// Shared event source for consistent keystroke simulation
private let eventSource = CGEventSource(stateID: .hidSystemState)

/// Post a keyDown event for a Unicode character
func postKeyDown(_ char: Character) {
    guard !headlessMode else { return }
    let unichars = Array(String(char).utf16)
    guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else { return }
    event.keyboardSetUnicodeString(stringLength: unichars.count, unicodeString: unichars)
    event.flags = []
    event.post(tap: .cghidEventTap)
}

/// Post a keyUp event for a Unicode character
func postKeyUp(_ char: Character) {
    guard !headlessMode else { return }
    let unichars = Array(String(char).utf16)
    guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else { return }
    event.keyboardSetUnicodeString(stringLength: unichars.count, unicodeString: unichars)
    event.flags = []
    event.post(tap: .cghidEventTap)
}

/// Post backspace (Delete key, virtualKey 51)
func postBackspace() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

/// Post Return/Enter (virtualKey 36)
func postReturn() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 36, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 36, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

/// Post Tab (virtualKey 48)
func postTab() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 48, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 48, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

/// Post Forward Delete (virtualKey 117, Fn+Delete on Mac)
func postForwardDelete() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 117, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 117, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

/// Post Left Arrow (virtualKey 123)
func postArrowLeft() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 123, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

/// Post Right Arrow (virtualKey 124)
func postArrowRight() {
    guard !headlessMode else { return }
    if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 124, keyDown: true) {
        down.flags = []
        down.post(tap: .cghidEventTap)
    }
    if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 124, keyDown: false) {
        up.flags = []
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - High-Level Keystroke Functions

/// Type a single character with realistic dwell time (no flight — caller handles that)
func emitKeystroke(_ char: Character, dwellMs: Double) {
    postKeyDown(char)
    Thread.sleep(forTimeInterval: dwellMs / 1000.0)
    postKeyUp(char)
}

/// Type a character with rollover: next keyDown fires before current keyUp
/// Returns the time when keyUp was posted (for tracking)
func emitKeystrokeWithRollover(prev: Character, cur: Character, prevDwellRemaining: Double, curDwellMs: Double) {
    // The previous key is still "held" — post current keyDown now (overlap)
    postKeyDown(cur)

    // Release previous key after remaining dwell
    if prevDwellRemaining > 0 {
        Thread.sleep(forTimeInterval: prevDwellRemaining / 1000.0)
    }
    postKeyUp(prev)

    // Hold current key for its dwell
    Thread.sleep(forTimeInterval: curDwellMs / 1000.0)
    postKeyUp(cur)
}

/// Type a backspace with realistic dwell
func emitBackspace() {
    postBackspace()
    // Backspace dwell is shorter — quick angry tap
    Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 60.0, beta: 7.0) / 1000.0)
}

/// Type Return with pause
func emitReturn() {
    postReturn()
}

/// Type Tab
func emitTab() {
    postTab()
}

/// Forward delete with realistic dwell
func emitForwardDelete() {
    postForwardDelete()
    Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 55.0, beta: 7.0) / 1000.0)
}

/// Left arrow with short dwell
func emitArrowLeft() {
    postArrowLeft()
    Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 40.0, beta: 8.0) / 1000.0)
}

/// Right arrow with short dwell
func emitArrowRight() {
    postArrowRight()
    Thread.sleep(forTimeInterval: logLogisticRandom(alpha: 40.0, beta: 8.0) / 1000.0)
}
