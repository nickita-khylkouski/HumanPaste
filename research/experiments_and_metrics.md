# R&D Track 5: Experimentation Roadmap and KPI Framework

## Scope and Objective
Track 5 defines a repeatable experimentation system for HumanPaste v3 so timing-model changes are accepted only when they improve human-likeness, reduce detector confidence, and preserve runtime performance.

Decision principle: no model change ships without passing both quality KPIs and safety guardrails.

## Experiment Matrix

| ID | Experiment | Hypothesis | Variants | Primary KPIs | Guardrails | Ship Decision |
|---|---|---|---|---|---|---|
| E1 | IKI distribution family | Log-logistic IKI produces lower distribution drift vs Gaussian/uniform baselines. | Control: Gaussian. V1: Log-logistic (alpha=160, beta=4.5). V2: 3-parameter log-logistic with tail clamp. | KS distance (IKI CDF), Wasserstein distance, p95 IKI realism band hit rate. | Mean WPM within target +/- 10%; no >5% increase in timeout/failure runs. | Ship best variant if KS and Wasserstein each improve >=15% vs control. |
| E2 | Dwell-time realism | Non-zero dwell modeled by finger class improves detector resistance and feature realism. | Control: 0ms dwell. V1: single dwell distribution. V2: per-finger dwell priors. | Dwell mean error, dwell SD error, detector confidence delta. | End-to-end throughput degradation <8%. | Ship if detector confidence drops >=10% and dwell errors each improve >=20%. |
| E3 | Digraph timing model | Digraph-aware flight timing lowers n-graph anomaly score. | Control: global flight delay. V1: cross/same-hand classes. V2: full digraph lookup + class fallback. | Digraph RMSE vs reference corpus, n-graph likelihood score. | Memory overhead <50 MB; no crash regressions. | Ship if RMSE improves >=15% with stable memory. |
| E4 | Cognitive pause hierarchy | Structured boundary pauses improve long-form authenticity. | Control: flat random pauses. V1: punctuation hierarchy. V2: punctuation + burst/planning pauses. | Pause-by-boundary MAE, burst-length distribution fit, detector confidence delta on essays. | Total session duration inflation <20%. | Ship if boundary MAE improves >=20% and essay detector confidence drops >=8%. |
| E5 | Error model realism | Multi-type typo model yields human-like correction traces. | Control: substitution-only. V1: sub+ins+omit. V2: adds transposition + delayed correction. | Error-type KL divergence, KSPC gap, backspace pattern similarity. | Character accuracy floor >=97%; no infinite correction loops. | Ship if KL improves >=25% and KSPC within +/- 2pp of target corpus. |
| E6 | Key rollover overlap | Controlled overlap on cross-hand pairs improves advanced biometric realism. | Control: no overlap. V1: fixed 25% overlap. V2: context-dependent overlap (skill-speed conditioned). | Overlap rate error, press-release overlap duration error, detector confidence delta. | Stuck-key and ordering error rate == 0 in harness replay. | Ship if overlap metrics improve >=20% and event ordering stays clean. |
| E7 | Composite model bake-off | Combined best-of components outperform any single-component variant. | Control: current stable. V1: best from E1-E6. V2: tuned composite after first bake-off. | Human-likeness composite score, detector pass rate, latency overhead. | CPU <15% on reference machine; memory <200 MB. | Promote winner to candidate branch if composite improves >=12% and all guardrails pass. |

## Benchmark Harness Design

## 1) Architecture
- `Scenario Generator`: creates deterministic typing sessions from text corpora with fixed seeds and scenario tags (`short_chat`, `essay`, `code_block`, `form_fill`).
- `Runner`: executes each model variant over identical scenarios, captures full key event stream (`keyDown`, `keyUp`, timestamps, correction metadata).
- `Feature Extractor`: computes IKI, dwell, digraph timing, pause hierarchy, error patterns, overlap features.
- `Comparator`: scores variant outputs against a fixed human reference corpus and baseline control.
- `Report Builder`: writes markdown + JSON summaries per run and appends weekly trend snapshots.

