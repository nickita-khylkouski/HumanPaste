import Foundation
import CoreGraphics

enum TimingEventKind: String, Codable {
    case sessionStart = "session_start"
    case sessionStop = "session_stop"
    case idleGap = "idle_gap"
    case down
    case up
}

enum KeyCategory: String, Codable {
    case letter
    case number
    case symbol
    case whitespace
    case editing
    case navigation
    case modifier
    case functionKey = "function"
    case unknown
    case idle
}

struct TimingEvent: Codable {
    let kind: TimingEventKind
    let tMs: Double
    let category: KeyCategory
    let subCategory: String?
    let keyCode: Int?
    let modifiers: [String]?
    let autoRepeat: Bool?

    // Optional fields depending on event kind
    let dwellMs: Double?
    let gapMs: Double?
    let source: String?
}

struct TimingSessionHeader: Codable {
    let kind: TimingEventKind
    let startedAtISO8601: String
    let machine: String
    let version: String
    let idleGapThresholdMs: Double
    let captureContent: Bool
    let notes: [String]
}

func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

func hostname() -> String {
    ProcessInfo.processInfo.hostName
}

func keyCategory(for keyCode: CGKeyCode, flags: CGEventFlags) -> KeyCategory {
    let letters: Set<CGKeyCode> = [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
        45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6
    ]
    let numbers: Set<CGKeyCode> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    let symbols: Set<CGKeyCode> = [24, 27, 30, 33, 39, 41, 42, 43, 44, 47, 50]
    let keypadSymbols: Set<CGKeyCode> = [65, 67, 69, 75, 78, 81]
    let whitespace: Set<CGKeyCode> = [49, 36, 48, 76]
    let editing: Set<CGKeyCode> = [51, 117, 71]
    let navigation: Set<CGKeyCode> = [53, 123, 124, 125, 126, 115, 119, 116, 121, 114]
    let modifiers: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    let functionKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    if modifiers.contains(keyCode) {
        return .modifier
    }
    if letters.contains(keyCode) { return .letter }
    if numbers.contains(keyCode) { return .number }
    if symbols.contains(keyCode) || keypadSymbols.contains(keyCode) { return .symbol }
    if whitespace.contains(keyCode) { return .whitespace }
    if editing.contains(keyCode) { return .editing }
    if navigation.contains(keyCode) { return .navigation }
    if functionKeys.contains(keyCode) { return .functionKey }
    return .unknown
}

func keySubCategory(for keyCode: CGKeyCode, flags: CGEventFlags) -> String? {
    let shift = flags.contains(.maskShift)

    switch keyCode {
    case 49: return "space"
    case 36: return "return"
    case 48: return "tab"
    case 76: return "keypad_enter"

    case 51: return "backspace"
    case 117: return "delete_forward"
    case 71: return "clear"
    case 114: return "help"
    case 53: return "escape"

    case 123: return "arrow_left"
    case 124: return "arrow_right"
    case 125: return "arrow_down"
    case 126: return "arrow_up"
    case 115: return "home"
    case 119: return "end"
    case 116: return "page_up"
    case 121: return "page_down"

    case 18: return shift ? "exclamation_terminal" : "digit"
    case 19: return shift ? "at_symbol" : "digit"
    case 20: return shift ? "hash_symbol" : "digit"
    case 21: return shift ? "dollar_symbol" : "digit"
    case 23: return shift ? "percent_symbol" : "digit"
    case 22: return shift ? "caret_symbol" : "digit"
    case 26: return shift ? "ampersand_symbol" : "digit"
    case 28: return shift ? "asterisk_symbol" : "digit"
    case 25: return shift ? "left_paren" : "digit"
    case 29: return shift ? "right_paren" : "digit"

    case 44: return shift ? "question_terminal" : "slash"
    case 47: return shift ? "angle_right" : "period_terminal"
    case 43: return shift ? "angle_left" : "comma"
    case 41: return shift ? "colon" : "semicolon"
    case 39: return shift ? "double_quote" : "single_quote"
    case 24: return shift ? "plus" : "equals"
    case 27: return shift ? "underscore" : "minus"
    case 30: return shift ? "right_brace" : "right_bracket"
    case 33: return shift ? "left_brace" : "left_bracket"
    case 42: return shift ? "pipe" : "backslash"
    case 50: return shift ? "tilde" : "backtick"
    case 65: return "keypad_decimal"
    case 67: return "keypad_multiply"
    case 69: return "keypad_plus"
    case 75: return "keypad_divide"
    case 78: return "keypad_minus"
    case 81: return "keypad_equals"
    case 82, 83, 84, 85, 86, 87, 88, 89, 91, 92: return "keypad_digit"

    case 54, 55: return "command"
    case 56, 60: return "shift"
    case 58, 61: return "option"
    case 59, 62: return "control"
    case 57: return "caps_lock"
    case 63: return "fn"

    default:
        let category = keyCategory(for: keyCode, flags: flags)
        switch category {
        case .letter: return "letter"
        case .number: return "digit"
        case .symbol: return "symbol"
        case .whitespace: return "whitespace"
        case .editing: return "editing"
        case .navigation: return "navigation"
        case .modifier: return "modifier"
        case .functionKey: return "function"
        case .idle: return "idle"
        case .unknown: return "unknown"
        }
    }
}

func normalizedModifiers(flags: CGEventFlags) -> [String] {
    var mods: [String] = []
    if flags.contains(.maskShift) { mods.append("shift") }
    if flags.contains(.maskControl) { mods.append("control") }
    if flags.contains(.maskAlternate) { mods.append("option") }
    if flags.contains(.maskCommand) { mods.append("command") }
    if flags.contains(.maskAlphaShift) { mods.append("caps_lock") }
    if flags.contains(.maskSecondaryFn) { mods.append("fn") }
    return mods
}
