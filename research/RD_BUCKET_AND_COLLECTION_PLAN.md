# R&D Bucket Expansion + Data Collection Plan

Date: 2026-03-02
Log basis: `HumanPaste/research/global_timing_log.ndjson` (latest snapshots and latest suite)

## What We Can Already Infer
- Stable core cadence signature:
  - `letter->letter` flight p50 is consistently ~118ms.
  - letter dwell p50 is consistently ~68-69ms.
- Boundary behavior is distinct:
  - `letter->space` faster than `space->letter` (word-end vs word-start asymmetry).
- Pause profile is stable:
  - `motor_micro` ~88-92% of transitions.
  - thinking/away pauses are sparse and separable.
- Session drift is measurable:
  - low variability across snapshots for base metrics (flight/dwell/L2L).

## What This Data Enables Right Now
- Build a first-pass user-clone timing model for plain prose.
- Condition delay sampling on context buckets (intra-word vs word-start vs word-end).
- Separate active typing windows from idle/away windows during fitting.
- Generate stable baseline presets for:
  - `flight(letter->letter)`, `flight(letter->space)`, `flight(space->letter)`, `dwell(letter)`.

## What Is Still Under-Collected
- Punctuation behavior (`.,?!:;`) is near-zero in current sessions.
- Correction loops are sparse (few backspaces/deletes).
- Navigation/edit workflows are sparse (arrow/home/end style edits).
- Number/symbol heavy transitions are sparse.
- Multi-paragraph Enter behavior is light.

## New Bucket Taxonomy (Add These)
1. Timing mode buckets:
- `sprint`: flight <= q25.
- `cruise`: q25 < flight <= q75.
- `hesitate`: q75 < flight <= q95.
- `micro_pause`: q95 < flight < idle threshold.
- `away`: flight >= idle threshold.

2. Context buckets:
- `intra_word_letter_letter`
- `word_end_transition` (`letter->space|return|tab`)
- `word_start_transition` (`space|return|tab->letter`)
- `new_line_start` (`return->letter`)
- `correction_entry` (`letter->backspace/delete`)
- `correction_exit` (`backspace/delete->letter`)
- `navigation_transition` (any transition touching navigation keys)

3. Word-position buckets:
- `pos1` (first letter in word)
- `pos2`
- `pos3`
- `pos4_plus`

4. Session-state buckets:
- `warmup` (first 10-15% active keys)
- `cruise` (middle active windows)
- `fatigue` (late windows with slowdown)
- `recovery` (post-idle re-entry windows)

5. Content-type buckets:
- `chat_prose`
- `formal_prose`
- `command_line`
- `code_like`
- `short_form` (search bars/messages)

## Collection Targets (Per User Profile)
- Letters: >= 3,000 downs
- Spaces/returns: >= 600 boundary keys
- Punctuation keys: >= 120 total with all major marks covered
- Corrections: >= 60 backspace/delete events
- Navigation/edit keys: >= 80 events
- Numbers/symbols: >= 300 events
- Sessions: >= 12 sessions over >= 3 days (to capture day-to-day drift)

## Suggested Collection Prompts
1. Punctuation-rich prompt:
- Type 8-10 paragraphs with mixed punctuation and questions.

2. Correction-heavy prompt:
- Free-write quickly for 5 minutes without stopping to self-edit naturally.

3. Edit/refactor prompt:
- Paste a paragraph, then revise it using arrow keys and deletions.

4. Number/symbol prompt:
- Type URLs, code snippets, shell commands, and lists with symbols.

5. Re-entry prompt:
- Type in 1-2 minute bursts with natural pauses between bursts.

## Practical Next Steps
1. Keep snapshot automation running for passive accumulation.
2. Add a lightweight “collection mission” runner that reminds the user which prompt type to do next.
3. Gate clone quality by readiness threshold:
- `readiness < 40`: baseline model only.
- `40-70`: context-conditioned model.
- `>70`: full bucket-conditioned model with correction and punctuation policy.
