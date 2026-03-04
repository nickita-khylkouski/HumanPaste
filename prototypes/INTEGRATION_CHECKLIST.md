# Uncertainty Prototype Integration Checklist

1. Add feature flag:
- `uncertainty_prototype_enabled` (default off)

2. Load config:
- parse `prototypes/config/default_uncertainty_config.json`

3. Choose provider:
- deterministic fallback always available
- cloud provider optional with timeout and circuit breaker

4. Generate actions:
- call `UncertaintyEngine.buildActions(for: canonicalText)`

5. Map actions to emitter:
- `.type(text)` -> existing character emitter
- `.pause(ms)` -> delay
- `.backspace(n)` -> repeat backspace
- `.deleteForward(n)` -> repeat forward-delete
- `.moveCursorLeft(n)` / `.moveCursorRight(n)` -> arrow key events

6. Enforce guards:
- disable synthetic edits for protected tokens (URL/email/code-like)
- cap false-starts + cursor edits per message
- apply cooldown between synthetic events

7. Telemetry:
- false-start count
- cursor-edit count
- added latency ms
- fallback count

8. Rollout:
- dogfood only first
- then 10% flag rollout
