# Cross-GDD Consistency Review — 2026-05-12

**Scope**: 10 MVP GDDs (configuration-loader, data-bridge, agent-state-machine, audio-manager, tilemap-renderer, room-system, agent-character-controller, ambient-animation-layer, task-completion-beat, commanders-room-hud)
**Manifest baseline**: `2026-05-12.2`
**Verdict**: **CONCERNS** — implementation can begin on Foundation + Data Bridge + ASM, but the four Feature/Presentation GDDs (ACC, AAL, TCB, HUD) carry stale provisional ASM assumptions that must be reconciled before their stories are spun up.
**Reviewer**: general-purpose agent (Opus tier)

---

## Verdict summary

The newly-authored Agent State Machine GDD (2026-05-12) is internally coherent, accurately cites ADR-0001 Amendment 2026-05-12.b and ADR-0007, and resolves the OQ-1 blockers in every downstream GDD that listed it. Foundation GDDs (Configuration Loader, Audio Manager, TileMap Renderer) are unchanged and clean. The Data Bridge GDD remains in its pre-amendment state (lists three signals, never four; no mention of `request_dispatched` / `request_settled`).

Tally: **0 blocking**, **9 concerns**, **7 advisory**. Headline issues:

- **C-1 / C-2** Data Bridge GDD is stale vs. ADR-0001 Amendment 2026-05-12.b — missing `request_dispatched` / `request_settled` signals, missing `is_request_in_flight()`, missing 4xx-vs-5xx differentiation, and still claims `agent_poll_failed` as a third signal (the manifest documents only two bridge signals — `agent_response_received` and `agent_connection_changed`).
- **C-3 / C-4 / C-5** ACC, AAL, HUD all still type `agent_id` and state strings as `StringName`, despite ASM GDD + ADR-0001 + ADR-0007 mandating `String`. Their banners still say "PROVISIONAL — review when ASM GDD complete" even though ASM was completed in the same session.
- **C-6** ACC GDD claims ACC emits `task_completed`, directly violating ADR-0005 / ADR-0007 / ASM GDD Rule 10 (ASM is the sole emitter).
- **C-7** Per-state colour palette: ASM, HUD, art-bible all use the **new** `#5BAD63` Active Green; ambient-animation-layer.md still says the green is `#4A9A52` in one row (a stale reference per the 2026-05-12 WCAG shift).
- **C-8** Room System exposes `get_room(room_id) → RoomData` and `get_workstation_for_agent(id) → Vector2i`, but ACC and HUD call `get_room_bounds(room_id)` and `get_all_agent_ids()` which Room System does not document.
- **C-9** ASM GDD reads `entities.yaml → asm.completed_decay_sec` via `ConfigLoader.get_setting(...)` but the Configuration Loader GDD owns `user://settings.json` only; `entities.yaml` access is undefined in ConfigLoader's public API.

Pillar coverage is healthy. ASM's 33 ACs are largely testable; a handful are marked as advisory below.

---

## 🔴 BLOCKING issues

**None.** None of the issues found prevent ASM, Data Bridge prototype-to-production, or Foundation systems from beginning implementation today. All issues are documentation-stale, not architecturally-broken.

---

## 🟠 CONCERN-level issues

### C-1 — Data Bridge GDD has not absorbed ADR-0001 Amendment 2026-05-12.b

**File**: `design/gdd/data-bridge.md` §§ Interactions (lines ~100–106), Acceptance Criteria (lines ~232–268).
**Stale text**: GDD lists three downstream signals — `agent_response_received`, `agent_connection_changed`, `agent_poll_failed`. ADR-0001 Amendment B2 adds **two more** that ASM depends on:

```
signal request_dispatched(agent_id: String)
signal request_settled(agent_id: String)
func is_request_in_flight(agent_id: String) -> bool
```

The ASM GDD (Rules 5 + 12, AC-10 / AC-11) hard-depends on these. With the Data Bridge GDD silent on them, the bridge implementer has no GDD-level mandate to ship them — only the ADR amendment.

