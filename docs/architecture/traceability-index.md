# Architecture Traceability Index

**Last Updated**: 2026-05-12
**Engine**: Godot 4.6.2
**Source review**: `docs/architecture/architecture-review-2026-05-12.md` (supersedes 2026-05-11)

## Coverage Summary

| Metric | 2026-05-11 | 2026-05-12 (am) | 2026-05-12 (pm — post-Sprint-1) |
|---|---|---|---|
| Total requirements (per architecture.md baseline) | ~70 | ~70 (60 in registry) | ~70 (60 in registry) |
| Covered by **Accepted** ADRs | 0 | 56 (~93%) | **60 (100%)** |
| Partial / GDD-self-sufficient | ~9 | ~0 | 0 |
| Gap (no ADR) | ~25 (~36%) | 0 | **0** |
| Blocked (ADR-0007 awaits Data Bridge prototype) | ~6 | 4 (TR-asm-002, 004, 005, 006) | **0 — unblocked by Sprint 1** |

> ✅ **14 of 14 ADRs Accepted as of 2026-05-12 pm.** ADR-0007 (Agent State Vocabulary) written + Accepted after Sprint 1 prototype harvested real Anthropic API findings. Source: `prototypes/data-bridge/findings.md` + `docs/architecture/adr-0007-agent-state-vocabulary.md`.
> Stories referencing any Accepted ADR may now pass `/story-readiness`. No architectural blocks remain in the Pre-Production critical path.

## TR-ID Mapping (initial registration)

Stable IDs assigned by this review pass. See `tr-registry.yaml` for canonical entries.

### Configuration Loader (system: `config`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-config-001 | Autoload singleton initialised before any scene `_ready()` | ADR-0003 | ✅ Covered (Accepted 2026-05-12) |
| TR-config-002 | Resolves `config.json` path per platform (PC/macOS/web/editor) | ADR-0002 | ✅ Covered (Accepted 2026-05-12) |
| TR-config-003 | Owns `user://settings.json` persistence (load/write + `setting_changed` signal) | ADR-0002 | ✅ Covered (Accepted 2026-05-12) |
| TR-config-004 | Schema versioning via `schema_version: int` (mismatch → CONFIG_INVALID) | ADR-0002 | ✅ Covered (Accepted 2026-05-12) |
| TR-config-005 | `is_mock()` reads top-level `"mock": bool` from config.json | ADR-0002 + ADR-0008 | ✅ Covered (Accepted 2026-05-12) |
| TR-config-006 | Test-mode fallback returns safe defaults when config absent in editor | ADR-0002 | ✅ Covered (Accepted 2026-05-12) |

### Audio Manager (system: `audio`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-audio-001 | Autoload singleton accessible to TCB + future alert systems | ADR-0003 | ✅ Covered |
| TR-audio-002 | Bus topology: Master → Music + SFX | GDD self-sufficient | ⚠️ No ADR (acceptable) |
| TR-audio-003 | 8-node pre-instantiated AudioStreamPlayer pool, no runtime allocation | GDD self-sufficient | ⚠️ No ADR (acceptable) |
| TR-audio-004 | Audio Manager is stream-agnostic — caller owns lookup | GDD self-sufficient | ⚠️ No ADR (acceptable) |
| TR-audio-005 | Settings persist via ConfigLoader `setting_changed` signal subscription | ADR-0002 + ADR-0006 | ✅ Covered |
| TR-audio-006 | Web AudioContext requires user-gesture unlock | ADR-0003 (acknowledged) | ⚠️ Partial — needs ADR-0004 |

### TileMap Renderer (system: `tilemap`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-tilemap-001 | TileMapLayer wrapper, `CELL_SIZE=16`, `MODULE_SIZE=8` constants | — | ❌ GAP — needs ADR-0013 |
| TR-tilemap-002 | 4-layer structure (Floor/AlertOverlay/Wall/Overlay) with Y-sort on Wall | — | ❌ GAP — needs ADR-0013 (VERIFY-3) |
| TR-tilemap-003 | Single writer rule — no system touches TileMapLayer directly | architecture.md Principle #4 | ⚠️ Partial — needs ADR-0013 |
| TR-tilemap-004 | Room registry via `register_room(id, Rect2i)` | — | ❌ GAP — likely covered by ADR-0013 |

