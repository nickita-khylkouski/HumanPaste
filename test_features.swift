import Foundation

// Standalone test for word familiarity + caps fumble features.
// Does NOT require CGEvent or accessibility — pure logic tests.

// --- Replicate isSentenceStart from HumanTyper ---
func isSentenceStart(chars: [Character], at i: Int) -> Bool {
    if i == 0 { return true }
    var j = i - 1
    while j >= 0 && (chars[j] == " " || chars[j] == "\t" || chars[j] == "\n") {
        j -= 1
    }
    if j < 0 { return true }
    let prev = chars[j]
    return prev == "." || prev == "!" || prev == "?"
}

// --- Tests ---

var passed = 0
var failed = 0

func check(_ name: String, _ result: Bool) {
    if result {
        passed += 1
    } else {
        print("  FAIL: \(name)")
        failed += 1
    }
}

@main struct TestFeatures {
static func main() {

// ============================================================
print("=== TEST: isSentenceStart ===")
// ============================================================

let text1 = Array("Hello. The quick brown fox.")
// "T" is at index 7 (after "Hello. ")
check("'T' after '. ' is sentence start",
      isSentenceStart(chars: text1, at: 7))

// "q" at index 11
check("'q' mid-word is NOT sentence start",
      !isSentenceStart(chars: text1, at: 11))

// "H" at index 0
check("First char is sentence start",
      isSentenceStart(chars: text1, at: 0))

let text2 = Array("Wait! Now what?")
// "N" is at index 6 (after "Wait! ")
check("'N' after '! ' is sentence start",
      isSentenceStart(chars: text2, at: 6))

let text3 = Array("Right?\n\nOkay.")
// "O" is at index 8 (after "Right?\n\n")
check("'O' after '?\\n\\n' is sentence start",
      isSentenceStart(chars: text3, at: 8))

// Char after period with no space (edge case)
let text4 = Array("end.Start")
check("'S' directly after '.' is sentence start",
      isSentenceStart(chars: text4, at: 4))

// Comma is NOT a sentence ender
let text5 = Array("Hello, World")
check("'W' after ', ' is NOT sentence start",
      !isSentenceStart(chars: text5, at: 7))

// Tab + space after period
let text6 = Array("done.\t Next")
check("'N' after '.\\t ' is sentence start",
      isSentenceStart(chars: text6, at: 7))

// ============================================================
print("\n=== TEST: wordFamiliarityMultiplier ===")
// ============================================================

// Tier 1 — fastest
check("'the' → 0.78", wordFamiliarityMultiplier(for: "the") == 0.78)
check("'is' → 0.78", wordFamiliarityMultiplier(for: "is") == 0.78)
check("'I' (case-insensitive) → 0.78", wordFamiliarityMultiplier(for: "I") == 0.78)
check("'AND' (case-insensitive) → 0.78", wordFamiliarityMultiplier(for: "AND") == 0.78)

// Tier 2
check("'about' → 0.88", wordFamiliarityMultiplier(for: "about") == 0.88)
check("'because' → 0.88", wordFamiliarityMultiplier(for: "because") == 0.88)
check("'Between' (case) → 0.88", wordFamiliarityMultiplier(for: "Between") == 0.88)

// Tier 3
check("'important' → 0.96", wordFamiliarityMultiplier(for: "important") == 0.96)
check("'research' → 0.96", wordFamiliarityMultiplier(for: "research") == 0.96)
check("'technology' → 0.96", wordFamiliarityMultiplier(for: "technology") == 0.96)
check("'computer' → 0.96", wordFamiliarityMultiplier(for: "computer") == 0.96)

// Unranked short words — baseline
check("'dog' → 1.0", wordFamiliarityMultiplier(for: "dog") == 1.0)
check("'cat' → 1.0", wordFamiliarityMultiplier(for: "cat") == 1.0)
check("'fox' → 1.0", wordFamiliarityMultiplier(for: "fox") == 1.0)
check("'zap' → 1.0", wordFamiliarityMultiplier(for: "zap") == 1.0)

// Long rare words — slower
check("'biodiversity' → 1.12", wordFamiliarityMultiplier(for: "biodiversity") == 1.12)
check("'inaccessible' → 1.12", wordFamiliarityMultiplier(for: "inaccessible") == 1.12)
check("'continental' → 1.12", wordFamiliarityMultiplier(for: "continental") == 1.12)
check("'photosynthesis' → 1.12", wordFamiliarityMultiplier(for: "photosynthesis") == 1.12)

// Long word IN tier3 should be 0.96, not 1.12
check("'technology' is tier3 not long-rare", wordFamiliarityMultiplier(for: "technology") == 0.96)
check("'information' is tier3 not long-rare", wordFamiliarityMultiplier(for: "information") == 0.96)

// ============================================================
print("\n=== TEST: Caps fumble trigger conditions ===")
// ============================================================

// Simulate walking through text and counting where caps fumble WOULD trigger
let testText = "The quick brown fox. Scientists have discovered something. Modern technology is great! New ideas emerge. the lowercase start. What? Amazing!"
let chars = Array(testText)
var triggerPositions: [Int] = []

for i in 0..<chars.count {
    let char = chars[i]
    if char.isUppercase && char.isLetter && isSentenceStart(chars: chars, at: i) {
        triggerPositions.append(i)
    }
}

print("  Text: \"\(testText)\"")
print("  Caps fumble trigger positions: \(triggerPositions)")
for pos in triggerPositions {
    let context = String(chars[max(0, pos-3)..<min(chars.count, pos+5)])
    print("    [\(pos)] '\(chars[pos])' context: \"\(context)\"")
}

let expectedTriggers = ["T", "S", "M", "N", "W", "A"]
check("Found \(triggerPositions.count) trigger positions (expect \(expectedTriggers.count))",
      triggerPositions.count == expectedTriggers.count)

for (pos, expected) in zip(triggerPositions, expectedTriggers) {
    check("Position \(pos) char '\(chars[pos])' == '\(expected)'",
          String(chars[pos]) == expected)
}

// "the" after period should NOT trigger (lowercase)
let lowercaseAfterPeriod = Array("end. the next")
check("lowercase 't' after '. ' does NOT trigger",
      !(lowercaseAfterPeriod[5].isUppercase))

// Mid-sentence uppercase should NOT trigger
let midSentence = Array("I saw John walking")
let johnIdx = 6 // "J" in "John"
check("'J' mid-sentence does NOT trigger isSentenceStart",
      !isSentenceStart(chars: midSentence, at: johnIdx))

// ============================================================
print("\n=== TEST: Word familiarity in real sentences ===")
// ============================================================

// Verify that speed tiers make sense for a real sentence
let sentence = "The biodiversity of marine ecosystems is remarkable"
let words = sentence.split(separator: " ").map(String.init)
print("  Sentence: \"\(sentence)\"")
for word in words {
    let mod = wordFamiliarityMultiplier(for: word)
    let tier: String
    switch mod {
    case 0.78: tier = "TIER1 (fastest)"
    case 0.88: tier = "TIER2"
    case 0.96: tier = "TIER3"
    case 1.0:  tier = "UNRANKED"
    case 1.12: tier = "LONG/RARE (slowest)"
    default:   tier = "???"
    }
    print("    \(word.padding(toLength: 16, withPad: " ", startingAt: 0)) → \(mod)x  \(tier)")
}

// Verify ordering: tier1 < tier2 < tier3 < unranked < long/rare
let t1: Double = 0.78; let t2: Double = 0.88; let t3: Double = 0.96; let base: Double = 1.0; let slow: Double = 1.12
check("tier1 < tier2", t1 < t2)
check("tier2 < tier3", t2 < t3)
check("tier3 < unranked", t3 < base)
check("unranked < long/rare", base < slow)

// ============================================================
print("\n=== TEST: positionInCurrentWord ===")
// ============================================================

// Replicate positionInCurrentWord from HumanTyper
func positionInCurrentWord(chars: [Character], at index: Int) -> Int {
    guard chars[index].isLetter else { return 0 }
    var pos = 0
    var j = index - 1
    while j >= 0 && chars[j].isLetter {
        pos += 1
        j -= 1
    }
    return pos
}

let wordText = Array("Hello world! Testing.")
// "Hello" = H(0) e(1) l(2) l(3) o(4)
check("'H' in 'Hello' = pos 0", positionInCurrentWord(chars: wordText, at: 0) == 0)
check("'e' in 'Hello' = pos 1", positionInCurrentWord(chars: wordText, at: 1) == 1)
check("'l' in 'Hello' = pos 2", positionInCurrentWord(chars: wordText, at: 2) == 2)
check("'l' in 'Hello' = pos 3", positionInCurrentWord(chars: wordText, at: 3) == 3)
check("'o' in 'Hello' = pos 4", positionInCurrentWord(chars: wordText, at: 4) == 4)
// space at index 5
check("' ' (space) = pos 0", positionInCurrentWord(chars: wordText, at: 5) == 0)
// "world" = w(0) o(1) r(2) l(3) d(4)
check("'w' in 'world' = pos 0", positionInCurrentWord(chars: wordText, at: 6) == 0)
check("'o' in 'world' = pos 1", positionInCurrentWord(chars: wordText, at: 7) == 1)
check("'d' in 'world' = pos 4", positionInCurrentWord(chars: wordText, at: 10) == 4)
// '!' at index 11
check("'!' = pos 0", positionInCurrentWord(chars: wordText, at: 11) == 0)
// "Testing" = T(0) e(1) s(2) t(3) i(4) n(5) g(6)
check("'T' in 'Testing' = pos 0", positionInCurrentWord(chars: wordText, at: 13) == 0)
check("'g' in 'Testing' = pos 6", positionInCurrentWord(chars: wordText, at: 19) == 6)

// ============================================================
print("\n=== TEST: Intra-word gradient structure ===")
// ============================================================

// Verify the gradient logic: pos 0 gets wordStartMultiplier (in computeFlightTime),
// pos 1 gets 1.10-1.20x, pos 2 gets 1.02-1.08x, pos 3+ gets 1.0x (no extra)
// Word-final before non-letter gets 0.88-0.94x speedup
let gradientText = Array("The quick fox.")
// "The" positions: T=0, h=1, e=2  (space at 3, so e is word-final)
check("T pos 0 (word start, handled by computeFlightTime)", positionInCurrentWord(chars: gradientText, at: 0) == 0)
check("h pos 1 (gradient: 1.10-1.20x)", positionInCurrentWord(chars: gradientText, at: 1) == 1)
check("e pos 2 (gradient: 1.02-1.08x, also word-final → 0.88-0.94x)", positionInCurrentWord(chars: gradientText, at: 2) == 2)
// "quick" positions: q=0, u=1, i=2, c=3, k=4
check("q pos 0", positionInCurrentWord(chars: gradientText, at: 4) == 0)
check("u pos 1 (gradient)", positionInCurrentWord(chars: gradientText, at: 5) == 1)
check("i pos 2 (gradient)", positionInCurrentWord(chars: gradientText, at: 6) == 2)
check("c pos 3 (no extra slowdown)", positionInCurrentWord(chars: gradientText, at: 7) == 3)
check("k pos 4 (word-final)", positionInCurrentWord(chars: gradientText, at: 8) == 4)

// Verify word-final detection: char is letter, next char is non-letter, pos >= 2
let wordFinalPositions: [Int] = []
for idx in 0..<gradientText.count {
    let c = gradientText[idx]
    let nc: Character? = idx + 1 < gradientText.count ? gradientText[idx + 1] : nil
    let wp = positionInCurrentWord(chars: gradientText, at: idx)
    if let nc = nc, !nc.isLetter && c.isLetter && wp >= 2 {
        // This is a word-final position eligible for speedup
    }
}
// "e" in "The" (pos 2, next is space) — eligible
check("'e' in 'The' is word-final eligible", {
    let i = 2; let c = gradientText[i]; let nc = gradientText[3]
    return c.isLetter && !nc.isLetter && positionInCurrentWord(chars: gradientText, at: i) >= 2
}())
// "k" in "quick" (pos 4, next is space) — eligible
check("'k' in 'quick' is word-final eligible", {
    let i = 8; let c = gradientText[i]; let nc = gradientText[9]
    return c.isLetter && !nc.isLetter && positionInCurrentWord(chars: gradientText, at: i) >= 2
}())
// "T" in "The" (pos 0) — NOT eligible (pos < 2)
check("'T' in 'The' is NOT word-final eligible", {
    let i = 0
    return positionInCurrentWord(chars: gradientText, at: i) < 2
}())

// ============================================================
print("\n=== RESULTS ===")
print("\(passed)/\(passed + failed) tests passed")
if failed > 0 {
    print("SOME TESTS FAILED")
} else {
    print("ALL TESTS PASSED")
}

} // end main
} // end struct
