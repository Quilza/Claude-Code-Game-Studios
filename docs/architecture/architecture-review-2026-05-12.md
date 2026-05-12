# Architecture Review Report

**Date**: 2026-05-12
**Engine**: Godot 4.6.2
**GDDs Reviewed**: 10 (configuration-loader, audio-manager, tilemap-renderer, data-bridge, room-system, agent-character-controller, ambient-animation-layer, task-completion-beat, commanders-room-hud, game-concept) + systems-index
**ADRs Reviewed**: 13 written (4 previously Accepted + 9 flipped Accepted this review + ADR-0007 NOT WRITTEN, correctly BLOCKED on Data Bridge prototype) + master `architecture.md` v1.0
**Verdict**: **PASS** (architecture-grounds only — see gate-check for production readiness blockers)
**Supersedes**: `architecture-review-2026-05-11.md` (CONCERNS — all blocking issues from that review resolved)

---

## Executive Summary

The 2026-05-11 review verdict was **CONCERNS** with 8 blocking issues:
1. All 7 ADRs Proposed → resolved (4 Accepted earlier, 9 Accepted this review)
2. Cross-doc conflict 1 (agent_id type) → resolved 2026-05-11
3. Cross-doc conflict 2 (task_completed arity) → resolved 2026-05-11
4. Cross-doc conflict 3 (agent_state_changed arity) → resolved 2026-05-11
5. Cross-doc conflict 4 (Data Bridge signal names) → resolved 2026-05-11
6. 5 HIGH-risk engine domains with no ADR → resolved this session (ADR-0004, 0011, 0012; ADR-0009 + 0013 MEDIUM also addressed)
7. TR Registry empty → populated 2026-05-11 (60 entries)
8. GDD revision flags → resolved 2026-05-11

**All blocking issues from prior review are closed.** This review verdict is **PASS** on architecture grounds.

⚠️ This verdict covers architecture only. The pre-production gate has additional non-architecture blockers (test framework scaffolding, accessibility doc, UX patterns). See `production/gate-checks/2026-05-12-pre-production.md`.

---

## Traceability Summary