### Data Bridge (system: `data-bridge`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-data-bridge-001 | One HTTPRequest node per agent, pre-instantiated, never freed at runtime | ADR-0001 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-002 | Independent per-agent polling coroutines | ADR-0001 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-003 | Raw String payload — no JSON parsing at bridge layer | ADR-0001 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-004 | Bearer token auth per-agent (`Authorization: Bearer [token]`) | ADR-0001 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-005 | Backoff: grace(1) → STALE(2nd) → DISCONNECTED(4th), cap 30s, auto-heal | ADR-0001 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-006 | Mock mode swaps polling driver, identical signal interface, no HTTPRequest nodes | ADR-0008 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-007 | Mock data cycles `assets/data/mock/[agent_id].json` JSON array sequentially | ADR-0008 | ✅ Covered (Accepted 2026-05-12) |
| TR-data-bridge-008 | Web export CORS strategy (proxy / web-mock / PC-only) | — | ❌ GAP — needs ADR-0004 (VERIFY-4) |

### Agent State Machine (system: `asm`) — BLOCKED

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-asm-001 | ASM is sole emitter of `task_completed(agent_id: String)` | ADR-0005 | ✅ Covered (Accepted 2026-05-12) |
| TR-asm-002 | Agent state vocabulary (`idle/working/completed/errored`) | ADR-0007 | ✅ Covered (Accepted 2026-05-12 pm) |
| TR-asm-003 | Emits `agent_state_changed(agent_id: String, new_state, previous_state)` | ADR-0005 + ADR-0006 | ✅ Covered (Accepted 2026-05-12) |
| TR-asm-004 | Connection-quality reporting mechanism (HUD OQ-4) | ADR-0007 | ✅ Covered (Accepted 2026-05-12 pm) — orthogonality decision |
| TR-asm-005 | Parses Data Bridge raw payload into canonical state | ADR-0007 | ✅ Covered (Accepted 2026-05-12 pm) — derivation rule |
| TR-asm-006 | Per-agent stats dictionary exposed via `get_agent_stats(id)` | ADR-0007 | ✅ Covered (Accepted 2026-05-12 pm) — read-only API spec |

### Room System (system: `room`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-room-001 | Node2D in scene tree (not Autoload), `@export` ref pattern | ADR-0003 | ✅ Covered (Accepted 2026-05-12) |
| TR-room-002 | `COMMANDERS_ROOM_ID = &"commander"` constant + permanent room | GDD self-sufficient | ⚠️ No ADR needed |
| TR-room-003 | `RoomData` inner class with `bounds`, `agent_ids[]`, `workstation_tiles[]` | GDD self-sufficient | ⚠️ No ADR needed |
| TR-room-004 | Registers rooms with TileMap Renderer in `_ready()` | ADR-0003 (init order) | ✅ Covered (Accepted 2026-05-12) |
| TR-room-005 | `computer_interacted` signal forwarded from commander's computer Area2D | architecture.md | ⚠️ Partial — implicit in ADR-0006 |

### Agent Character Controller (system: `acc`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-acc-001 | Per-agent CharacterBody2D, one ACC per configured agent | ADR-0003 (init order) | ⚠️ Partial |
| TR-acc-002 | AnimationPlayer state driven by ASM state | — | ❌ GAP — needs ADR-0009 (VERIFY-6) |
| TR-acc-003 | Subscribes to `agent_state_changed` filtered by agent_id via `.bind()` | ADR-0006 | ✅ Covered (Accepted 2026-05-12) |
| TR-acc-004 | Pure consumer — no public signals (ADR-0005 boundary) | ADR-0005 | ✅ Covered (Accepted 2026-05-12) |
| TR-acc-005 | Navigation between desks within room | — | ❌ GAP |
| TR-acc-006 | `ERROR_TIMEOUT_SEC` + `STAGGER_BASE_SEC` + `COMPLETED_BEAT_DURATION_SEC` constants | — | ❌ GAP |
| TR-acc-007 | Sprite placement uses TileMap Renderer `cell_to_world` helpers | architecture.md Principle #4 | ⚠️ Partial |

