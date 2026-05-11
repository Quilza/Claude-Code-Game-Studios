# Architecture Review Report

**Date**: 2026-05-11
**Engine**: Godot 4.6.2
**GDDs Reviewed**: 10 (configuration-loader, audio-manager, tilemap-renderer, data-bridge, room-system, agent-character-controller, ambient-animation-layer, task-completion-beat, commanders-room-hud, game-concept) + systems-index
**ADRs Reviewed**: 7 Proposed (0001, 0002, 0003, 0005, 0006, 0008, 0014) + master `architecture.md` v1.0
**Verdict**: **CONCERNS** — pre-production gate cannot pass without resolving blocking items

---

## Traceability Summary

| Bucket | Count |
|---|---|
| TR baseline (per architecture.md) | ~70 |
| ADRs Accepted | 0 |
| ADRs Proposed | 7 |
| ADRs planned but missing | 7 (0004, 0007 [blocked], 0009, 0010, 0011, 0012, 0013) |
| Requirements covered by Proposed ADRs | ~30 / ~70 (~43%) |
| Requirements with zero ADR coverage | ~25 / ~70 (~36%) |
| Requirements awaiting blocked ADR-0007 | ~6 (ASM-related) |
| TR-registry entries | **0** (registry file exists but empty) |

### Coverage by GDD

| GDD | TR Count | Covered (Proposed) | Missing ADR |
|---|---|---|---|
| configuration-loader | 5 | 5 (ADR-0002, 0003) | — |
| audio-manager | 6 | 4 (ADR-0003 + GDD self-sufficient) | partial — GDD covers most |
| tilemap-renderer | 4 | 0 | ADR-0013 (stretch mode, Y-sort) |
| data-bridge | 8 | 7 (ADR-0001, 0008) | ADR-0004 (web export CORS) |
| agent-state-machine | 6 | 0 | **BLOCKED** (ADR-0007 awaits prototype) |
| room-system | 5 | 1 (ADR-0003 partial) | none planned |
| agent-character-controller | 7 | 0 | ADR-0009 (AnimationPlayer) |
| ambient-animation-layer | 4 | 0 | ADR-0009, ADR-0010 (Tween) |
| task-completion-beat | 8 | 1 (ADR-0005 source) | ADR-0010 (Tween) |
| commanders-room-hud | 12 | 0 | ADR-0011 (render), ADR-0012 (font) |
| cross-cutting | 5 | 4 (ADR-0006, 0008, 0014) | — |

### Coverage Gaps — Suggested ADRs (ordered by impact)

| Suggested ADR | Domain | Engine Risk | Blocks |
|---|---|---|---|
| ADR-0004 Web Export Compatibility | CORS + HTML5 export + stretch | HIGH | Data Bridge prototype Q6; ADR-0001 finalisation |
| ADR-0010 Tween Lifecycle Management | Tween cleanup on freed Node2D (VERIFY-9) | HIGH | TCB, AAL, HUD impl |
| ADR-0011 HUD Rendering Strategy | CanvasLayer vs in-world; web responsiveness | HIGH | HUD impl |
| ADR-0012 BitmapFont/FontFile Strategy | VERIFY-2, VERIFY-5 | HIGH | HUD impl |
| ADR-0013 Stretch Mode + Pixel-Perfect | keep_integer (VERIFY-1) | MEDIUM | Bootstrap setup |
| ADR-0009 AnimationPlayer Strategy | VERIFY-6 | MEDIUM | ACC, AAL impl |
| ADR-0007 Agent State Vocabulary | ASM states | LOW | **Blocked on Data Bridge prototype Qs 4-5** |

---

## Cross-ADR Conflicts (🔴 must resolve)

### 🔴 Conflict 1 — `agent_id` parameter type inconsistency

| Document | Type used |
|---|---|
| ADR-0001, ADR-0005, ADR-0006, ADR-0008 (all code) | `agent_id: String` |
| `architecture.md` § API Boundaries (Data Bridge, ASM, Room System, ACC, TCB) | `agent_id: StringName` |
| `task-completion-beat.md` GDD (`beat_fired`, Rules 2.4, 9) | `agent_id: StringName` |
| `data-bridge.md` GDD (after ADR-0001 sync) | `agent_id: String` ✅ |

**Impact**: When TCB (StringName per GDD) connects to ASM's `task_completed(agent_id: String)` (per ADR-0005), Godot's typed signal connection will fail at parse time or implicit-convert on every emission. HUD subscribes to both signals and would see mismatched types.

**Resolution (user-decided 2026-05-11)**: **Adopt `String` everywhere** — ADRs win. The value originates from JSON parsing as String; converting to StringName at every emission is pure overhead.

