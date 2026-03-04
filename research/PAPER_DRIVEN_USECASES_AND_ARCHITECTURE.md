# Paper-Driven Use Cases + Architecture Direction (2026)

Date: March 2, 2026
Owner: R&D

## 1) What research says (core facts)

1. Keystroke dynamics can identify users at scale.
- TypeNet reports strong free-text authentication performance and scalability to very large populations.
- Reference: https://arxiv.org/abs/2101.05570

2. Large benchmark evidence is now mature.
- KVC-onGoing (185K+ subjects) reports low EER values in desktop/mobile and highlights fairness variance by age/gender.
- Reference: https://arxiv.org/abs/2412.20530

3. Human typing behavior has stable high-value signals.
- CHI 2018 (136M keystrokes): average speed ~52 WPM, average keypress duration ~116ms, rollout of rollover behavior as major speed predictor, and 8 typist clusters.
- References:
  - https://userinterfaces.aalto.fi/136Mkeystrokes/
  - https://userinterfaces.aalto.fi/136Mkeystrokes/resources/chi-18-analysis.pdf

4. Error structure matters.
- CHI 2018 details substitution/omission/insertion patterns and correction behavior; fast typists make fewer errors and use higher rollover.
- Reference: https://userinterfaces.aalto.fi/136Mkeystrokes/resources/chi-18-analysis.pdf

5. Privacy/security risks are real.
- Privacy-preserving continuous-auth protocols exist because raw behavior features leak sensitive information.
- Replay/spoof attacks are documented in literature.
- References:
  - https://link.springer.com/article/10.1007/s10207-023-00721-y
  - https://arxiv.org/abs/2209.06557
  - https://journalofbigdata.springeropen.com/articles/10.1186/s40537-022-00662-8

6. Non-security use cases are credible.
- LLM-assisted text entry can materially improve communication speed for users with severe motor impairment.
- Reference: https://arxiv.org/abs/2312.01532

---

## 2) Why people would want realistic typing (real use cases)

### A) Accessibility + assistive communication
- Use realistic paced typing and predictive assists to reduce motor burden.
- Value: fewer keystrokes, lower fatigue, better communication throughput.

### B) Continuous identity assurance
- Background behavior verification during sessions (not just login-time auth).
- Value: account protection even if password/session is compromised.

### C) Writing provenance / transparency workflows
- Replay and source-aware writing process is increasingly used in education/work review flows.
- References:
  - https://www.grammarly.com/authorship
  - https://support.grammarly.com/hc/en-us/articles/29548735595405-About-Grammarly-Authorship
  - https://gptzero.me/news/announcing-gptzero-docs-the-future-of-transparent-writing/

### D) Personal productivity + training
- Typing profile feedback (error timing, pause rhythm, rollover ratio) can improve performance and reduce repetitive strain patterns.

### E) Behavioral UX personalization
- Tune autocorrect/prediction/pace to user motor style instead of one-size-fits-all settings.

---

## 3) Your product opportunity (HumanPaste)

### Positioning that is strongest in 2026
1. Realistic typing engine grounded in published typing dynamics.
2. Local-first motor profile capture (opt-in), not opaque black-box random delays.
3. Process integrity mode: action timeline + replay + user controls.

### Product modes to add
1. `Accessibility Mode`
- Prioritize lower cognitive load and motor savings.

2. `Authentic Pace Mode`
- Realistic typing rhythm with bounded corrections, preserving exact final text.

3. `Evidence Mode`
- Session replay and event summary for transparency/debug/review.

---

## 4) Backend upgrades (concrete)

1. Event schema and store
- Capture keydown/keyup, dwell, flight, backspace, cursor events, timing buckets, context tags.
- Keep raw text optional and minimized; store derived features by default.

2. Feature extraction service
- Derive:
  - dwell/flight distributions,
  - digraph timing vectors,
  - rollover ratio,
  - correction density,
  - pause hierarchy.

3. Profile service (per user + per app)
- Maintain:
  - baseline profile,
  - context profile (app/domain),
  - session drift deltas.

4. Low-latency prediction orchestration
- Async prefetch for synthetic false-start candidates.
- Hard timeout + deterministic fallback.
- Per-message latency budget enforcement.

5. Privacy controls
- Opt-in capture.
- Data minimization and retention windows.
- Separate identifiers from feature vectors.
- Add encrypted/aggregated processing path for enterprise mode.

6. Safety controls
- Protected-token detector (URLs, emails, code, numeric IDs).
- Guaranteed canonical integrity assertion in pipeline.

---

## 5) Frontend upgrades (concrete)

1. Profile calibration wizard (2-5 minutes)
- Record sample typing and show extracted metrics.

2. Live control panel
- Sliders/toggles for:
  - realism intensity,
  - correction rate,
  - cursor edit rate,
  - latency vs realism preference.

3. Session replay UI
- Timeline with typed/deleted/cursor events and pause markers.

4. Explainability cards
- "Why this behavior fired" (e.g., low confidence chunk, pause at clause boundary).

5. Trust + privacy UI
- Capture on/off indicator.
- Clear data controls and per-app exclusions.

---

## 6) How scientists identify people from typing (simple pipeline)

1. Capture
- Timestamped keydown/keyup event stream.

2. Build feature vectors
- Dwell times, flight times, n-graph timing, correction behavior, rollover, pause rhythm.

3. Normalize
- Device/session normalization, sequence-length handling.

4. Model
- Siamese/LSTM/Transformer embeddings for verification.

5. Decision
- Compare probe vs enrolled profile, threshold by risk target (EER/FMR/FNMR tradeoff).

6. Monitor drift + fairness
- Recalibrate over time and audit subgroup performance.

References:
- https://arxiv.org/abs/2101.05570
- https://arxiv.org/abs/2412.20530
- https://userinterfaces.aalto.fi/136Mkeystrokes/resources/chi-18-analysis.pdf

---

## 7) What to build next (shortlist)

1. Motor DNA profile capture + feature extractor.
2. Protected-token detector hardening.
3. Replay/evidence view in UI.
4. Per-app profile blending.
5. Fairness + drift monitoring dashboard (internal).

---

## 8) Immediate warnings for implementation

1. Do not rely on random delay only; use feature-driven behavior.
2. Do not block typing loop on network calls.
3. Do not store full plaintext by default if feature vectors are enough.
4. Do not ship without canonical integrity tests and protected-token exclusions.