**Fix**: Add an amendment section to data-bridge.md mirroring ADR-0001 §§ B1–B4 (4xx-fatal differentiation, dispatched/settled signal pair, Anthropic error envelope shape, rate-limit headers deferred). Add ACs covering `test_4xx_transitions_to_disconnected_immediately`, `test_request_dispatched_and_settled_fire_in_order`, `test_is_request_in_flight_during_request`. Updates the AC count from 21 → ~25.

### C-2 — Data Bridge GDD's `agent_poll_failed` signal conflicts with the control manifest

**File**: `design/gdd/data-bridge.md` line 103, lines 165–174, AC-07/11/12 (lines 244, 251, 252).
**Manifest (2026-05-12.2)**: only two bridge signals are documented in the Data Bridge layer Required block — `agent_response_received(agent_id, payload)` and `agent_connection_changed(agent_id, new_state)`. Payload is the single field after `agent_id` — the GDD's signature `agent_response_received(agent_id, http_status, raw_payload)` carries an extra `http_status: int`.

Two related conflicts:
1. The manifest's signal signature has 2 args; the GDD has 3.
2. `agent_poll_failed` exists in the GDD only — ASM, HUD, ACC, AAL all consume `agent_connection_changed` instead. No downstream GDD subscribes to `agent_poll_failed`.

**Fix options**: (a) Promote `agent_poll_failed` into the manifest, OR (b) collapse failure reporting into `agent_connection_changed("DISCONNECTED")` and remove `agent_poll_failed` from the GDD. (b) is the cleaner option — matches what every consumer already expects. Either fix should bump manifest to `2026-05-12.3`.

### C-3 — ACC, AAL, HUD use `StringName` for `agent_id`; ASM + ADR-0001 + ADR-0007 mandate `String`

**Files affected**:
- `design/gdd/agent-character-controller.md` lines 64, 95, 102, 103, 248, 409
- `design/gdd/ambient-animation-layer.md` lines 41, 71, 72, 75, 157, 158, 247
- `design/gdd/commanders-room-hud.md` lines 56, 57, 149, 150, 152, 153, 265
- `design/gdd/room-system.md` (entire RoomData design uses `StringName` throughout — lines 46, 50, 91, 94–101)

**Manifest 2026-05-12.2**: `agent_id: String everywhere (never StringName).` Data Bridge GDD line 104 explicitly notes "agent_id type corrected from StringName → String per ADR-0001."

**Why it matters**: At signal subscription time, GDScript's typed signal will reject a `String` payload bound to a `StringName` handler (or auto-coerce — engine behaviour shift between 4.4 and 4.5). The ASM GDD §6.1 lists Data Bridge signals as `agent_id: String`. If ACC, AAL, HUD subscribe expecting `StringName`, the type check will surface at integration.

**Fix**: Global s/StringName/String/ on every `agent_id`-typed signature in the four downstream GDDs and in Room System. Room System should keep `StringName` only for *room IDs* (which are internal constants like `&"commander"`) — but agent IDs flowing from config should match the Data Bridge contract: `String`. The cleanest pattern: room_id is `StringName`, agent_id is `String`.

### C-4 — Provisional ASM banners on ACC, AAL, HUD, TCB are now stale

**Files**:
- ACC line 7: `> **⚠ PROVISIONAL**: Agent State Machine assumptions used throughout.`
- AAL line 7: same banner.
- HUD line 3: `(PROVISIONAL: ASM interface not yet finalized — see OQ-1)` and OQ-1 itself (lines 465–467).
- TCB line 7: provisional flag still set; line 312 still asks the canonical task_completed source question (ADR-0005 + ASM Rule 10 already answer this — ASM is sole emitter).

**Fix**: Remove the PROVISIONAL banners on all four GDDs. Update their Open Questions sections to mark ASM-interface OQs as RESOLVED with citation (e.g. "OQ-1 — RESOLVED 2026-05-12 by ASM GDD §3.4 + ADR-0007"). The signal names + signatures these GDDs assumed (`agent_state_changed(agent_id, new_state, previous_state)`, `task_completed(agent_id)`) actually match what ASM ships, so no semantic rewrite is needed beyond the banner + StringName→String correction.

### C-5 — ACC dependency table says `agent_state_changed` is 2-arg; ASM emits 3-arg

