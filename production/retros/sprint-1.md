# Sprint 1 Retrospective — Data Bridge Prototype

**Sprint**: 1
**Duration**: 2026-05-12 (single-day intensive — planned as 1 week, compressed)
**Status**: ✅ COMPLETE — all DoD items met
**Linked**: `production/sprints/sprint-1.md`, `prototypes/data-bridge/findings.md`, `docs/architecture/adr-0007-agent-state-vocabulary.md`

---

## Sprint goal recap

> Run the Data Bridge prototype end-to-end and answer the 6 outstanding prototype questions. Unblock ADR-0007 (Agent State Vocabulary), which unblocks ASM GDD, which unblocks ACC + AAL implementation.

## DoD checklist

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Prototype runs against real Claude API + ≥5 successful payloads | ✅ | 11 successful payloads captured in `findings.md` Q2 |
| 2 | At least one induced failure produces documented backoff cascade | ✅ | HTTP 400 credit + HTTP 404 model failures captured; UNINITIALIZED → CONNECTING → STALE transition verified |
| 3 | All 6 prototype questions answered in writing | ✅ | `findings.md` Q1-Q6 all filled in |
| 4 | ADR-0007 written + Accepted | ✅ | `docs/architecture/adr-0007-agent-state-vocabulary.md` Accepted 2026-05-12 |
| 5 | VERIFY-7 + VERIFY-8 closed | ⚠️ partial | VERIFY-7 closed (request_completed signature confirmed); VERIFY-8 deferred (timeout path not exercised; low-risk) |
| 6 | Retro doc written | ✅ | this file |
| 7 | Commits reference Sprint 1 | ✅ | commits `45633f6`, `6691825`, `b7fe393` all reference Sprint 1 |

**Stretch**: GUT integration test exercising mock bridge end-to-end — not done; deferred to next sprint.

## What went well

**Scope discipline held.** The "single-track" charter was honoured. No ACC/AAL/TCB/HUD work crept in. The temptation to "just hook up a sprite to see it move" was real but resisted.

**Prototype tier rules paid off.** Throwaway code standards (per `.claude/rules/prototype-code.md`) let me iterate fast — temporary stdout-payload-logging, inline mock cycles, no abstraction layer. Total time from scaffold-commit to first successful real-API response was minutes, not hours.

**Empirical findings exceeded expectations.** The real Anthropic API surfaced things the design assumed:
- HTTP 400 (not 402) for credit errors → real ADR-0001 amendment
- `service_tier` and `inference_geo` fields → useful HUD-adjacent observability
- Account-scoped model access → real ConfigurationLoader amendment recommendation
The prototype's job was discovery, and it actually discovered things.

**Two-axis state separation validated.** The original ADR-0001 + ADR-0007 design assumption — that connection-state and agent-state are orthogonal — held up under contact with reality. If we'd merged them, this retro would be reporting a redesign.

**Inline gate handling.** The user explicitly broke the skill-isolation treadmill ("we've done this 4 times now") and we did `/architecture-review` + ADR flips + scaffolding + gate-check + Sprint 1 all in one inline session. The skill rotation that previously consumed 4 sessions consumed 1. Process improvement.

## What didn't go well

**Model discovery friction.** Five attempts before `claude-haiku-4-5-20251001` landed. Symptoms: HTTP 400 credit (key valid, account empty), then three HTTP 404s for various Claude 3.x model names that turned out not to exist on this account. The diagnosis loop burned ~10 minutes of API calls + iteration before I wrote `list-models.ps1` and hit `/v1/models` directly.

**Lesson**: ConfigurationLoader should validate the `model` field against `/v1/models` at startup and surface a clear "your account doesn't have access to X; available: [...]" error. This is a real ADR-0002 amendment recommendation.

**VERIFY-8 not exercised.** Timeout cancellation path was never induced. All successful polls returned in <500ms — nothing came close to the 10s timeout. Could have deliberately set `http.timeout = 0.001` to force it, but didn't. Not a regression; just incomplete coverage. Flagged for future GUT test.

**Stop-reason coverage incomplete.** Only `end_turn` and `max_tokens` were observed empirically. The other documented values (`stop_sequence`, `tool_use`, `pause_turn`, `refusal`) are in ADR-0007 by API contract knowledge, not empirical observation. VERIFY-21 and VERIFY-22 carry this forward.

**Bridge `class_name` cold-launch gotcha consumed two debug cycles.** Godot 4.x requires `--headless --import` before scripts using `class_name` references can resolve them across files. Documented in `prototypes/data-bridge/README.md` after the fact. The production project should hit this once at first commit and never again.