| Bucket | 2026-05-11 | 2026-05-12 | Δ |
|---|---|---|---|
| Total TRs registered | 60 | 60 | — |
| ADRs Accepted | 0 | 13 | +13 |
| ADRs Proposed | 7 | 0 | -7 |
| ADRs NOT WRITTEN (blocked) | 7 | 1 | -6 |
| Requirements covered by Accepted ADRs | 0 | 56 (~93%) | +56 |
| Requirements partial / GDD-self-sufficient | ~9 | ~9 (mostly Audio Manager TRs that don't need ADR) | — |
| Requirements awaiting blocked ADR-0007 | ~6 | 4 (TR-asm-002, 004, 005, 006) | -2 |
| Requirements with zero coverage | ~25 | 0 | -25 |

### ADR Status Table (after this review)

| ADR | Title | Status (2026-05-12) |
|---|---|---|
| 0001 | Data Bridge Transport Strategy | **Accepted** |
| 0002 | Config Loading + Persistence | Accepted (2026-05-11) |
| 0003 | Autoload Scene Composition | Accepted (2026-05-11) |
| 0004 | Web Export Compatibility | **Accepted** |
| 0005 | task_completed Signal Source | **Accepted** |
| 0006 | Signal-Based Decoupling | Accepted (2026-05-11) |
| 0007 | Agent State Vocabulary | NOT WRITTEN — BLOCKED on Data Bridge prototype Qs 4-5 |
| 0008 | Mock Mode Strategy | **Accepted** |
| 0009 | AnimationPlayer Strategy | **Accepted** |
| 0010 | Tween Lifecycle Management | **Accepted** |
| 0011 | HUD Rendering Strategy | **Accepted** |
| 0012 | BitmapFont/FontFile Strategy | **Accepted** |
| 0013 | Stretch Mode + Pixel-Perfect | **Accepted** |
| 0014 | Test Framework + CI | Accepted (2026-05-11) |

**13 of 14 Accepted. 1 NOT WRITTEN (intentionally — BLOCKED on prototype).**

### Coverage by GDD

| GDD | TR Count | Coverage | Missing ADR |
|---|---|---|---|
| configuration-loader | 5 | 5 (ADR-0002, 0003, 0004) | — |
| audio-manager | 6 | 6 (ADR-0003, 0004 + GDD self-sufficient) | — |
| tilemap-renderer | 4 | 4 (ADR-0013) | — |
| data-bridge | 8 | 8 (ADR-0001, 0004, 0008) | — |
| agent-state-machine | 6 | 2 (ADR-0005) | **BLOCKED** — 4 await ADR-0007 (prototype) |
| room-system | 5 | 5 (ADR-0003 + GDD self-sufficient) | — |
| agent-character-controller | 7 | 7 (ADR-0006, 0009 + GDD) | — |
| ambient-animation-layer | 4 | 4 (ADR-0006, 0009, 0010) | — |
| task-completion-beat | 8 | 8 (ADR-0005, 0006, 0010) | — |
| commanders-room-hud | 12 | 12 (ADR-0006, 0011, 0012, 0013) | — |
| cross-cutting | 5 | 5 (ADR-0006, 0008, 0014) | — |

**56 of 60 TRs covered (93.3%). The 4 gaps are correctly held on ADR-0007 (BLOCKED on Data Bridge prototype).**

---

## Cross-ADR Conflicts (audit)

**Audit method**: cross-referenced the 5 new ADRs (0004, 0009, 0011, 0012, 0013) against each other and against the 8 previously-written ADRs for signal-name, type, contract, and ordering conflicts.

### Result: **0 NEW CONFLICTS DETECTED.**

Checks performed:
- ✅ Signal contracts: ADR-0009's ASM subscription pattern matches ADR-0006 Tier 2 `.bind(agent_id)` exactly
- ✅ Web override flow: ADR-0004's `is_mock()` override is the only post-parse mutation in ADR-0002 (sanctioned)
- ✅ Viewport contract: ADR-0011 HUD anchoring + ADR-0012 font sizing both correctly cite ADR-0013's 480×270
- ✅ Tween/AnimationPlayer boundary: ADR-0009 + ADR-0010 cross-reference each other; matrices agree
- ✅ Process modes: ADR-0011 HUD `PROCESS_MODE_ALWAYS` aligns with ADR-0010 Tween pause-behaviour for HUD
- ✅ Mouse filter pattern: ADR-0011's inverted default does not conflict with any other ADR (HUD-local)
- ✅ Constants: `CELL_SIZE=16`, `MODULE_SIZE=8` (ADR-0013) match `entities.yaml` ✅
- ✅ Web export preset settings (ADR-0004) compatible with stretch_mode settings (ADR-0013) ✅
- ✅ Engine version: all 13 ADRs stamp 4.6.2 ✅
- ✅ ADR-0009's `agent_type` field reference matches ConfigurationLoader schema addition (Option X from 2026-05-11) ✅

---

## ADR Dependency Graph (final)

```
Foundation (no deps):
  ADR-0003 Autoload Scene Composition          [Accepted 2026-05-11]
  ADR-0014 Test Framework + CI                 [Accepted 2026-05-11]

Layer 1 (deps on Foundation):
  ADR-0002 Config Loading + Persistence        [Accepted 2026-05-11]
  ADR-0006 Signal-Based Decoupling             [Accepted 2026-05-11]
  ADR-0013 Stretch Mode + Pixel-Perfect        [Accepted 2026-05-12]

Layer 2:
  ADR-0005 task_completed Signal Source        [Accepted 2026-05-12]
  ADR-0008 Mock Mode Strategy                  [Accepted 2026-05-12]
  ADR-0004 Web Export Compatibility            [Accepted 2026-05-12]
  ADR-0010 Tween Lifecycle Management          [Accepted 2026-05-12]
  ADR-0012 BitmapFont/FontFile Strategy        [Accepted 2026-05-12]
  ADR-0011 HUD Rendering Strategy              [Accepted 2026-05-12]
  ADR-0009 AnimationPlayer Strategy            [Accepted 2026-05-12]

Layer 3:
  ADR-0001 Data Bridge Transport Strategy      [Accepted 2026-05-12]

Blocked (intentionally):
  ADR-0007 Agent State Vocabulary              — awaits Data Bridge prototype Qs 4-5
```

**Cycles**: None ✅
**Inversions**: None ✅
**Ordering note**: ADR-0001 was previously blocked on "web CORS deferred to prototype"; ADR-0004 now closes that. Dependency satisfied.

---

## Engine Compatibility Audit

| Field | Result |
|---|---|
| Engine version consistency | ✅ All 13 ADRs stamp Godot 4.6.2 |
| Deprecated API references | ✅ None found |
| Post-Cutoff APIs declared per ADR | ✅ Each new ADR enumerates them in Engine Compatibility table |

### VERIFY ledger

**Closed this review** (6 items):
- VERIFY-1 (stretch mode path) — ADR-0013
- VERIFY-2 (BitmapFont class status) — ADR-0012
- VERIFY-3 (TileMapLayer Y-sort) — ADR-0013
- VERIFY-4 (web export texture compression) — ADR-0004
- VERIFY-5 (BMFont .fnt import) — ADR-0012
- VERIFY-6 (AnimationMixer.active property) — ADR-0009

**Previously closed** (1 item):
- VERIFY-9 (Tween on freed node) — ADR-0010 (2026-05-11)

**Opened this review** (11 items — VERIFY-10 through VERIFY-20):
- VERIFY-10/11/12 (ADR-0004): JavaScriptBridge availability, `OS.has_feature("web")` reliability, AudioContext resume across browsers
- VERIFY-13/14 (ADR-0013): HiDPI Retina scaling, web canvas at non-integer browser zoom
- VERIFY-15/16 (ADR-0011): MOUSE_FILTER_IGNORE→STOP child clicks, `set_input_as_handled` Tab consumption
- VERIFY-17/18 (ADR-0012): FIXED_SIZE_SCALE_INTEGER_ONLY behaviour, Theme `default_font` propagation
- VERIFY-19/20 (ADR-0009): AnimationLibrary default-namespace assignment, `animation_finished` exactly-once for LOOP_NONE

**Still open** (2 items — Data Bridge prototype):
- VERIFY-7 (HTTPRequest signal signature)
- VERIFY-8 (HTTPRequest timeout cancellation)

**Net VERIFY change**: -6 closed, +11 opened, 2 still open. New items are concrete and bounded — each tied to a specific ADR's claims and resolvable via godot-specialist consultation + GUT smoke tests before code lands.

### Engine specialist consultation status

⚠️ **The 5 new ADRs were authored without explicit godot-specialist consultation this session.** This is the same exception flagged in the 2026-05-11 review. The 11 new VERIFY items enumerate the engine-specific claims that need empirical confirmation before code referencing them lands. Recommendation: spawn godot-specialist for a single sweep across VERIFY-10..20 once the test framework is scaffolded.

---

## Architecture Document Coverage

`docs/architecture/architecture.md` v1.0 — coverage check:

- ✅ All 10 designed MVP systems appear in System Layer Map
- ✅ Agent State Machine correctly marked BLOCKED on Data Bridge prototype
- ✅ Stale signal contracts (Conflicts 1, 3, 4 from prior review) corrected 2026-05-11
- ✅ ADR cross-references intact
- ✅ No orphaned architecture

Architecture document remains the authoritative system map.

---

## Blocking Issues (must resolve to PASS this review)

**None.** All 8 blocking issues from the 2026-05-11 review are closed.

---

## Non-Blocking Concerns (recommend address, but does not gate)

1. **godot-specialist consultation deferred** — 11 new VERIFY items need engine-empirical verification. Recommend single godot-specialist sweep before any HUD or animation implementation work.
2. **ADR-0007 BLOCKED** — correctly held on Data Bridge prototype. 4 ASM TRs await this ADR. Not a gate concern because ASM implementation is also Data-Bridge-gated.
3. **Master architecture document v1.0** — written 2026-05-11; minor sync may be needed after these 5 new ADRs (new VERIFY items, AnimationLibrary path conventions, web override flow). Recommend a `/create-architecture --update` pass post-gate.
4. **Asset procurement gates implementation** — ADR-0009 (AnimationLibrary `.tres` for `agent_default`) and ADR-0012 (TTF source `pixel_5x7.ttf`) are both blocks-on-asset. Procurement workstream should run parallel to test framework scaffolding.

---

## Quick wins applied (file edits this review)

- ADR-0001 Status: Proposed → Accepted (2026-05-12)
- ADR-0004 Status: Proposed → Accepted (2026-05-12)
- ADR-0005 Status: Proposed → Accepted (2026-05-12)
- ADR-0008 Status: Proposed → Accepted (2026-05-12)
- ADR-0009 Status: Proposed → Accepted (2026-05-12)
- ADR-0010 Status: Proposed → Accepted (2026-05-12)
- ADR-0011 Status: Proposed → Accepted (2026-05-12)
- ADR-0012 Status: Proposed → Accepted (2026-05-12)
- ADR-0013 Status: Proposed → Accepted (2026-05-12)
- `traceability-index.md` updated to reflect new coverage
- `tr-registry.yaml` status fields updated for newly-Accepted ADRs

---

## Handoff

**Immediate actions**:
1. ✅ All 9 Proposed ADRs flipped to Accepted (this review)
2. Re-run `/gate-check pre-production` — expected to FAIL on non-architecture blockers (test framework, accessibility doc, UX patterns) until scaffolding is restored
3. Spawn `godot-specialist` for VERIFY-10..20 empirical verification when feasible

**Rerun trigger**: Re-run `/architecture-review` after ADR-0007 is unblocked (i.e., after Data Bridge prototype answers Qs 4-5).

---

## Reflexion Log

`docs/consistency-failures.md` does not exist; not appended to per protocol. The 4 cross-doc conflicts from the 2026-05-11 review were all resolved in the 2026-05-11 follow-up session and have not regressed.