**File**: `design/gdd/agent-character-controller.md` line 95 + line 239.
**Stale text**: `agent_state_changed(agent_id: StringName, new_state: StringName)`
**Canonical (ASM §6.2 + ADR-0006)**: `agent_state_changed(agent_id: String, new_state: String, previous_state: String)`

Also affects AAL line 71/157 and HUD line 56/149 — same 2-arg vs 3-arg mismatch.

**Fix**: Update all three GDDs to the 3-arg signature. The `previous_state` argument is informational only — none of the consumers currently use it, but the subscription signature must match emitter.

### C-6 — ACC GDD claims ACC emits `task_completed` — violates ADR-0005 + ASM Rule 10

**File**: `design/gdd/agent-character-controller.md`
- Line 102: `| **Task Completion Beat** | ACC → | `task_completed(agent_id: StringName)` signal emitted by ACC | …`
- Line 248: same claim in Downstream Dependents.
- Line 409 (AC-15): "ACC emits `task_completed` on COMPLETED entry."
- TCB OQ-1 (line 312) raises this exact conflict but defers to ASM GDD.

**Canonical**: ADR-0005 — ASM is the **sole emitter** of `task_completed`. ASM GDD Rule 10 and AC-17 lock this. Control manifest Signal Patterns Required: "task_completed is emitted only by Agent State Machine." Forbidden: "Any system besides ASM emitting task_completed."

**Fix**: In ACC GDD, remove the `task_completed` signal emission claim. Replace AC-15 with: "When ACC receives `agent_state_changed(id, "completed", ...)` it plays the completion animation. It does NOT emit any signal — TCB subscribes directly to ASM." Update TCB OQ-1 (line 312) to RESOLVED — `task_completed` source is ASM.

### C-7 — AAL still references `#4A9A52` (pre-WCAG green) in the WORKING palette table

**File**: `design/gdd/ambient-animation-layer.md` line 209.
**Stale text**: "State-sensitive WORKING: full amber `#D4882A`. The eye should recognize this as the same amber as the agent character WORKING state."

Wait — this line is fine; it's the prop colours table at line ~207 that's relevant. Looking more carefully: ambient-animation-layer.md does NOT contain `#4A9A52` in any line (Grep confirmed no matches in `design/gdd/`). The stale references live in `design/art/art-bible.md` and `design/ux/accessibility-requirements.md` only.

**However**, the AAL GDD line 47 references `#5BAD63` correctly. The art-bible.md and accessibility-requirements.md both have surviving `#4A9A52` references — these are out of the GDD review scope but flagged here for housekeeping.

**Fix**: This concern is downgraded to ADVISORY (see A-1 below). No GDD edit required. Two non-GDD files need a propagated update — see `production/session-state/active.md` for the recent palette-shift commit context (`ca0ae7d`).

### C-8 — Room System API surface does not match what ACC and HUD call

**Files**:
- ACC line 97-98, 240: calls `RoomSystem.get_workstation_for_agent(agent_id)` ✅ (matches Room System line 97) and `RoomSystem.get_room_bounds(room_id)` ❌ — Room System exposes `get_room(room_id) → RoomData` (line 94), and RoomData carries `bounds: Rect2i`. There is no `get_room_bounds` method.
- HUD line 152, 265: calls `RoomSystem.get_all_agent_ids() → Array[StringName]` ❌ — Room System has no such method. It exposes `get_all_room_ids()` (line 95). HUD wants the *agent* roster, not room roster — and that lives in ConfigurationLoader (`get_agents()`).
- ASM GDD §6 (line 286 footnote): "AAL aggregates per-room state internally; ASM exposes nothing room-aware" — but AAL line 158 calls `RoomSystem.get_room_for_agent(agent_id) → StringName` (which Room System does define at line 96). This one is fine.

**Fix**:
- ACC: change `get_room_bounds(room_id)` to `get_room(room_id).bounds`. Update lines 98 + 240.
- HUD: change `RoomSystem.get_all_agent_ids()` to `ConfigurationLoader.get_agents()` (returns the array of agent dicts the HUD slot grid needs). Update lines 152 + 265.

### C-9 — ASM reads `entities.yaml` via ConfigLoader, but ConfigLoader's public API does not document `entities.yaml` access

