# Session State — The Situation Room

*Last updated: 2026-05-11*

## Current Status

**Phase**: Pre-Production — Technical Setup in progress (9/10 MVP GDDs designed; master architecture v1.0 written; **8/14 ADRs written — 4 Accepted, 4 Proposed**)
**Last completed task**: `/architecture-decision tween-lifecycle` — **ADR-0010 written** at `docs/architecture/adr-0010-tween-lifecycle.md`. Status: Proposed. Mandates `create_tween() + bind_node()` pattern, `kill()` + restart re-trigger, signal-not-await cleanup, presentation-property carve-out for `direct_cross_system_state_write`. godot-specialist consultation confirmed all behaviour for Godot 4.6.2. **VERIFY-9 CLOSED.** Registry updated with `tween_lifecycle_pattern` api_decision + `tween_without_bind_node` forbidden pattern. Same session also resolved 4 cross-doc conflicts (Buckets A1-A4), flipped 4 Foundation ADRs to Accepted (Bucket B), and added `agent_type` field to ConfigurationLoader schema (Option X). Pre-Production gate previous FAIL on 2026-05-11 — re-gate scheduled for **fresh session** (must not run `/architecture-review` in same session as `/architecture-decision` per skill rule).

## Progress Checklist

- [x] `/start` — onboarding complete
- [x] `/brainstorm` — game concept document written (`design/gdd/game-concept.md`)
- [x] `/setup-engine` — Godot 4.6.2 / GDScript configured
- [x] `/art-bible` — all 9 sections complete (`design/art/art-bible.md`)
- [x] `/map-systems` — systems index created (`design/gdd/systems-index.md`)
- [x] `/design-system configuration-loader` — GDD #1 COMPLETE (Designed — pending /design-review in fresh session)
- [x] `/design-system audio-manager` — GDD #2 COMPLETE (Designed — pending /design-review in fresh session)
- [x] `/design-system tilemap-renderer` — GDD #3 COMPLETE (Designed — pending /design-review in fresh session)
- [x] `/design-system data-bridge` — GDD #4 COMPLETE (Designed — pending /design-review + prototype gate)
- [x] `/design-system room-system` — GDD #5 COMPLETE (Designed — pending /design-review)
- [x] `/design-system agent-character-controller` — GDD #7 COMPLETE (Designed — pending /design-review in fresh session)
- [x] `/design-system task-completion-beat` — GDD #9 COMPLETE (Designed — 14 ACs, 6 open questions, pending /design-review in fresh session)
- [x] `/design-system commanders-room-hud` — GDD #10 COMPLETE (Designed — 33 ACs, 8 open questions, pending /design-review in fresh session)
- [ ] `/design-system agent-state-machine` — GDD #6 (MVP, Core, M) — BLOCKED until Data Bridge prototype Qs 4+5 answered
- [ ] ... (10 MVP systems total — see systems-index.md for full order)
- [ ] `/gate-check pre-production` — when all 10 MVP GDDs complete
- [ ] `/create-architecture` — master architecture blueprint (after MVP GDDs approved)

## Key Files

| File | Status |
|---|---|
| `design/gdd/game-concept.md` | Complete |
| `design/gdd/systems-index.md` | Complete — 15 GDD systems + 1 architecture |
| `design/gdd/configuration-loader.md` | Designed (28 ACs, pending /design-review) |
| `design/gdd/audio-manager.md` | Designed (20 ACs, pending /design-review) |
| `design/gdd/tilemap-renderer.md` | Designed (17 ACs, pending /design-review) |
| `design/gdd/data-bridge.md` | Designed (21 ACs, 4 prototype-gated, pending /design-review) |
| `design/gdd/room-system.md` | Designed (15 ACs, pending /design-review) |
| `design/registry/entities.yaml` | Updated — max_agents, cell_size, module_size, poll_interval_default, max_poll_retries, commanders_room_id |
| `design/art/art-bible.md` | Complete (9/9 sections) |
| `design/gdd/task-completion-beat.md` | Designed (14 ACs, 6 open questions, pending /design-review) |
| `HOME.md` | Updated — 8/10 MVP, task-completion-beat ✅, commanders-room-hud NEXT |
| `production/review-mode.txt` | `lean` |

## Key Decisions Made

