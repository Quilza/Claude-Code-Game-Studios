# Sprint 1 Charter — The Situation Room

**Sprint #**: 1
**Created**: 2026-05-12
**Status**: PLANNED (not yet started)
**Duration**: 1 week (target — adjust on retro)
**Pre-Production phase**: Yes (first Pre-Production sprint after the 2026-05-12 gate PASS)

---

## Sprint goal

> **Run the Data Bridge prototype end-to-end and answer the 6 outstanding prototype questions. Unblock ADR-0007 (Agent State Vocabulary), which unblocks ASM GDD, which unblocks ACC + AAL implementation.**

This sprint is **single-track, high-risk, high-leverage**. The Data Bridge prototype is the project's #1 risk per HOME.md and the 2026-05-11 gate-check. Until it runs, ~60% of the MVP scope is blocked behind it.

---

## Why this is Sprint 1 (not something else)

| Candidate | Why deferred to a later sprint |
|---|---|
| ACC implementation | Blocked on ASM GDD → blocked on ADR-0007 → blocked on this prototype |
| AAL implementation | Same chain |
| HUD implementation | Blocked on TTF asset (ADR-0012) — asset procurement workstream runs parallel |
| TCB implementation | Blocked on ASM emitter availability |
| Asset procurement | Parallel workstream; not blocking |
| godot-specialist VERIFY sweep | Can run before/during/after; not gating |

The Data Bridge is upstream of every meaningful gameplay system. Investing one sprint to de-risk it pays for itself many times over.

---

## In scope (this sprint)

### S1.1 — Prototype Godot project
- Standalone scene under `prototypes/data-bridge/`
- One ConfigurationLoader instance (per ADR-0002 — uses test-mode fallback)
- One Data Bridge instance with 1–2 HTTPRequest nodes
- One bare-minimum visual indicator (text label showing "CONNECTED / STALE / DISCONNECTED" per agent)
- Reuses ADR-0001's specified transport pattern verbatim

