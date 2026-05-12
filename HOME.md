# The Situation Room — Project Home

> **For Claude**: Read this file first every session. It replaces reading `active.md` + `systems-index.md` separately. Follow links only when you need detail on a specific system.

---

## What This Is

A real-time AI agent dashboard disguised as a top-down pixel-art underground bunker. A personal developer tool — not a game. The user monitors their AI agent team through animated characters in rooms. No combat, no economy, no skill trees.

**One-line pitch**: *A Fallout settlement that runs your AI agents.*

---

## Stack

| Field | Value |
|-------|-------|
| Engine | Godot 4.6.2 / GDScript |
| Renderer | 2D CanvasItem |
| Physics | Jolt (default in 4.6) |
| Targets | PC (Win/Mac/Linux) + Web (HTML5) |
| Input | Keyboard/Mouse |

---

## Phase: Pre-Production — GDD Authoring

**Progress**: 9 / 10 MVP systems designed (10th blocked — Agent State Machine awaiting Data Bridge prototype)

| # | System | Layer | Status | Doc |
|---|--------|-------|--------|-----|
| 1 | Configuration Loader | Foundation | ✅ Designed | [[configuration-loader]] |
| 2 | Audio Manager | Foundation | ✅ Designed | [[audio-manager]] |
| 3 | TileMap Renderer | Foundation | ✅ Designed | [[tilemap-renderer]] |
| 4 | Data Bridge | Core | ✅ Designed* | [[data-bridge]] |
| 5 | Room System | Core | ✅ Designed | [[room-system]] |
| 6 | Agent State Machine | Core | 🔴 Blocked | — |
| 7 | Agent Character Controller | Feature | ✅ Designed | [[agent-character-controller]] |
| 8 | Ambient Animation Layer | Feature | ✅ Designed | [[ambient-animation-layer]] |
| 9 | Task Completion Beat | Feature | ✅ Designed* | [[task-completion-beat]] |
| 10 | Commander's Room HUD | Presentation | ✅ Designed* | [[commanders-room-hud]] |

*Data Bridge GDD has 4 prototype-gated ACs (18–21). Full Approved status requires prototype. Agent State Machine (6) is blocked until prototype Qs 4+5 answered. Commander's Room HUD has provisional ASM interface (OQ-1).

**Pending reviews** (run in fresh sessions):
- `/design-review design/gdd/configuration-loader.md`
- `/design-review design/gdd/audio-manager.md`
- `/design-review design/gdd/tilemap-renderer.md`
- `/design-review design/gdd/data-bridge.md`
- `/design-review design/gdd/room-system.md`
- `/design-review design/gdd/agent-character-controller.md`
- `/design-review design/gdd/ambient-animation-layer.md`
- `/design-review design/gdd/task-completion-beat.md`
- `/design-review design/gdd/commanders-room-hud.md`

**All 10 MVP GDDs designed** (9 complete, 1 blocked — Agent State Machine awaiting Data Bridge prototype).

**Next step**: `/gate-check pre-production` — all 10 MVP GDDs are complete. Or run the Data Bridge prototype first to unblock Agent State Machine (#6) before the gate check.

**Gate**: `/gate-check pre-production` — ready to run

---

## Locked Decisions

**Visual identity**
- Aesthetic: "Institutional Underground" — cozy bunker, pixel art, retro-professional
- Art style: 16–32px sprites, 8-color palette, 8×8px tiles / 16×16px TileSet cells
- Font: Bitmap 5×7px
- Colors: Amber `#D4882A` (idle) · Green `#4A9A52` (active) · Sienna `#A03520` (alert)
- HUD vocabulary: Three glyphs only — ● / ▬ / +

**Architecture**
- Autoload singletons for Foundation systems (Configuration Loader, Audio Manager)
- Config schema: `config.json` at executable directory; agents array, poll_interval_sec, protocol
- Audio: Master → Music bus (−18 dB) + SFX bus (−12 dB); 8-node pool; no ducking
- Agents-to-sound mapping: caller's responsibility — Audio Manager is stream-agnostic
- Mute: two-tier (global M-key toggle + per-bus); persists to `user://settings.json`
- Max agents: 12 (`max_agents` constant, owned by configuration-loader.md)
- TileMapLayer (not TileMap — changed in Godot 4.3)

**Scope**
- MVP: 1 room, 1 agent, 1 live data source, 1 completion beat
- Data Bridge prototype must ship BEFORE any art production begins
- No crossfade, no adaptive music, no alert repeat — all post-MVP

---

## Five Pillars

1. **Alive by Default** — bunker breathes without user interaction
2. **Readable at a Glance** — state communicated through animation, not text
3. **Satisfying Feedback** — every event has a visual + audio beat
4. **Commander Always Home** — user's room always visible
5. **Earn Each Room** — rooms unlock only when an agent exists to fill them

---

## Active Risks

| Risk | Level | Mitigation |
|------|-------|------------|
| Data Bridge (real API connectivity) | 🔴 HIGH | Prototype BEFORE art production. GDD includes prototype plan. |
| Agent State Machine model accuracy | 🟡 MEDIUM | Design AFTER Data Bridge prototype reveals actual API output. |
| Agent Character Controller legibility | 🟡 MEDIUM | Visual prototype with placeholder art before full art production. |

---

## Key Files

| File | Purpose |
|------|---------|
| [[game-concept]] | Full project concept + pillars |
| [[systems-index]] | All 16 systems, dependency map, design order |
| [[art-bible]] | Complete visual identity (9 sections) |
| `docs/engine-reference/godot/VERSION.md` | Godot 4.6.2 API reference |
| `.claude/docs/technical-preferences.md` | Naming conventions, performance budgets |
| `production/review-mode.txt` | `lean` (directors at phase gates only) |

---

## Verify Before Shipping (Godot 4.4–4.6 specifics)

1. `keep_integer` stretch mode path in Godot 4.6.2 Project Settings
2. `BitmapFont` class — deprecated or still first-class in 4.6?
3. `TileMapLayer` Y-sort behavior (`y_sort_enabled`) in 4.6.2
4. Web export texture compression option location in 4.6 Export Presets
5. BMFont `.fnt` import via `FontFile` — unchanged from 4.3?
6. `AnimationMixer`/`AnimationPlayer` API — `active` property confirms unchanged
7. `HTTPRequest.request_completed` signal signature — confirm unchanged from pre-4.4 docs (expected: `result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray`)
8. `HTTPRequest.timeout` — confirm clean cancellation behavior in Godot 4.6.2
9. `Tween` on freed node — confirm Godot 4.6.2 cleans up cleanly when a Tween's target Node2D is freed mid-animation (Task Completion Beat: room modulate Tween)

---

*Last updated: 2026-05-11 — Commander's Room HUD GDD complete (9/10 MVP, 10th blocked). All MVP GDDs designed. Gate check ready.*
