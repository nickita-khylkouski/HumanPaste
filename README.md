# HumanPaste

A macOS menu bar app that types clipboard text with realistic human-like keystroke dynamics. Instead of instant paste, HumanPaste simulates natural typing — complete with variable speeds, typos that get corrected, thinking pauses, and cognitive uncertainty behaviors like false starts and forgotten words.

## Why

Pasting text is instant and obvious. HumanPaste makes it look like you're actually typing — useful for live demos, screen recordings, or anywhere you need text to appear naturally.

## Features

### Keystroke Engine
- **Log-logistic timing model** — inter-key intervals follow distributions fitted to real human typing data (CMU dataset)
- **Digraph-aware flight times** — timing varies based on finger distance, hand alternation, same-finger penalties, row changes
- **Key rollover simulation** — overlapping key press/release for fast cross-hand sequences
- **Burst/slow phase cycling** — alternates between fast bursts and slower deliberate phases
- **Fatigue modeling** — gradual slowdown over long texts with periodic "second wind" recovery
- **Intra-word speed gradient** — word-initial chars are slower (motor planning), mid-word accelerates, word-final fastest

### Error Model
- **Substitution** — hits a nearby wrong key, notices, backspaces, retypes
- **Omission** — skips a character, types ahead 1-3 chars before noticing, backspaces to fix
- **Insertion** — accidentally hits an extra key before the correct one
- **Transposition** — swaps two adjacent characters
- **Caps fumble** — types lowercase at sentence start, quickly corrects
- **Post-error slowing** — IKI doubles after a correction, decays over 2-4 chars (matches research data)

### Cognitive Pauses
- **Thinking pauses** — at sentence/clause boundaries, log-logistic distributed
- **Lost thought pauses** — rare ultra-long pauses (~2% chance per 300 chars)
- **Cognitive scaling** — pause frequency/duration adjustable independently from speed

### Uncertainty Engine
When enabled, injects realistic editing behaviors that make typing look like composing rather than copying:

- **False starts** — types a wrong continuation (AI-generated or deterministic), pauses, deletes it, continues with correct text
- **Forgotten words** — skips a word while typing, continues for 2-4 words, then arrow-keys back to insert the missing word
- **Forgotten clauses** — same as above but for entire clauses between punctuation
- **Mid-word restarts** — starts typing a long word, hesitates partway through, backspaces, starts over
- **Rephrase backtracks** — types an alternative phrasing, pauses, deletes it, lets the original continue

All uncertainty events preserve the final canonical text — the output always matches the clipboard content exactly.

### Prediction Providers
- **Deterministic** — generates false-start phrases by shuffling and recombining upcoming words (no API needed)
- **OpenAI** — uses GPT-4.1-nano for contextually plausible false-start phrases (optional, needs API key)

## Building

Requires macOS 14+ and Xcode command line tools.

```bash
# Build and launch
./build.sh

# Run visual test suite (no GUI, tests uncertainty engine integrity)
./HumanPaste.app/Contents/MacOS/HumanPaste --test

# Run headless typing simulation (outputs timing log, no CGEvents)
./HumanPaste.app/Contents/MacOS/HumanPaste --headless --wpm 80 --text "your text here"
```

The build script compiles all Swift files, code-signs the binary (ad-hoc or with a dev certificate if available), and launches the app.

## Usage

1. Launch the app — it appears as a keyboard icon in the menu bar showing `HP 80+`
2. Copy text to clipboard normally (Cmd+C)
3. Press **Ctrl+Shift+V** to start typing at the cursor position
4. Press **Esc** to stop mid-typing

### Hotkeys

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+V` | Paste with human typing |
| `Ctrl+Shift+]` | Increase WPM by 10 |
| `Ctrl+Shift+[` | Decrease WPM by 10 |
| `Ctrl+Shift+P` | Cycle pause percentage |
| `Ctrl+Shift+T` | Cycle typo percentage |
| `Ctrl+Shift+U` | Toggle uncertainty engine |
| `Esc` | Stop typing |

### Presets

| Preset | WPM | Pauses | Typos | Uncertainty | Use Case |
|--------|-----|--------|-------|-------------|----------|
| Natural | 75 | 20% | 45% | On | Balanced, realistic |
| Fast | 160 | 5% | 15% | Off | Speed typist |
| AI Paste | 90 | 12% | 35% | On | Long start delay, looks like composing |
| Careful | 50 | 35% | 60% | On | Slow, deliberate, many corrections |
| Test | 60 | 30% | 70% | On (max) | Everything cranked up for dev testing |

### Settings

Click the menu bar icon to open the settings window. All parameters update in real-time.

**Speed & Errors** — WPM, pause frequency, typo rate, correction speed, burst length

**Timing** — flight time cap, thinking pause cap, initial start delay

**Uncertainty Engine** — toggle on/off, false start count, cursor edit count, optional OpenAI API key

**Log Panel** — real-time event log with compact/verbose toggle

### API Key (Optional)

For AI-generated false-start phrases, set your OpenAI API key either:
- In the settings UI (api key field)
- In a `.env` file next to the app: `OPENAI_API_KEY=sk-...`
- As an environment variable

Without an API key, the engine falls back to deterministic phrase generation which works fine.

## Architecture

```
main.swift              — AppDelegate, menu bar, hotkeys, visual test harness
SettingsView.swift       — SwiftUI settings panel
HumanTyper.swift         — Core typing loop, error execution, timing, uncertainty integration
TimingModel.swift        — Speed profiles, pause configs, log-logistic distribution
ErrorModel.swift         — Typo types, error rolling, nearby-key maps
KeyboardLayout.swift     — Physical keyboard geometry, finger assignments, hand mapping
KeystrokeEmitter.swift   — CGEvent keystroke emission, key codes, modifiers
prototypes/
  UncertaintyEngine.swift   — Builds action sequences (type, pause, backspace, cursor move)
  UncertaintyConfig.swift   — Configuration struct with all tunable parameters
  UncertaintyTypes.swift    — TypingAction enum, PlannerState
  FalseStartPlanner.swift   — False start decision logic and action building
  CursorEditPlanner.swift   — Cognitive events: mid-word restart, rephrase, forgotten word/clause
  BoundaryTokenizer.swift   — Splits text into word/whitespace/punctuation tokens
  PredictionProvider.swift  — OpenAI and deterministic false-start phrase generation
```

## Calibration Data

The `data/calibration.json` file contains timing parameters fitted to the CMU typing dataset:
- Flight time: alpha=191ms, beta=2.64 (log-logistic)
- Dwell time: alpha=86ms, beta=5.09
- Cross-hand speedup: 0.78x, same-finger penalty: 1.38x
- Word-start slowdown: 1.55x, common-word speedup: 0.88x

## Permissions

HumanPaste requires **Accessibility** permission to emit keystrokes (CGEvent). On first launch, it will prompt you to grant access in System Settings > Privacy & Security > Accessibility.

## License

MIT