**Required edits**:
- `docs/architecture/architecture.md` § API Boundaries — change all `agent_id: StringName` to `agent_id: String` (Data Bridge, ASM, Room System, ACC, TCB sections, ~12 lines)
- `design/gdd/task-completion-beat.md` Rules 2.4 + 9 — change `beat_fired(agent_id: StringName, ...)` to `agent_id: String`
- `design/gdd/commanders-room-hud.md` — verify and align (not re-read in this review)

### 🔴 Conflict 2 — `task_completed` signal arity (ADR-0005 vs ADR-0006)

| Document | Declaration |
|---|---|
| ADR-0005 (binding) | `signal task_completed(agent_id: String)` — 1 param |
| ADR-0006 example (lines 76, 218) | `signal task_completed(agent_id: String, task_name: String)` — 2 params |

**Impact**: ADR-0006 is the signal-pattern governance doc; its example contradicts ADR-0005. A developer cargo-culting from ADR-0006 would emit a 2-param signal no subscriber expects.

**Resolution**: Edit ADR-0006 example code to drop `task_name: String`. ADR-0005 is the binding contract.

### 🔴 Conflict 3 — `agent_state_changed` arity (ADRs vs architecture.md)

| Document | Declaration |
|---|---|
| ADR-0005 + ADR-0006 (binding) | `agent_state_changed(agent_id: String, new_state: String, previous_state: String)` — 3 params |
| `architecture.md` § ASM API | `agent_state_changed(agent_id: StringName, new_state: StringName)` — 2 params |

**Resolution**: Update `architecture.md` to 3-param declaration with `String`. Same edit pass as Conflict 1.

### 🔴 Conflict 4 — Data Bridge connection/payload signal names

| Document | Signal names |
|---|---|
| `architecture.md` § Data Bridge API | `payload_received`, `connection_state_changed` |
| ADR-0001 (binding) + data-bridge.md GDD | `agent_response_received`, `agent_connection_changed` |

**Resolution**: Update `architecture.md` § API Boundaries → Data Bridge to use binding names. Bundle with Conflicts 1+3 edits.

---

## ADR Dependency Order

Dependency graph (all currently `Proposed`):

```
Foundation (no deps):
  ADR-0003 Autoload Scene Composition
  ADR-0014 Test Framework + CI

Layer 1 (deps on Foundation):
  ADR-0002 Config Loading + Persistence       (requires 0003)
  ADR-0006 Signal-Based Decoupling Pattern    (requires 0003)

Layer 2:
  ADR-0005 task_completed Signal Source       (requires 0003, 0006)
  ADR-0008 Mock Mode Strategy                 (requires 0002, 0006)

Layer 3:
  ADR-0001 Data Bridge Transport Strategy     (requires 0002, 0003, 0006, 0008)
```

**Cycles**: None ✅
**Recommended Accept order**: 0003 + 0014 → 0002 + 0006 → 0005 + 0008 → 0001

⚠️ **All ADRs remain `Proposed`.** Per `docs/CLAUDE.md` policy, stories referencing a Proposed ADR are auto-blocked. Nothing can be implemented until at least the Foundation chain is `Accepted`.

---

## GDD Revision Flags (Architecture → Design Feedback)

| GDD | Assumption | Reality | Action |
|---|---|---|---|
| `data-bridge.md` Rule 7 | "each agent in config may include `mock: true`" — per-agent | ADR-0008: MVP is **project-wide** mock only via top-level `"mock"` | Revise GDD Rule 7 wording |
| `task-completion-beat.md` Rules 2.4, 9 | `beat_fired(agent_id: StringName, ...)` | ADRs use `String` (decided) | Revise to `String` |
| `task-completion-beat.md` Rule 2.1 | `ConfigurationLoader.get_agent_type(agent_id)` method | No such method on ConfigLoader per ADR-0002/0003 + Audio Manager GDD ("caller owns lookup") | Either add to ADR-0002 or revise GDD to look up via `get_agent(id).agent_type` field |
| `agent-character-controller.md` | Provisional ASM contract | ADR-0007 BLOCKED on prototype | Hold revisions |

---

## Engine Compatibility Audit

**Engine version consistency**: All 7 ADRs stamp Godot 4.6.2. ✅

**Deprecated API references**: None found (grepped against `deprecated-apis.md`). ✅

**Post-Cutoff APIs declared and verified**:
- `FileAccess.store_* → bool` (4.4 change) — ADR-0002 ✅, ADR-0008 ✅
- `HTTPRequest.timeout`, `HTTPRequest.RESULT_TIMEOUT`, `request_completed` 4-arg signature — ADR-0001 ✅ (VERIFY-7, VERIFY-8 pending)
- `signal.connect(callable)` — ADR-0006 ✅

**HIGH-risk engine domains with NO ADR coverage**:

| Risk | Engine Domain | Affected systems | Missing ADR | Open VERIFY |
|---|---|---|---|---|
| HIGH | Tween cleanup on freed Node2D | TCB, AAL, HUD | ADR-0010 | VERIFY-9 |
| HIGH | CanvasLayer + screen-space overlay (web) | HUD | ADR-0011 | — |
| HIGH | BitmapFont / FontFile import | HUD | ADR-0012 | VERIFY-2, VERIFY-5 |
| HIGH | Web export CORS for AI APIs | Data Bridge | ADR-0004 | VERIFY-4 |
| MEDIUM | `keep_integer` stretch mode | All rendering | ADR-0013 | VERIFY-1 |
| MEDIUM | AnimationMixer.active property | ACC, AAL | ADR-0009 | VERIFY-6 |
| MEDIUM | TileMapLayer Y-sort behaviour | TileMap Renderer | ADR-0013 | VERIFY-3 |

**Engine specialist consultation**: Skipped in this review pass (no engine-specialist subagent invoked). Recommend running `godot-specialist` consultation when the 7 missing ADRs are drafted, particularly ADR-0010 (Tween) and ADR-0012 (BitmapFont) which carry the most engine-API uncertainty.

---

## Architecture Document Coverage

`docs/architecture/architecture.md` v1.0 exists and mirrors `systems-index.md`. All 10 designed MVP systems appear in the System Layer Map. Agent State Machine is correctly marked BLOCKED. No orphaned architecture detected. ✅

**However**, the document contains **stale signal contracts** (Conflicts 1, 3, 4) — it was written before some ADRs locked their contracts and was not back-synced.

---

## Blocking Issues (must resolve before PASS)

1. 🔴 **All 7 ADRs are `Proposed`** — Convert at least ADR-0003 + ADR-0002 + ADR-0006 + ADR-0014 to `Accepted` to unblock Foundation work.
2. 🔴 **Conflict 1** (resolved to String) — propagate edits to architecture.md + TCB GDD + commanders-room-hud GDD.
3. 🔴 **Conflict 2** — fix ADR-0006 example arity.
4. 🔴 **Conflict 3** — sync architecture.md `agent_state_changed` to 3-param + String.
5. 🔴 **Conflict 4** — sync architecture.md Data Bridge signal names to ADR-0001.
6. 🔴 **5 HIGH-risk engine domains with no ADR** — author ADR-0004, 0010, 0011, 0012, plus ADR-0013 (MEDIUM).
7. 🟠 **TR Registry empty** — appended in this review pass.
8. 🟠 **GDD revision flags** — data-bridge.md Rule 7, TCB Rules 2.1 + 2.4 + 9.

## Required ADRs (priority order)

1. **ADR-0010 Tween Lifecycle** (HIGH risk; unblocks TCB + AAL + HUD)
2. **ADR-0004 Web Export Compatibility** (HIGH; gates Data Bridge prototype Q6)
3. **ADR-0013 Stretch Mode** (MEDIUM; foundation rendering decision)
4. **ADR-0011 HUD Rendering** (HIGH; needed before HUD code)
5. **ADR-0012 BitmapFont Strategy** (HIGH; needed before HUD code)
6. **ADR-0009 AnimationPlayer Strategy** (MEDIUM; needed before ACC + AAL)
7. **ADR-0007 Agent State Vocabulary** — author **after** Data Bridge prototype answers Qs 4-5

## Quick wins (text edits only — no new ADRs)

- Sync `docs/architecture/architecture.md` § API Boundaries → ADR-locked signal contracts (Conflicts 1+3+4)
- Edit ADR-0006 example: drop `task_name: String` from `task_completed` (Conflict 2)
- Revise `data-bridge.md` Rule 7 to clarify global-only mock for MVP
- Revise `task-completion-beat.md` Rules 2.4 + 9 to use `agent_id: String`

---

## Handoff

**Immediate actions (top 3)**:
1. Apply the four quick-win text edits (architecture.md sync + ADR-0006 example + GDD revisions). ~30 min total.
2. Move ADR-0003 + ADR-0002 + ADR-0006 + ADR-0014 from `Proposed` → `Accepted` (these are low-risk Foundation decisions ready to ship).
3. Author ADR-0010 (Tween Lifecycle) — highest blocking risk that does not depend on prototype.

**Gate guidance**: When all blocking issues are resolved (especially items 1-5 above), re-run `/gate-check pre-production`. The previous gate FAILED on 2026-05-11 — see `production/gate-checks/2026-05-11-pre-production.md`.

**Rerun trigger**: Re-run `/architecture-review` after each new ADR is written to verify coverage improves and no new conflicts are introduced.

---

## Reflexion Log

`docs/consistency-failures.md` does not exist; not appended to per protocol. If it is created in the future, the four Conflict entries above should be migrated.