### S1.2 — Real provider hookup
- Target provider: **Claude API** (first; the user's own dogfood)
- Bearer token via env var or local config file (NOT committed)
- Endpoint: TBD (use a low-cost completion endpoint to limit token spend)
- Document the exact request shape used so it's reproducible

### S1.3 — Answer the 6 prototype questions
The data-bridge GDD Section C lists 6 questions. Capture answers in writing.
1. What is the realistic poll cadence? (1s? 5s? 30s?)
2. What does a typical real-API payload look like?
3. How frequent are transient failures?
4. **What canonical agent states does the real-API stream resolve to?** (BLOCKS ADR-0007)
5. **What is the connection-quality reporting mechanism?** (BLOCKS ADR-0007)
6. Web export CORS — already answered by ADR-0004 (mock-forced); verify the override fires.

### S1.4 — VERIFY-7 + VERIFY-8 closure
- VERIFY-7: confirm `HTTPRequest.request_completed` signal signature in 4.6.2 — run a one-line assertion test
- VERIFY-8: confirm `HTTPRequest.timeout` cleanly cancels (no leaked listeners) — instrument the prototype

### S1.5 — Author ADR-0007 from prototype findings
Once Q4 + Q5 are answered, draft ADR-0007 (Agent State Vocabulary):
- Canonical state list
- State transition rules
- Connection-quality state name (separate from agent state? part of it?)
- Map to ASM's emitted `agent_state_changed(agent_id, new_state, previous_state)` signature

### S1.6 — Sprint retro + control manifest version bump
- Retro doc: `production/retros/sprint-1.md`
- If ADR-0007 lands: bump `docs/architecture/control-manifest.md` to a new version and reconcile.

---

## Out of scope (Sprint 1)

- ACC, AAL, TCB, HUD implementation — all downstream of this sprint
- Real-API hookup to providers beyond Claude API — Sprint 2+
- Mock data cycle authoring — already covered by ADR-0008; will get test fixtures in Sprint 2
- Asset procurement — parallel workstream, owned by art-director
- godot-specialist VERIFY-10..20 sweep — parallel; can happen anytime
- Web export validation — ADR-0004's override stops real-API on web; verify in Sprint 2 when there's a HUD to demo

---

## Definition of Done (DoD)

Sprint 1 is **done** when all of these are true:

1. ✅ Prototype runs against a real Claude API endpoint and emits at least 5 successful payload-received events
2. ✅ At least one induced failure (network off, bad token, malformed payload) produces the documented STALE → DISCONNECTED → auto-heal cycle from ADR-0001
3. ✅ All 6 prototype questions have answers committed to a written doc (recommend: `prototypes/data-bridge/findings.md`)
4. ✅ ADR-0007 written and Status: Accepted (no longer NOT WRITTEN)
5. ✅ VERIFY-7 and VERIFY-8 marked CLOSED in active.md / control manifest
6. ✅ Sprint retro doc written
7. ✅ All code commits reference Sprint 1 in the message

**Stretch**: a smoke test in `tests/integration/` exercises Data Bridge with mock mode end-to-end.

---

## Risks (linked to `production/risk-register/`)

| ID | Risk | Severity | Mitigation |
|---|---|---|---|
| R-S1-01 | Claude API rate limits or token cost during prototype iteration | MEDIUM | Use cheapest endpoint; budget $20; switch to mock if burning |
| R-S1-02 | Real-API payloads don't fit cleanly into 4-state vocabulary | HIGH | This is the *point* of the prototype — discovery is the deliverable, not a failure |
| R-S1-03 | VERIFY-7 / VERIFY-8 surface engine-API differences from documented behaviour | MEDIUM | Document; if blocking, escalate to godot-specialist |
| R-S1-04 | Sprint scope creeps into ACC implementation | MEDIUM | Sprint goal is single-track; resist. Out-of-scope list is explicit. |
| R-S1-05 | User loses interest mid-prototype (research-feeling work) | LOW | Day-3 checkpoint: even partial findings unblock ADR-0007 partially. |

---

## Daily-ish checkpoints (recommended cadence)

- **Day 1**: prototype scaffold + ConfigLoader + first HTTPRequest hookup; first successful HTTP round-trip
- **Day 2**: 5+ successful payloads; failure injection (network off, bad token); document what STALE/DISCONNECTED look like in practice
- **Day 3**: ⚠️ checkpoint on Q4 + Q5 (state vocabulary) — if not answerable yet, identify why and adjust prototype shape
- **Day 4**: draft ADR-0007 in parallel with last prototype iteration
- **Day 5**: ADR-0007 Accepted; retro; manifest bump

If Day 3 checkpoint slips: **do not extend Sprint 1 silently**. Either de-scope (skip stretch items, accept partial Q answers) or formally extend to Sprint 1.5.

---

## What unblocks downstream after Sprint 1

| Unblocked | By |
|---|---|
| ADR-0007 Agent State Vocabulary | Sprint 1 outcome |
| `design/gdd/agent-state-machine.md` (GDD #6) | Once ADR-0007 Accepted |
| ACC Implementation stories | Once ADR-0007 + ASM GDD |
| AAL Implementation stories | Once ADR-0007 + ASM GDD |
| TCB Implementation stories | Once ASM emits real `task_completed` |
| HUD slot subscription stories | Once ASM emits real signals |

The downstream unblock cascade is the reason this is worth a whole sprint.

---

## Tracking

- Sprint plan lives here (this file)
- Daily progress logged in `production/session-state/active.md` STATUS block (set when status line block is enabled in Production phase)
- Findings written to `prototypes/data-bridge/findings.md`
- Retro at the end → `production/retros/sprint-1.md`

---

## References

- `design/gdd/data-bridge.md` Section C — the 6 prototype questions
- `docs/architecture/adr-0001-data-bridge-transport.md` — transport contract
- `docs/architecture/adr-0008-mock-mode-strategy.md` — fallback when prototype isn't reachable
- `docs/architecture/control-manifest.md` Manifest Version 2026-05-12 — Data Bridge layer rules
- `production/gate-checks/2026-05-12-pre-production.md` — gate that opened this sprint
- HOME.md — current phase + risk roster