### Ambient Animation Layer (system: `aal`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-aal-001 | Per-room ambient Node2D, one AAL per room | ADR-0003 (init order) | ⚠️ Partial |
| TR-aal-002 | Background ambient animations (AnimationPlayer) + Tween-driven | — | ❌ GAP — needs ADR-0009 + ADR-0010 |
| TR-aal-003 | Responds to ASM state for room-context-aware reactions | ADR-0006 | ✅ Covered (Accepted 2026-05-12) |
| TR-aal-004 | `TRANSITION_SEC = 0.3` constant | — | ❌ GAP |

### Task Completion Beat (system: `tcb`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-tcb-001 | Stateless one-shot subscriber to `task_completed` (sole emitter ASM) | ADR-0005 | ✅ Covered (Accepted 2026-05-12) |
| TR-tcb-002 | Resolves `AudioStream` from AgentSoundRegistry, calls `AudioManager.play_sfx()` | ADR-0006 + audio GDD | ✅ Covered |
| TR-tcb-003 | Emits `beat_fired(agent_id: String, timestamp: float)` signal | ADR-0006 (pattern) | ⚠️ Partial — needs explicit ADR or doc sync |
| TR-tcb-004 | Room modulate Tween (attack 0.3s + hold 0.5s + decay 0.7s = 1.5s total) | — | ❌ GAP — needs ADR-0010 |
| TR-tcb-005 | Tween kill-and-restart on rapid re-trigger (no compounding) | — | ❌ GAP — needs ADR-0010 (VERIFY-9) |
| TR-tcb-006 | Per-room independent Tweens, no bunker-wide pulse | — | ❌ GAP — needs ADR-0010 |
| TR-tcb-007 | AgentSoundRegistry preloaded at scene startup, `default.ogg` mandatory | GDD self-sufficient | ⚠️ No ADR |
| TR-tcb-008 | Room node resolution via Room System (Provisional — interface TBD) | — | ❌ GAP — needs Room System API extension |

### Commander's Room HUD (system: `hud`)

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-hud-001 | Screen-edge CanvasLayer panel + screen-space detail overlay | — | ❌ GAP — needs ADR-0011 |
| TR-hud-002 | 3×4 slot grid state synchronised with ASM | ADR-0006 | ⚠️ Partial — visual contract needs ADR-0011 |
| TR-hud-003 | Completions strip cap 6 entries | — | ❌ GAP |
| TR-hud-004 | Per-slot timers (1.5s) for `+` glyph after `beat_fired` | — | ❌ GAP |
| TR-hud-005 | `tasks_completed` per-agent accumulator | — | ❌ GAP |
| TR-hud-006 | Subscribes to ASM (state + connection) + TCB (beat_fired) + Room System (computer_interacted) | ADR-0006 | ✅ Covered (Accepted 2026-05-12) |
| TR-hud-007 | Connection-quality alpha overlay (CONNECTED=1.0, STALE=0.5, DISCONNECTED=0.25) | — | ❌ GAP — needs ADR-0007 + ADR-0011 |
| TR-hud-008 | BitmapFont 5×7 px rendering via FontFile | — | ❌ GAP — needs ADR-0012 (VERIFY-2, VERIFY-5) |
| TR-hud-009 | `keep_integer` stretch mode required for pixel-perfect HUD | architecture.md Principle #4 | ⚠️ Partial — needs ADR-0013 (VERIFY-1) |
| TR-hud-010 | Detail overlay non-modal, status panel `mouse_filter = MOUSE_FILTER_IGNORE` | — | ❌ GAP |
| TR-hud-011 | Sync pass via `ASM.get_agent_state()` per agent at startup (EC-6) | ADR-0006 (Tier 2) | ✅ Covered (Accepted 2026-05-12) |
| TR-hud-012 | Computer prop signal originates from Room System, not HUD | architecture.md | ⚠️ Partial — needs explicit ADR or doc sync |