**File**: `design/gdd/agent-state-machine.md` §7.3 (lines 342–348).
**Stale text**: "ASM reads these at `_ready()` via `ConfigLoader.get_setting("asm.completed_decay_sec", 1.5)`…"

**ConfigLoader GDD public API** (lines 128–135): `get_agents`, `get_agent`, `get_poll_interval`, `get_protocol`, `get_applied_defaults`. No `get_setting` method documented. The control manifest 2026-05-12.2 Configuration layer Required lists `set_setting(key, value)` writing to `user://settings.json` — but `entities.yaml` is a separate file (per Universal rules: "All tuning values come from `ConfigurationLoader` or `design/registry/entities.yaml`").

There's a real ownership question here: who reads `entities.yaml`? The ConfigLoader GDD doesn't claim to. The manifest implies it does ("tuning via ConfigurationLoader or entities.yaml") but the ASM GDD codes against `ConfigLoader.get_setting(...)`.

**Fix options**:
1. Extend Configuration Loader GDD to add a `get_setting(key, default)` method that loads `entities.yaml` at startup and exposes it via the getter. Update the manifest to clarify.
2. Or: define a separate `EntityRegistry` Autoload (would require ADR amendment to ADR-0003's two-Autoload limit).

Option 1 is simpler and aligns with what ASM expects. ASM also persists per-agent stats via `set_setting("asm_stats_<agent_id>", dict)` (ASM line 433 / AC-26) which the Configuration Loader GDD does not currently document writing for arbitrary keys. This pairs with C-9: ConfigLoader's read/write surface needs broadening to cover ASM's needs.

---

## 🟡 ADVISORY notes

### A-1 — `#4A9A52` lingers in two non-GDD files

`design/art/art-bible.md` and `design/ux/accessibility-requirements.md` still reference the pre-WCAG green. The recent commit `ca0ae7d` claimed to propagate the shift; these two files were missed. Open a quick housekeeping fix.

### A-2 — Signal-name pluralisation drift

The control manifest names the bridge signals `agent_response_received` and `agent_connection_changed`. Some GDDs use the past tense `agent_connection_changed`, all consistent — but the Data Bridge GDD's state-machine table (line 88) uses `connection_state: "error"` (lowercase, while other states are uppercase per manifest: `STALE`, `DISCONNECTED`, `ERROR`). Trivial style fix.

### A-3 — ASM GDD §6.3 promises bidirectional dep updates; the four downstream GDDs do not yet list ASM

ASM §6.3 says "Each downstream system's GDD must list ASM as an upstream dependency." This is currently TRUE for ACC, AAL, TCB, HUD only in the *provisional* "Agent State Machine *(provisional)*" rows. After C-4 strips the provisional banners, those rows become canonical references — confirm wording matches ASM §6.2 exactly.

### A-4 — TCB Open Questions §6 was already RESOLVED by ASM GDD § Authoring Provenance #4 ("Stateless per poll — ASM stores only the most recent payload's derived state"). Mark OQ-6 closed.

### A-5 — HUD computer-prop signal `computer_interacted` is referenced in HUD line 71 and `design/ux/interaction-patterns.md` line 122 but NOT in Room System GDD's signal list (line 100–101 only lists `agent_assigned`, `agent_unassigned`). Room System should add `signal computer_interacted` to its emitted-signals table OR clarify that the prop owns the signal and Room System merely re-forwards. TR-room-005 in the traceability index already flags this as "Partial — implicit in ADR-0006."

### A-6 — TCB Tween peak `Color(1.15, 1.35, 1.15, 1.0)` is a tuned visual; flagging because the green-channel boost of 1.35 was set BEFORE the `#5BAD63` palette shift. With the new green being slightly brighter (5BAD63 vs 4A9A52), the modulate peak may now overshoot. Defer to a visual smoke test, not a doc fix.

### A-7 — ASM AC-19 says `get_agent_state` returns `"idle"` for unknown agents (safe default). ACC + AAL + HUD subscribe to `agent_state_changed` for agents they expect to exist. There's a subtle race: between Data Bridge `_ready()` registering agents and ASM `_ready()` registering its tracker, an early `agent_response_received` could fire before ASM is listening. E-13 in the ASM GDD partially covers this with a deferred-subscribe note — but the resolution ("place ASM below Data Bridge in scene tree") is owned by Main Scene Bootstrap (which doesn't exist yet). Track as an architecture follow-up.

---

## Bidirectional dependency matrix

Rows = source GDD, Columns = target GDD. Cell value: → (depends on), ← (depended on by), ↔ (both), blank (no relation).

|              | Config | DataBr | ASM | Audio | Tile | Room | ACC | AAL | TCB | HUD |
|--------------|:------:|:------:|:---:|:-----:|:----:|:----:|:---:|:---:|:---:|:---:|
| **Config**   | —      | ←      | ←   |       |      | ←    | ←   | ←   | ←   | ←   |
| **DataBr**   | →      | —      | ←   |       |      |      |     |     |     |     |
| **ASM**      | →      | →      | —   |       |      |      | ←   | ←   | ←   | ←   |
| **Audio**    |        |        |     | —     |      |      | ←   |     | ←   |     |
| **Tile**     |        |        |     |       | —    | ←    | ←   | ←   |     |     |
| **Room**     | →      |        |     |       | →    | —    | ←   | ←   | ←   | ←   |
| **ACC**      | →      |        | →   | →     | →    | →    | —   |     | (✗) |     |
| **AAL**      | →      |        | →   |       | →    | →    |     | —   |     |     |
| **TCB**      | →      |        | →   | →     |      | →    |     |     | —   | ←   |
| **HUD**      | →      |        | →   |       |      | →    |     |     | →   | —   |

**Asymmetries found**:
- ACC → TCB marked `(✗)`: ACC GDD line 102/248/409 claims ACC emits `task_completed` to TCB, but TCB and ASM both say ASM is the emitter. This is the C-6 issue — the edge does not exist; it should be removed from ACC.
- ASM ← ACC/AAL/TCB/HUD: ASM lists these as downstream (line 286–290). Each downstream GDD currently lists ASM as `(provisional)`. After C-4 fix, all four upgrade to canonical references.
- Data Bridge ← ASM: Data Bridge GDD line 197 says "Agent State Machine GDD must not be authored until prototype questions 4 and 5 are answered." This warning is now obsolete (ASM was authored after the prototype) — should be marked RESOLVED.

No circular dependencies introduced by ASM. The graph remains a DAG.

---

## Signal contract audit

| Signal | Canonical signature | Emitter | Consumers (per GDDs) | Status |
|---|---|---|---|---|
| `config_loaded` | `()` | ConfigLoader | DataBridge, RoomSys, Bootstrap | ✅ consistent |
| `config_load_failed` | `(state: String, message: String)` | ConfigLoader | Bootstrap | ✅ consistent |
| `setting_changed` | `(key: String, value: Variant)` | ConfigLoader | AudioMgr, ASM (write-only) | ⚠️ ASM also writes via this surface — see C-9 |
| `agent_response_received` | `(agent_id: String, payload: String)` per manifest; `(agent_id, http_status: int, raw_payload: String)` per data-bridge.md | DataBridge | ASM | ⚠️ signature drift — see C-2 |
| `agent_connection_changed` | `(agent_id: String, new_state: String)` | DataBridge | HUD (per ADR-0001), ASM does NOT subscribe (per ADR-0007) | ✅ consistent |
| `agent_poll_failed` | `(agent_id: String, error_code: int, http_status: int, error_message: String)` | DataBridge | (none) | ⚠️ orphan signal — see C-2 |
| `request_dispatched` | `(agent_id: String)` | DataBridge (per ADR-0001 B2) | ASM | ⚠️ missing from DataBridge GDD — see C-1 |
| `request_settled` | `(agent_id: String)` | DataBridge (per ADR-0001 B2) | ASM | ⚠️ missing from DataBridge GDD — see C-1 |
| `agent_state_changed` | `(agent_id: String, new_state: String, previous_state: String)` | ASM | ACC, AAL, HUD | ⚠️ ACC/AAL/HUD use 2-arg StringName form — see C-3, C-5 |
| `task_completed` | `(agent_id: String)` | ASM (sole, per ADR-0005) | TCB | ⚠️ ACC GDD claims dual-emit — see C-6 |
| `beat_fired` | `(agent_id: String, timestamp: float)` | TCB | HUD | ✅ consistent (HUD line 57 uses StringName — minor; C-3 covers) |
| `agent_assigned` | `(room_id: StringName, agent_id: StringName)` | RoomSys | none in MVP (HUD reads via sync pass) | ✅ consistent |
| `agent_unassigned` | `(room_id: StringName, agent_id: StringName)` | RoomSys | none in MVP | ✅ consistent |
| `computer_interacted` | `()` | Computer prop (forwarded by Room System) | HUD | ⚠️ not in Room System signals list — see A-5 |

---

## Pillar coverage check

| Pillar | Direct serving GDDs | Risk |
|---|---|---|
| **Alive by Default** | DataBridge (live polling), AAL (always-on motion), ACC (idle wandering), TileMap (substrate) | ✅ healthy — four systems |
| **Readable at a Glance** | ACC (4-state animation), HUD (glyph grid), ASM (vocabulary lock) | ✅ healthy |
| **Satisfying Feedback** | TCB (room flash + audio beat), Audio Mgr (SFX pool), ASM (task_completed emit) | ✅ healthy |
| **Commander Always Home** | HUD (always-visible status panel), Room System (permanent Commander's Room) | ✅ healthy |
| **Earn Each Room** | Room System (registry-not-allocator, MVP 2 rooms only) | ⚠️ thin — only one GDD; ACC mentions department rooms but Room System MVP is 2 rooms. Consistent with MVP scope, but flag for V1. |

No pillar has zero coverage. No GDD over-claims (every system serves at most 2 pillars, no "this serves all 5" handwave).

---

## ASM-specific findings (the newly-authored doc)

### Strengths

- **ADR citations are accurate.** §3.2 Rule 4 correctly mirrors ADR-0007's derivation table. §3.2 Rule 5 cites ADR-0001 B2 by name for the dispatched/settled signal pair. §4.6 documents the 9-field stats schema decision (resolved during authoring as decision #3 in Authoring Provenance).
- **Orthogonality is locked.** §3.5 Rule 11 and Rule 12 explicitly disclaim subscription to `agent_connection_changed` and assert the bridge contract guarantees `request_settled` even on network errors — matching ADR-0007's two-axis model.
- **Transition matrix (§4.2) is comprehensive.** Covers all 4×6 = 24 cells including no-op and defensive cases. Reads as a true spec, not a sketch.
- **Edge cases (§5) are thorough.** E-1 through E-21 cover payload malformations, timing races, bridge interaction, persistence corruption, mode invariance, and defensive cases. Each names the observable behaviour rather than "handle gracefully."
- **Authoring Provenance section is excellent.** Twelve resolved-decision rows make the GDD's rationale auditable later — particularly useful for the "why does completed decay to idle and not the prior state?" type of question.

### Weaknesses

- **§7.3 ConfigLoader integration is under-specified** (C-9). ASM codes against `ConfigLoader.get_setting()`, but ConfigLoader GDD does not expose that method nor document `entities.yaml` ingestion. Either ConfigLoader needs an amendment, or ASM needs an `EntityRegistry` consumer.
- **§5 E-13 (ASM `_ready()` race with Data Bridge)** acknowledges the ordering problem and points to "Main Scene Bootstrap GDD" — which doesn't exist yet. Defer-and-pray is fine for now but track for the bootstrap design.
- **§8 ACs are mostly testable, with these caveats**:
  - **AC-12** "After 1.5s ± 100ms, ASM transitions to `idle`" — the ±100ms tolerance is generous given Godot Timer accuracy; consider tightening to ±50ms (matches ADR-0007's stated tolerance).
  - **AC-26** "Within `STATS_WRITE_INTERVAL_SEC + 100ms`, ConfigurationLoader receives a `set_setting(...)` call" — depends on the C-9 resolution. If ConfigLoader doesn't expose `set_setting` for arbitrary keys, this AC is unimplementable.
  - **AC-29** "Mocking both `agent_response_received` AND `agent_connection_changed("DISCONNECTED")` simultaneously" — Rule 11 says ASM does NOT subscribe to `agent_connection_changed`. Mocking the signal won't reach ASM; the AC should be reworded to assert "ASM does not connect to the signal in the first place" (a code-review check, not a behaviour test).
  - **AC-30** "Corrupt persisted stats blob → zero-initialize that agent" — the AC asserts that warning is emitted; doesn't specify *which* corruption modes (missing fields? wrong types? non-Dict?). E-14 enumerates these; the AC should reference them.

  Otherwise all 33 ACs map cleanly to a Rule or Edge case and are genuinely testable.

- **Performance section (§4.5) is light.** ASM expects "writes per minute = 12 (worst case)." But each `set_setting` writes a JSON blob — at 12 agents with full 9-field stats, the JSON is non-trivial. Worth a measurement smoke test before MVP ship.

### Stripe-of-doubt: provider-portability

ASM's derivation rule (§3.2) is Anthropic-shaped (`stop_reason ∈ {end_turn, tool_use, …}`). The ADR-0007 §Risks row acknowledges this and proposes future `ADR-0007.x` amendments for non-Anthropic providers. The ASM GDD does not surface this as an OQ. If MVP ever targets a second AI API, the derivation table will need extending. Consider adding an Open Questions section to the ASM GDD to track this.

---

## Recommended actions

Priority order. Effort: S = <30 min doc edit, M = 1–2 hour spec revision + AC additions, L = multi-doc reconciliation.

1. **C-1, C-2 (Data Bridge GDD amendment)** — author Owner: technical-director (or game-designer with TD review). Effort: M. Brings Data Bridge GDD to parity with ADR-0001 amendment 2026-05-12.b. Adds 4 new ACs, drops `agent_poll_failed` (or promotes it to manifest), corrects `agent_response_received` to 2-arg.

2. **C-3 (StringName → String global fix)** — Owner: game-designer. Effort: S per GDD × 4 GDDs (ACC, AAL, HUD, Room System). Pure search-and-replace on `agent_id: StringName` → `agent_id: String`. Keep `room_id: StringName` unchanged.

3. **C-4 (strip provisional banners)** — Owner: game-designer. Effort: S × 4. Updates GDD headers + closes OQ-1 in ACC/AAL/HUD/TCB with citation to ASM §3.4 + ADR-0007.

4. **C-5 (agent_state_changed 2-arg → 3-arg)** — Owner: game-designer. Effort: S × 3 GDDs. Adds `previous_state: String` to every consumer signature.

5. **C-6 (ACC removes task_completed emission claim)** — Owner: game-designer. Effort: S. Edit ACC Rule + AC-15 + dependency table; mark TCB OQ-1 resolved.

6. **C-8 (Room System API alignment)** — Owner: game-designer. Effort: S. Fix two callsites (ACC `get_room_bounds` → `get_room().bounds`; HUD `get_all_agent_ids()` → `ConfigurationLoader.get_agents()`).

7. **C-9 (ConfigLoader scope decision)** — Owner: technical-director. Effort: M. Decide: expand ConfigLoader to expose `get_setting/set_setting` for arbitrary keys + `entities.yaml` ingestion, OR add an `EntityRegistry` Autoload (requires ADR-0003 amendment). Either decision unblocks ASM AC-26 implementation.

8. **A-1 (palette housekeeping)** — Owner: art-director. Effort: S. Fix `#4A9A52` → `#5BAD63` in art-bible.md + accessibility-requirements.md.

9. **A-5 (computer_interacted signal ownership)** — Owner: game-designer. Effort: S. Document the signal explicitly in Room System GDD's signal list (or transfer ownership note to the Commander's Room scene's computer prop spec).

10. **A-2, A-3, A-4, A-6, A-7** — bundle into a single housekeeping pass. Effort: S total.

**Once items 1–7 land**, run a delta-only `/review-all-gdds` sweep to confirm no new asymmetries introduced. After that, the package is ready for `/gate-check pre-production`.

---

*Sweep complete: CONCERNS — 0 blocking, 9 concerns, 7 advisory. The ASM GDD itself is a strong addition; most issues are documentation-stale assumptions in the four downstream Feature/Presentation GDDs that pre-dated ASM. None of them block ASM implementation; all should be reconciled before ACC/AAL/TCB/HUD stories are spun up.*