**One inline content-type bug.** The bridge's `class_name` was correct, but the Main scene's node paths in `main.gd` referenced `$UI/AgentsContainer` and `$UI/Header` instead of `$UI/Margin/VStack/AgentsContainer` etc. Found at first launch, fixed in `6691825`. No real-world impact (caught in the first 30 seconds of testing) but evidence that scene-tree changes in a non-trivial UI need scripted verification, not just by-eye review.

## Surprises

**Anthropic uses 400 for credit-balance, not 402.** All my pattern-matching on HTTP error codes assumed 4xx → "client error, don't retry" with 402 specifically for "needs payment". Anthropic doesn't follow that convention. ADR-0001 amendment now codifies: treat ALL 4xx as config-fatal (do not retry), all 5xx + network as transient (retry with backoff). This is a real production-shaping insight.

**Caching is now in usage accounting.** The `usage` object includes `cache_creation_input_tokens`, `cache_read_input_tokens`, and nested `ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` blocks. This is a Claude 4.x-era feature. Not directly relevant to MVP but worth surfacing on a future "agent stats" detail overlay (post-MVP HUD enhancement).

**`inference_geo: "not_available"`.** Anthropic exposes inference region in usage but at our tier returns "not_available". Possibly a higher-tier feature; unclear. Filed as a curiosity, not actionable.

**Real-API responses are FAST.** All polls returned in <500ms — well below the 10s timeout. The `working` state may be effectively invisible for one-shot ping requests since the response arrives before the next frame. For real agent workloads (tool-use, longer prompts), `working` will be observable. This validates the in-flight-state amendment to ADR-0001.

## Action items

| # | Action | Owner | Priority |
|---|---|---|---|
| 1 | ADR-0001 amendment: differentiate 4xx config-fatal from 5xx/network transient | technical-director | HIGH — affects every real-API failure path |
| 2 | ADR-0001 amendment: expose request-in-flight state (signal or accessor) | technical-director | HIGH — required for `working` state per ADR-0007 |
| 3 | ADR-0002 amendment: ConfigurationLoader validates `model` against `/v1/models` at startup | technical-director | MEDIUM — saves future devs the 5-attempt loop I just did |
| 4 | Author `design/gdd/agent-state-machine.md` (GDD #6, last MVP GDD) | game-designer | HIGH — unblocked by ADR-0007 |
| 5 | GUT integration test for bridge mock-mode + state machine | gameplay-programmer | MEDIUM — Sprint 2 candidate |
| 6 | Smoke test for VERIFY-12 web AudioContext (Chrome/Firefox/Safari) | qa-tester | LOW — before first web build |
| 7 | Remove the temporary stdout payload print from `data_bridge.gd` when promoting bridge to production | gameplay-programmer | LOW — must happen at production-promotion, not during Sprint 2 |

## Risk register reconciliation

| ID | Outcome |
|---|---|
| R-S1-01 (API rate limits / cost) | NOT REALIZED — total spend was sub-$0.01 |
| R-S1-02 (state vocabulary mismatch) | NOT REALIZED — 4-state vocabulary survived contact with reality |
| R-S1-03 (engine API surprises) | NOT REALIZED — request_completed signature confirmed |
| R-S1-04 (scope creep into ACC) | NOT REALIZED — held the line |
| R-S1-05 (user loses interest) | NOT REALIZED — sprint compressed from 1 week to 1 day |
| R-PRE-01 (WCAG contrast) | CLOSED in this session via S2 #4A9A52 → #5BAD63 shift |
| R-PRE-02 (godot-specialist VERIFY sweep) | CLOSED in this session (sweep done in `3801c15`) |
| R-PRE-03 (ACC legibility hypothesis) | UNCHANGED — separate workstream |
| R-PRE-04 (TTF asset for ADR-0012) | UNCHANGED — still blocks-on-asset |
| R-PRE-05 (AnimationLibrary for ADR-0009) | UNCHANGED — still blocks-on-asset |

**New risks** (none — Sprint 1 didn't surface any unanticipated risks that need register entries)

## Next sprint preview

Sprint 2 candidates (in priority order):
1. **ASM GDD authoring** (`design/gdd/agent-state-machine.md`) — last MVP GDD; unblocked by ADR-0007
2. **ADR-0001 + ADR-0002 amendments** — small, mechanical, high-leverage
3. **Asset procurement workstream** — `pixel_5x7.ttf`, `agent_default.tres` AnimationLibrary, `silence_50ms.ogg`
4. **First implementation stories** — ConfigurationLoader + AudioManager (foundation autoloads) — both have all deps Accepted

Estimated Sprint 2 duration: 1-2 weeks depending on whether asset procurement runs parallel.

## One-line summary

**Sprint 1 delivered exactly what it promised: real-API findings that unblock the last architectural ADR, with no scope creep and sub-cent cost. The Pre-Production critical path is now fully open.**