### Cross-cutting

| TR-ID | Requirement | ADR | Status |
|---|---|---|---|
| TR-xc-001 | All cross-module communication uses typed Godot signals | ADR-0006 | ✅ Covered (Accepted 2026-05-12) |
| TR-xc-002 | Mock-mode strategy is invisible to all consumers | ADR-0008 | ✅ Covered (Accepted 2026-05-12) |
| TR-xc-003 | GUT test framework + GitHub Actions CI | ADR-0014 | ✅ Covered (Accepted 2026-05-12) |
| TR-xc-004 | Only ConfigLoader + AudioManager are Autoloads | ADR-0003 | ✅ Covered (Accepted 2026-05-12) |
| TR-xc-005 | Architecture principle: no hardcoded numbers — all tuning via Configuration Loader or `entities.yaml` | architecture.md Principle #3 | ⚠️ Partial — recommend ADR documenting this rule |

---

## Known Gaps (priority order)

| # | TR-ID | System | Suggested ADR | Engine Risk |
|---|---|---|---|---|
| 1 | TR-tcb-004 to 006 | TCB | **ADR-0010 Tween Lifecycle** | HIGH (VERIFY-9) |
| 2 | TR-data-bridge-008, TR-audio-006 | Data Bridge + Audio | **ADR-0004 Web Export Compatibility** | HIGH (VERIFY-4) |
| 3 | TR-tilemap-001 to 004, TR-hud-009 | TileMap + HUD | **ADR-0013 Stretch Mode + Pixel-Perfect** | MEDIUM (VERIFY-1, VERIFY-3) |
| 4 | TR-hud-001 to 005, 007, 010 | HUD | **ADR-0011 HUD Rendering Strategy** | HIGH |
| 5 | TR-hud-008 | HUD | **ADR-0012 BitmapFont/FontFile Strategy** | HIGH (VERIFY-2, VERIFY-5) |
| 6 | TR-acc-002, TR-aal-002 | ACC + AAL | **ADR-0009 AnimationPlayer Strategy** | MEDIUM (VERIFY-6) |
| 7 | TR-asm-002 to 006 | ASM | **ADR-0007 Agent State Vocabulary** | LOW — but BLOCKED on Data Bridge prototype |

## Superseded Requirements

None at this time. The TR registry has no prior version to supersede.

## History

| Date | Coverage % | Notes |
|---|---|---|
| 2026-05-11 | ~43% (Proposed) | Initial registry creation. 7 ADRs Proposed, 7 missing, 4 cross-doc conflicts identified. |
| 2026-05-11 (late) | ~43% (Proposed) | 4 cross-doc conflicts resolved; 4 Foundation ADRs flipped to Accepted (0003, 0014, 0002, 0006); ADR-0010 authored. |
| 2026-05-12 | ~93% (Accepted) | 5 new ADRs authored (0004, 0009, 0011, 0012, 0013) + 9 ADRs flipped Proposed → Accepted. Only gap is ADR-0007 (BLOCKED — correct). All HIGH-risk engine domains now have Accepted ADR coverage. |
| 2026-05-12 pm | **100% (Accepted)** | Sprint 1 Data Bridge prototype against real Anthropic API (`claude-haiku-4-5-20251001`) harvested 11 successful payloads. ADR-0007 Agent State Vocabulary authored + Accepted from empirical findings. 4 TRs unblocked (TR-asm-002, 004, 005, 006). All 14 ADRs now in final state. Last architectural block in Pre-Production critical path is closed. |