- **Project identity**: Real AI agent dashboard, not a game. Tool with game aesthetic.
- **Engine**: Godot 4.6.2, GDScript, 2D Renderer, Jolt Physics
- **Targets**: PC (Win/Mac/Linux) + Web (HTML5)
- **Visual identity**: "Institutional Underground" — pixel art 16–32px, 8-color palette, cozy bunker aesthetic
- **Color system**: Amber=idle (#D4882A), Green=active (#4A9A52), Sienna=alert (#A03520)
- **HUD**: Three-glyph vocabulary (●/▬/+), diegetic installed panels, bitmap font 5×7px
- **Sprites**: One sheet per character (row-per-state layout), PNG-8, Aseprite source
- **Tiles**: 8×8px module, 16×16px Godot TileSet cell, TileMapLayer (not TileMap)
- **Review mode**: Lean (directors at phase gates only)
- **Audio Manager decisions**:
  - Bus topology: Master → Music, Master → SFX (two-bus)
  - Pool size: 8 AudioStreamPlayer nodes (pre-instantiated, no runtime allocation)
  - Agent-to-stream mapping: caller owns lookup (Audio Manager is stream-agnostic)
  - Music default: −18 dB | SFX default: −12 dB | Alert: −8 dB
  - Two-tier mute: global toggle (M key) + per-bus via settings panel
  - Settings persist to user://settings.json
- **Data Bridge decisions**:
  - HTTP polling only (MVP); WebSocket post-MVP
  - One HTTPRequest node per agent (12 max); independent polling coroutines
  - Raw String payload — no JSON parsing at bridge layer
  - Per-agent states: UNINITIALIZED → CONNECTING → CONNECTED / STALE / DISCONNECTED / ERROR
  - Backoff: grace(1 failure) → STALE(2nd) → DISCONNECTED(4th); cap 30s; auto-heal
  - Mock mode: `mock: true` in config + cycling JSON array files at `assets/data/mock/[agent_id].json`
  - Web export CORS strategy deferred to prototype
  - poll_interval_default: 5.0s | max_poll_retries: 4 | stale_multiplier: 2.5

## VERIFY Items (Godot 4.4–4.6 specifics to confirm before shipping)

1. `keep_integer` stretch mode path in Godot 4.6.2 Project Settings
2. `BitmapFont` class status — deprecated or still first-class in 4.6?
3. `TileMapLayer` Y-sort behavior (`y_sort_enabled`) in 4.6.2
4. Web export texture compression option location in 4.6 Export Presets
5. BMFont `.fnt` import via `FontFile` — confirm unchanged from 4.3 behavior
6. `AnimationMixer`/`AnimationPlayer` API — `active` property confirms unchanged
7. `HTTPRequest.request_completed` signal signature — confirm unchanged in 4.4–4.6
8. `HTTPRequest.timeout` — confirm clean cancellation behavior in 4.6.2
9. ~~`Tween` on freed node reference~~ — **CLOSED 2026-05-11 by ADR-0010.** godot-specialist confirmed `bind_node(target)` is the documented Godot 4.6.2 mitigation; Tween auto-kills when bound target is freed (no `finished` emission). Mandatory pattern in ADR-0010.

## Biggest Risk

**Data bridge prototype**: The Data Bridge GDD is written but 4 ACs are prototype-gated. The prototype must answer 6 specific questions (see data-bridge.md Section C — Prototype Plan) before Agent State Machine GDD can be designed. Run the prototype as early as possible — BEFORE any art production begins.

## Recommended Next Step

Two parallel paths available:
1. **`/design-system agent-character-controller`** — GDD #7 (MVP, Feature, M). Depends on Agent State Machine (not yet designed), TileMap Renderer ✅, Room System ✅. Can begin with provisional Agent State Machine assumptions.
2. **Run the Data Bridge prototype** — unblocks Agent State Machine (GDD #6). If prototype Qs 4+5 are answered, Agent State Machine can be designed next, then Agent Character Controller properly.

## Open Questions

- WCAG AA contrast: S2 Active Green (#4A9A52) against W2 Institutional Grey-Warm (#4A4035) may fail — verify before shipping.
- Data Bridge web export CORS: deferred to prototype. Which AI APIs support CORS for Godot web exports?
- Which real AI agent APIs to target first for the Data Bridge prototype? (Claude API, Cursor, other?)

## Session Extract — /architecture-review 2026-05-11

- Verdict: **CONCERNS** (pre-production gate cannot pass without resolution)
- Requirements: ~70 total — ~30 covered (Proposed), ~9 partial, ~25 gaps, ~6 blocked
- New TR-IDs registered: 60 entries across 11 systems (config, audio, tilemap, data-bridge, asm, room, acc, aal, tcb, hud, xc)
- agent_id type conflict resolved: **adopt String everywhere** (ADRs win); pending edits to architecture.md + TCB GDD + HUD GDD
- GDD revision flags: data-bridge.md (Rule 7 mock wording), task-completion-beat.md (Rules 2.1, 2.4, 9)
- Top ADR gaps: ADR-0010 Tween Lifecycle (HIGH), ADR-0004 Web Export (HIGH), ADR-0013 Stretch Mode (MEDIUM)
- Four cross-doc conflicts identified — all require architecture.md back-sync to ADR-locked contracts
- All 7 ADRs remain Proposed — stories will be auto-blocked until at least Foundation chain (0003, 0014, 0002, 0006) reaches Accepted
- Report: docs/architecture/architecture-review-2026-05-11.md
- Index: docs/architecture/traceability-index.md
- Registry: docs/architecture/tr-registry.yaml (60 entries)

## Session Extract — Remediation + ADR-0010 (2026-05-11, follow-up)

Bucket-by-bucket execution of the 2026-05-11 architecture review's punch list. All four cross-doc conflicts resolved, Foundation ADRs accepted, ADR-0010 (Tween Lifecycle) authored from scratch.

**Bucket A — Cross-doc conflict resolution (4 sub-buckets, ~30 edits across 5 files)**
- A1: `docs/architecture/architecture.md` synced to ADR-locked contracts — `agent_id: String` everywhere (was `StringName`); `agent_state_changed` now 3-param (added `previous_state`); Data Bridge signal names corrected to `agent_response_received` / `agent_connection_changed` (was `payload_received` / `connection_state_changed`). 14 edits. Room ID `StringName` preserved (separate identifier, not a conflict).
- A2: `adr-0006-signal-based-decoupling.md` example fixed — dropped `task_name: String` from `task_completed` (now matches ADR-0005 binding). 1 edit.
- A3: `data-bridge.md` per-agent mock phrasing in E5/E6/Dependencies/AC-10-12 refactored to "mock mode active, an agent…" — Rule 7 itself was already correctly global-only. 4 edits.
- A4: **Option X applied** — added `agent_type: string` field (optional, default `"default"`) to ConfigurationLoader per-agent schema; TCB now calls `ConfigurationLoader.get_agent(id).get(&"agent_type", "default")` instead of the non-existent `get_agent_type()`. ~10 edits across `configuration-loader.md` + `task-completion-beat.md`. TCB Open Questions §2 + §3 marked RESOLVED.

**Bucket B — Foundation ADR acceptance**
ADR-0003, 0014, 0002, 0006 flipped from `Proposed` → `Accepted (2026-05-11)`. Stories referencing these can now pass `/story-readiness`. ADR-0001, 0005, 0008 remain Proposed (correct — they have outstanding dependencies).

**Bucket C1 — ADR-0010 Tween Lifecycle Management**
- File: `docs/architecture/adr-0010-tween-lifecycle.md` (Status: Proposed)
- godot-specialist consultation completed; **VERIFY-9 closed**
- Locks: mandatory `bind_node(target)` immediately after `create_tween()`; sequential phases via chained `tween_property()` on one Tween; re-trigger via `kill()` + new `create_tween()` (never `stop()`); cleanup via `finished` signal connection (never `await tween.finished` when target may free); pause behaviour controlled by owning Node's `process_mode`
- Carve-out: presentation-property animation (`modulate`, `scale`, transient `position`/`rotation`) on cross-system nodes is **exempt** from `direct_cross_system_state_write` — explicitly enumerated in ADR
- Registry: added `tween_lifecycle_pattern` api_decision + `tween_without_bind_node` forbidden_pattern in `docs/registry/architecture.yaml`

**Numbers**
- Files touched: 8 (architecture.md, adr-0006, adr-0002, adr-0003, adr-0014, data-bridge.md, configuration-loader.md, task-completion-beat.md, adr-0010 NEW, architecture.yaml, active.md)
- ADRs now: 8 written (4 Accepted, 4 Proposed). Was 7 Proposed at session start.
- VERIFY items: 1 closed (VERIFY-9). 8 remaining.
- TR registry: unchanged at 60 entries (this session was conflict resolution + ADR authoring, not new requirement IDs)

**Bucket D (next session)**
Re-run `/gate-check pre-production` in a **fresh session** (skill-mandated isolation from `/architecture-decision`).

**Remaining ADR gaps** (priority order)
ADR-0004 (Web Export, HIGH), ADR-0013 (Stretch Mode, MEDIUM), ADR-0011 (HUD Rendering, HIGH), ADR-0012 (BitmapFont, HIGH), ADR-0009 (AnimationPlayer, MEDIUM), ADR-0007 (Agent State Vocabulary, BLOCKED on Data Bridge prototype).
