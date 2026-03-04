# Prototypes: AI Prediction + Backspacing + Cursor Corrections

This folder is intentionally **not wired** into the current app yet.
It is a staging area for engineering to pull from.

## What is included
- `UncertaintyTypes.swift`: action/event + request/response types.
- `UncertaintyConfig.swift`: config model and JSON loader.
- `PredictionProvider.swift`: provider protocol, cloud provider, deterministic fallback.
- `FalseStartPlanner.swift`: 3-4 word false-start planning logic.
- `CursorEditPlanner.swift`: backtrack + forward correction planning.
- `UncertaintyEngine.swift`: orchestrates actions for canonical text.
- `config/default_uncertainty_config.json`: sensible defaults.
- `prompts/predictive_false_start_prompt.txt`: cloud model prompt template.

## Intended behavior
1. Build canonical text first.
2. At selected boundaries, optionally type a short AI-predicted phrase.
3. Pause, backspace that phrase, then continue typing canonical text.
4. Optionally add occasional cursor backtrack/replace edits.

## OpenAI provider
- Set `predictionProvider` to `openai` in config.
- Provide `OPENAI_API_KEY` as an environment variable (do not hardcode keys).
- Optional: `OPENAI_MODEL` override (default in config is `gpt-4.1-nano` based on latency tests).

## Guardrails
- Hard event caps per message.
- Cooldown between synthetic edits.
- Disable in protected tokens (URLs, emails, code-like, numerics).
- Time budget fallback to deterministic provider.

## Integration note
Keep existing implementation unchanged. Add a feature flag and integrate by mapping
`[TypingAction]` emitted by `UncertaintyEngine` to your keystroke emitter.
