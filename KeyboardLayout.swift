import Foundation

// MARK: - Hand & Finger Enums

enum Hand { case left, right }
enum Finger: Int, Comparable {
    case pinky = 0, ring = 1, middle = 2, index = 3, thumb = 4
    static func < (lhs: Finger, rhs: Finger) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Key Info

struct KeyInfo {
    let hand: Hand
    let finger: Finger
    let row: Int  // 0=home, 1=top, 2=number, 3=bottom
}

// MARK: - QWERTY Layout Map

let keyInfoMap: [Character: KeyInfo] = [
    // Number row (row 2)
    "1": KeyInfo(hand: .left, finger: .pinky, row: 2),
    "2": KeyInfo(hand: .left, finger: .ring, row: 2),
    "3": KeyInfo(hand: .left, finger: .middle, row: 2),
    "4": KeyInfo(hand: .left, finger: .index, row: 2),
    "5": KeyInfo(hand: .left, finger: .index, row: 2),
    "6": KeyInfo(hand: .right, finger: .index, row: 2),
    "7": KeyInfo(hand: .right, finger: .index, row: 2),
    "8": KeyInfo(hand: .right, finger: .middle, row: 2),
    "9": KeyInfo(hand: .right, finger: .ring, row: 2),
    "0": KeyInfo(hand: .right, finger: .pinky, row: 2),
    // Top row (row 1)
    "q": KeyInfo(hand: .left, finger: .pinky, row: 1),
    "w": KeyInfo(hand: .left, finger: .ring, row: 1),
    "e": KeyInfo(hand: .left, finger: .middle, row: 1),
    "r": KeyInfo(hand: .left, finger: .index, row: 1),
    "t": KeyInfo(hand: .left, finger: .index, row: 1),
    "y": KeyInfo(hand: .right, finger: .index, row: 1),
    "u": KeyInfo(hand: .right, finger: .index, row: 1),
    "i": KeyInfo(hand: .right, finger: .middle, row: 1),
    "o": KeyInfo(hand: .right, finger: .ring, row: 1),
    "p": KeyInfo(hand: .right, finger: .pinky, row: 1),
    // Home row (row 0)
    "a": KeyInfo(hand: .left, finger: .pinky, row: 0),
    "s": KeyInfo(hand: .left, finger: .ring, row: 0),
    "d": KeyInfo(hand: .left, finger: .middle, row: 0),
    "f": KeyInfo(hand: .left, finger: .index, row: 0),
    "g": KeyInfo(hand: .left, finger: .index, row: 0),
    "h": KeyInfo(hand: .right, finger: .index, row: 0),
    "j": KeyInfo(hand: .right, finger: .index, row: 0),
    "k": KeyInfo(hand: .right, finger: .middle, row: 0),
    "l": KeyInfo(hand: .right, finger: .ring, row: 0),
    ";": KeyInfo(hand: .right, finger: .pinky, row: 0),
    "'": KeyInfo(hand: .right, finger: .pinky, row: 0),
    // Bottom row (row 3)
    "z": KeyInfo(hand: .left, finger: .pinky, row: 3),
    "x": KeyInfo(hand: .left, finger: .ring, row: 3),
    "c": KeyInfo(hand: .left, finger: .middle, row: 3),
    "v": KeyInfo(hand: .left, finger: .index, row: 3),
    "b": KeyInfo(hand: .left, finger: .index, row: 3),
    "n": KeyInfo(hand: .right, finger: .index, row: 3),
    "m": KeyInfo(hand: .right, finger: .index, row: 3),
    ",": KeyInfo(hand: .right, finger: .middle, row: 3),
    ".": KeyInfo(hand: .right, finger: .ring, row: 3),
    "/": KeyInfo(hand: .right, finger: .pinky, row: 3),
    // Space
    " ": KeyInfo(hand: .right, finger: .thumb, row: 0),
    // Additional punctuation (number row symbols & brackets)
    "`": KeyInfo(hand: .left, finger: .pinky, row: 2),
    "-": KeyInfo(hand: .right, finger: .pinky, row: 2),
    "=": KeyInfo(hand: .right, finger: .pinky, row: 2),
    "[": KeyInfo(hand: .right, finger: .pinky, row: 1),
    "]": KeyInfo(hand: .right, finger: .pinky, row: 1),
    "\\": KeyInfo(hand: .right, finger: .pinky, row: 1),
]

func keyInfo(for char: Character) -> KeyInfo? {
    return keyInfoMap[Character(char.lowercased())]
}

func isCrossHand(_ a: Character, _ b: Character) -> Bool {
    guard let aInfo = keyInfo(for: a), let bInfo = keyInfo(for: b) else { return false }
    return aInfo.hand != bInfo.hand
}

func isSameFinger(_ a: Character, _ b: Character) -> Bool {
    guard let aInfo = keyInfo(for: a), let bInfo = keyInfo(for: b) else { return false }
    return aInfo.hand == bInfo.hand && aInfo.finger == bInfo.finger
}

// MARK: - Adjacent Keys for Typos

let adjacentKeys: [Character: [Character]] = [
    "q": ["w", "a"],
    "w": ["q", "e", "a", "s"],
    "e": ["w", "r", "s", "d"],
    "r": ["e", "t", "d", "f"],
    "t": ["r", "y", "f", "g"],
    "y": ["t", "u", "g", "h"],
    "u": ["y", "i", "h", "j"],
    "i": ["u", "o", "j", "k"],
    "o": ["i", "p", "k", "l"],
    "p": ["o", "l"],
    "a": ["q", "w", "s", "z"],
    "s": ["a", "w", "e", "d", "z", "x"],
    "d": ["s", "e", "r", "f", "x", "c"],
    "f": ["d", "r", "t", "g", "c", "v"],
    "g": ["f", "t", "y", "h", "v", "b"],
    "h": ["g", "y", "u", "j", "b", "n"],
    "j": ["h", "u", "i", "k", "n", "m"],
    "k": ["j", "i", "o", "l", "m"],
    "l": ["k", "o", "p"],
    "z": ["a", "s", "x"],
    "x": ["z", "s", "d", "c"],
    "c": ["x", "d", "f", "v"],
    "v": ["c", "f", "g", "b"],
    "b": ["v", "g", "h", "n"],
    "n": ["b", "h", "j", "m"],
    "m": ["n", "j", "k"],
]

func nearbyWrongKey(for char: Character) -> Character? {
    let lower = Character(char.lowercased())
    guard let neighbors = adjacentKeys[lower], !neighbors.isEmpty else { return nil }
    let wrong = neighbors.randomElement()!
    return char.isUppercase ? Character(wrong.uppercased()) : wrong
}

// MARK: - Fast Digraphs (muscle memory pairs)

let fastDigraphs: Set<String> = [
    "th", "he", "in", "er", "an", "re", "on", "at", "en", "nd",
    "ti", "es", "or", "te", "of", "ed", "is", "it", "al", "ar",
    "st", "to", "nt", "ng", "se", "ha", "as", "ou", "io", "le",
    "ve", "co", "me", "de", "hi", "ri", "ro", "ic", "ne", "ea",
    "ra", "ce", "li", "ch", "ll", "be", "ma", "si", "om", "ur",
]

// MARK: - Word Frequency Tiers (speed multipliers for typing familiarity)
// Tier 1: Pure muscle memory words — typed blazing fast (0.78x flight time)
// Tier 2: Very common words — fast but not autopilot (0.88x)
// Tier 3: Common words — slight speed boost (0.96x)
// Unranked: baseline (1.0x)
// Long/rare (8+ chars, not in any tier): unfamiliar, typed slower (1.12x)

private let wordFrequencyTier1: Set<String> = [
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
    "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
    "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
    "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
    "so", "up", "out", "if", "who", "get", "go", "me", "no", "is",
    "was", "are", "been", "has", "had", "did", "its", "than", "can", "im",
    "just", "like", "how", "ok", "too", "yes", "oh", "hi", "us", "am",
]

private let wordFrequencyTier2: Set<String> = [
    "about", "which", "when", "make", "time", "him", "know", "take",
    "people", "into", "year", "your", "good", "some", "could", "them",
    "see", "other", "then", "now", "look", "only", "come", "over",
    "think", "also", "back", "after", "use", "two", "want", "way",
    "first", "new", "because", "day", "more", "write", "were", "our",
    "many", "find", "here", "thing", "give", "most", "very", "these",
    "even", "tell", "own", "well", "still", "should", "work", "call",
    "need", "much", "right", "each", "where", "does", "got", "must",
    "before", "those", "same", "any", "being", "down", "such", "life",
    "world", "long", "made", "while", "left", "keep", "help", "between",
    "never", "last", "let", "might", "through", "great", "old", "big",
    "every", "name", "always", "show", "put", "end", "why", "set",
    "try", "ask", "men", "run", "move", "live", "real", "start",
    "read", "hand", "high", "place", "feel", "part", "head", "off",
]

private let wordFrequencyTier3: Set<String> = [
    "small", "number", "turn", "large", "next", "school", "important",
    "home", "point", "play", "side", "change", "again", "close",
    "night", "open", "city", "state", "house", "against", "area",
    "water", "room", "mother", "money", "story", "young", "fact",
    "month", "lot", "create", "study", "book", "eye", "word", "though",
    "business", "issue", "group", "problem", "company", "system", "program",
    "question", "during", "country", "power", "family", "until", "social",
    "case", "both", "line", "under", "team", "often", "second", "later",
    "whether", "already", "level", "able", "human", "local", "data",
    "better", "public", "nothing", "research", "perhaps", "rather", "sure",
    "without", "across", "early", "hold", "west", "ground", "interest",
    "past", "morning", "table", "report", "care", "free", "hope",
    "face", "least", "idea", "continue", "best", "land", "form",
    "course", "service", "war", "along", "result", "another", "market",
    "provide", "support", "less", "control", "certain", "type", "build",
    "value", "process", "model", "plan", "mind", "class", "sense",
    "kind", "include", "step", "body", "field", "mean", "rate",
    "action", "force", "meet", "based", "cost", "order", "paper",
    "full", "short", "clear", "bring", "view", "common", "above",
    "game", "begin", "offer", "general", "simple", "road", "child",
    "reason", "girl", "grow", "decide", "allow", "hard", "late",
    "stand", "member", "whole", "center", "third", "space", "produce",
    "true", "student", "special", "voice", "ready", "notice", "among",
    "deep", "total", "remain", "test", "design", "poor", "within",
    "project", "final", "material", "person", "private", "major", "party",
    "food", "nature", "appear", "behind", "reach", "suggest", "event",
    "note", "wall", "health", "death", "nation", "record", "either",
    "technology", "information", "different", "government", "development",
    "education", "together", "something", "anything", "everyone", "everything",
    "computer", "practice", "actually", "remember", "consider", "position",
    "probably", "possible", "standard", "whatever", "describe", "national",
    "language", "complete", "security", "directly", "personal", "industry",
    "evidence", "argument", "response", "involved", "expected", "approach",
    "identify", "training", "physical", "decision", "thinking", "building",
    "required", "specific", "american", "activity", "property", "resource",
    "movement", "planning", "increase", "function", "strategy", "learning",
    "analysis", "discover", "recently", "official", "existing", "internet",
    "election", "customer", "overview", "although", "entirely", "painting",
    "previous", "platform", "provided", "progress", "children", "software",
    "maintain", "document", "exchange", "managing", "problems", "products",
]

/// Returns a flight-time multiplier based on how familiar/common a word is.
/// Lower = faster (muscle memory), higher = slower (unfamiliar).
func wordFamiliarityMultiplier(for word: String) -> Double {
    let lower = word.lowercased()
    if wordFrequencyTier1.contains(lower) { return 0.78 }
    if wordFrequencyTier2.contains(lower) { return 0.88 }
    if wordFrequencyTier3.contains(lower) { return 0.96 }
    // Long words not in any tier → unfamiliar, typed slower
    if lower.count >= 8 { return 1.12 }
    return 1.0
}