## 2) Reproducibility Contract
- Fixed random seeds per scenario batch.
- Same corpus slice for all variants in a run.
- Versioned config file for parameters and thresholds.
- Each run stamped with git SHA, config checksum, and timestamp.

## 3) Data Inputs
- `Reference corpus`: human timing benchmark corpus (frozen snapshot for quarter).
- `Test prompts`: balanced by length/domain, including punctuation-heavy and correction-prone texts.
- `Synthetic stress set`: pathological sequences (`llll`, alternating hands, heavy punctuation) for edge behavior.

## 4) Outputs
- `run_summary.json`: per-variant metric values, deltas, CI bounds, pass/fail flags.
- `detector_eval.json`: detector confidence and pass rates per scenario class.
- `weekly_track5_report.md`: human-readable experiment conclusions and ship/no-ship decisions.

## 5) Statistical Policy
- Minimum 30 scenario replications per variant before decisioning.
- Bootstrap 95% confidence intervals for primary KPI deltas.
- Treat results as inconclusive when CI crosses zero or guardrail breaches occur.
- Use one control per run; avoid control drift by pinning baseline version for the week.

## Success Metrics (KPI Framework)

## North-Star KPI
`Human-Likeness Index (HLI)` (0-100), weighted composite:
- 30% timing distribution fit (IKI + dwell)
- 20% digraph/rollover realism
- 20% pause-structure realism
- 20% error/correction realism
- 10% detector confidence inversion (lower detector confidence => higher score)

Quarter target: increase HLI by >=15 points from Track 5 kickoff baseline.

## Primary KPIs
- `Distribution Fit`: KS + Wasserstein distances vs reference corpus.
- `Behavioral Realism`: digraph RMSE, pause MAE, error-type KL divergence.
- `Detector Resistance`: mean detector confidence and scenario-level pass rate.
- `Throughput`: achieved WPM vs configured WPM.
- `Stability`: harness failure rate, ordering violations, stuck-key incidents.

## Guardrail KPIs
- `Perf`: CPU and memory ceilings.
- `Reliability`: zero critical event-ordering bugs.
- `Usability`: session duration inflation cap and accuracy floor.
- `Operational`: benchmark completion time under agreed CI budget.

## Exit Criteria for Track 5
- Two consecutive weekly runs with:
  - HLI improvement >=12% vs frozen baseline.
  - Detector pass rate improvement >=10% relative.
  - No guardrail violations.

## Weekly Execution Cadence

## Monday: Plan and Freeze
- Freeze baseline SHA and experiment configs.
- Select 1 to 2 experiments from the matrix for active testing.
- Confirm KPI thresholds and guardrails for the week.

## Tuesday: Implement and Instrument
- Land parameter/model changes on experiment branches.
- Verify harness instrumentation coverage for new features.
- Run smoke benchmarks to validate data integrity.

## Wednesday: Full Benchmark Runs
- Execute full seeded batch for control + variants.
- Publish raw outputs and preliminary KPI dashboard.
- Flag anomalies early (missing events, unstable variance, perf spikes).

## Thursday: Analysis and Decision Review
- Compute effect sizes and confidence intervals.
- Conduct go/no-go review using matrix decision rules.
- Choose one winner, one hold, and one drop (if applicable).

## Friday: Integrate and Report
- Promote passing variant(s) to candidate branch.
- Publish `weekly_track5_report.md` with KPI deltas, decisions, and risks.
- Update next-week queue with prioritized experiments and dependencies.

## Weekly Artifacts Checklist
- Experiment plan with IDs and hypotheses.
- Reproducible benchmark config (seeds, corpus version, SHA).
- KPI results table with CI and guardrail status.
- Decision log (`ship`, `hold`, `drop`) with rationale.
- Updated backlog for next weekly cycle.
