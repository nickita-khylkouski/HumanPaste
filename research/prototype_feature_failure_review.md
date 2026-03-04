# Prototype Feature Failure Review

Date: March 2, 2026
Scope: `HumanPaste/prototypes/*`

## Count
- Prototype files created: 11

## Initial failures found
1. Cursor correction corrupted final text (`mismatch=100/100` in cursor-only mode).
2. Formatting not preserved (newlines/double spaces collapsed).
3. Combined mode failed canonical integrity (`mismatch=200/200`).

## Fixes applied
1. Added `deleteForward(count)` action and switched cursor correction to forward-delete workflow.
2. Reworked engine to tokenize and emit canonical text exactly (`BoundaryTokenizer`) instead of split/join by whitespace.
3. Added provider factory and OpenAI provider scaffold with env-based key loading only.

## Re-test results after fix
1. Combined mode integrity (200 runs): `mismatch=0`.
2. Formatting preservation: `true` for newline/tab/double-space sample.
3. False-start cap respected in stress run (`maxFalseStartsSeen=2`).

## Remaining risks
1. OpenAI provider not live-tested in repo (no key used during tests).
2. Cursor edit realism quality needs tuning even though integrity now passes.
3. Protected-token detection is heuristic and should be expanded.

## Recommendation
- Keep this as prototype for engineering review.
- Integrate behind feature flag and run dogfood telemetry before rollout.
