# Session State — The Situation Room

*Last updated: 2026-05-12 (late pm — post-ASM-GDD)*

## Current Status

**Phase**: Pre-Production — **DESIGN COMPLETE**, ready for implementation
- **10 / 10 MVP GDDs designed** (last one — ASM — landed today as commit `d88cd01`)
- **14 / 14 ADRs Accepted** (final state; ADR-0007 closed today via Sprint 1 prototype)
- **60 / 60 TRs covered** (100% via traceability index v2026-05-12 pm)
- **Control manifest v2026-05-12.2** active
- **Pre-Production gate**: PASS (`production/gate-checks/2026-05-12-pre-production.md`)
- **Sprint 1**: CLOSED with retro (`production/retros/sprint-1.md`); Data Bridge prototype validated against real Anthropic API
- **Cross-GDD review in flight**: `design/reviews/gdd-cross-review-2026-05-12.md` (Opus-tier agent running)
- **Architectural blocks**: 0
- **11 commits on `main`** queued for push (local only)

**Last completed task**: Authored `design/gdd/agent-state-machine.md` (GDD #6, the 10th and last MVP GDD) in a single session via 12 AskUserQuestion-panel-driven design decisions. All 8 required sections complete; 33 acceptance criteria pinned; ASM-specific TRs (TR-asm-002, 004, 005, 006) now have a referenced GDD on top of ADR-0007 coverage.

---

## Session 2026-05-12 chronicle (chronological)

Today's session broke the multi-session treadmill described in the prior session-extract sections (below this one). Achievements:

1. **Architecture finalization inline** (rather than session-rotation through `/architecture-review` + `/gate-check`) — 13 ADRs Accepted, all HIGH-risk engine domains covered.
2. **Test scaffolding** + accessibility + UX patterns docs created to close 2026-05-11 gate-check blockers.
3. **godot-specialist VERIFY-10..20 sweep** integrated as ADR amendments (Manifest v2026-05-12.1).
4. **WCAG palette shift** propagated (S2 `#4A9A52` → `#5BAD63`; 3.65:1 contrast PASS).
5. **Sprint 1 prototype** built (Godot project + ConfigLoader + Data Bridge + UI), Godot 4.3 installed locally, prototype run against live Claude API (`claude-haiku-4-5-20251001`), 11 successful payloads captured.
6. **ADR-0007 Agent State Vocabulary** authored + Accepted from empirical findings.
7. **ADR-0001 Amendment 2026-05-12.b** added: 4xx vs 5xx differentiation + `request_dispatched`/`request_settled` signals required for `working` state visibility.
8. **Sprint 1 retro** written; risk register reconciled (0 of 10 risks realized).
9. **ASM GDD (GDD #6)** authored section-by-section via panel-driven decisions; 12 decisions resolved.
10. **Manifest v2026-05-12.2** with new ASM layer rules.

## Commits this session (11, all on `main`, local-only)

```
d88cd01 docs(design): Agent State Machine GDD complete — 10th and last MVP GDD
fce5037 docs: Sprint 1 retro + ADR-0001 amendments + ASM GDD skeleton
b7fe393 feat(arch): ADR-0007 Agent State Vocabulary Accepted — Sprint 1 DoD met
ca0ae7d docs: propagate S2 Active Green palette shift #4A9A52 → #5BAD63
6691825 fix(prototype): correct main.gd node paths + add run.bat launcher
3801c15 docs(arch): integrate VERIFY-10..20 sweep findings — manifest v2026-05-12.1
45633f6 feat(prototype): Sprint 1 Data Bridge scaffold — runnable in mock mode
c113636 docs: WCAG verdict + control manifest + Sprint 1 charter + risk register
314c3b6 docs(design): land prior-session GDDs + art bible + config + ACC prototype
1325daa docs(arch): finalize 13 ADRs + pre-production gate PASS + test/UX scaffolding
ce1b01c (already on main — predecessor) docs(arch): remediate cross-doc conflicts...
```

## Next recommended actions (post-session)

1. Cross-GDD review (in flight; finishes soon) → fix any blocking issues surfaced
2. Push 11 commits to remote (`git push origin main`)
3. Sprint 2 candidates per `production/retros/sprint-1.md`:
   - ConfigurationLoader implementation (clean foundation autoload)
   - AudioManager implementation (similar)
   - Asset procurement: `pixel_5x7.ttf` (ADR-0012), `agent_default.tres` AnimationLibrary (ADR-0009), `silence_50ms.ogg` (ADR-0004 A1)
4. ADR-0002 amendment recommended (per Sprint 1 retro): ConfigLoader validates `model` field against `/v1/models` at startup

## Previous session extracts (chronological history)

The sections below preserve session-by-session history from the multi-session pre-treadmill era. Useful for audit trail; not authoritative for current state (see top of this file).

---

## (historical) Session Extract pre-2026-05-12

**ADRs written this session (2026-05-12):**

- **ADR-0004 Web Export Compatibility** — Web build is MVP-supported as demo-only with `mock: true` forced via ConfigurationLoader override when `OS.has_feature("web")`. AudioContext unlock via one-shot `_input()` handler in AudioManager. Custom HTML shell (`web/shell.html`) required. Export preset settings pinned. **Closes VERIFY-4 + TR-data-bridge-008 + TR-audio-006. Opens VERIFY-10/11/12.**
- **ADR-0013 Stretch Mode + Pixel-Perfect** — Base resolution **480×270**. Stretch mode `viewport` / aspect `keep` / `scale_mode = "integer"` (NOT `keep_integer` — that mode was unified in 4.4). Y-sort on Wall layer + parent Node2D only. `CELL_SIZE=16`, `MODULE_SIZE=8` pinned as code constants. Camera2D.zoom locked at 1×. **Closes VERIFY-1 + VERIFY-3 + TR-tilemap-001..004 + TR-hud-009. Opens VERIFY-13/14.**
- **ADR-0011 HUD Rendering Strategy** — Two CanvasLayers: `HudLayer` (layer=10, status panel + 3×4 slot grid + completions strip) + `OverlayLayer` (layer=20, detail overlay). HUD root `process_mode = PROCESS_MODE_ALWAYS`. **Inverted mouse_filter** default (IGNORE) with 14 explicit STOP overrides. Connection-quality alpha via `modulate.a` per slot, not separate overlay. **User-requested**: Tab toggles both CanvasLayers' visibility, persisted via `ConfigurationLoader.set_setting(&"hud_visible", bool)`. **Closes TR-hud-001/002/003/004/005/007/010. Opens VERIFY-15/16. Adds `toggle_hud` input action.**
- **ADR-0012 BitmapFont / FontFile Strategy** — `FontFile` resource with **TTF source** (NOT BMFont `.fnt`) at `fixed_size=7`, `antialiasing=NONE`, `subpixel_positioning=DISABLED`, `hinting=NONE`, `fixed_size_scale_mode=INTEGER_ONLY`. Single canonical font (`pixel_font_5x7.tres`) via project-wide Theme (`pixel.tres`). One font size for MVP. **Closes VERIFY-2 + VERIFY-5 + TR-hud-008. Opens VERIFY-17/18. Blocks-on-asset: TTF source procurement.**
- **ADR-0009 AnimationPlayer Strategy** — Per-agent + per-room `AnimationPlayer` with shared `AnimationLibrary` resource (`agent_default.tres`, per-agent-type variants `agent_<type>.tres`). ASM state → animation via Tier 2 signal subscription with `.bind(agent_id)`. Loop policies pinned per state (`idle/working/errored` LOOP_LINEAR, `completed` LOOP_NONE). `AnimationMixer.active=true` explicit at `_ready()`. **Codifies Tween/AnimationPlayer boundary alongside ADR-0010** (state→AnimationPlayer; event→Tween). **Closes VERIFY-6 + TR-acc-002 + TR-aal-002. Opens VERIFY-19/20.**

**Session opened 8 new VERIFY items (VERIFY-10..20) and closed 7 (VERIFY-1/2/3/4/5/6 + reconfirmed VERIFY-9). VERIFY-7/8 (HTTPRequest behaviour) remain open. ADR-0007 remains correctly BLOCKED on Data Bridge prototype Qs 4-5.**

**Critical handoff note**: This session ran `/architecture-decision` 5 times. Per skill rule, `/architecture-review` and the ADR Proposed→Accepted flips must happen in a **fresh session**. Do NOT run `/architecture-review` in the next turn of this session.

---

## Session Extract — Inline Review + Gate + Scaffolding (2026-05-12, late)

User pushed back on the new-session treadmill ("we have done new session, architecture review and gate check like 4 times now"). Skill-isolation rule was set aside; all remaining work executed inline.

**Work completed in this session, post-pushback:**

1. **Architecture review (manual, not skill)** — `docs/architecture/architecture-review-2026-05-12.md`. Verdict: **PASS**. All 8 blocking issues from 2026-05-11 review resolved. TR coverage: ~43% → ~93%. 0 new cross-ADR conflicts detected. 6 VERIFY closed (1, 2, 3, 4, 5, 6). 11 new VERIFY opened (10–20).
2. **ADR flips** — 9 ADRs flipped from Proposed → **Accepted (2026-05-12)**: 0001, 0004, 0005, 0008, 0009, 0010, 0011, 0012, 0013. Result: **13 of 14 ADRs Accepted; ADR-0007 still NOT WRITTEN (correctly BLOCKED on Data Bridge prototype).**
3. **Test framework scaffolded** — `tests/unit/example_test.gd` (3 smoke assertions), `tests/integration/.gitkeep`, `tests/README.md` (GUT install + usage), `.github/workflows/tests.yml` (GUT CI workflow per ADR-0014; uses chickensoft-games/setup-godot@v2). GUT addon itself still needs install (documented).
4. **UX/Accessibility docs** — `design/ux/accessibility-requirements.md` (WCAG 2.1 AA baseline + reduced motion + keyboard alternatives + carry-forward of S2/W2 contrast check). `design/ux/interaction-patterns.md` (8 patterns + explicit "NOT in this library" list).
5. **Traceability index updated** — `docs/architecture/traceability-index.md` now reflects 93% coverage + Accepted status + 2026-05-12 history entry.
6. **Pre-production gate-check** — `production/gate-checks/2026-05-12-pre-production.md`. Verdict: **PASS** (with 2 CONCERNS tracked: WCAG contrast verification + godot-specialist VERIFY-10..20 sweep). All 13 required artifacts present. 8/9 quality checks pass. Supersedes the 2026-05-11 FAIL.

**Stage transition**: Pre-Production is now **OPEN**. The 2026-05-11 FAIL gate is officially closed.

**Recommended first Pre-Production actions** (in order):
1. Control manifest extraction (`docs/architecture/control-manifest.md`) — mechanical from 13 Accepted ADRs
2. Sprint 1 charter — Data Bridge prototype focus (highest risk; unblocks ADR-0007)
3. WCAG contrast check (S2 #4A9A52 over W2 #4A4035) — 30 min, art-director
4. godot-specialist VERIFY-10..20 consultation sweep
5. Data Bridge prototype execution → unblocks ADR-0007 → ASM GDD → ACC + AAL implementation

**Asset procurement workstream (parallel)**:
- `pixel_5x7.ttf` (ADR-0012 blocks-on-asset)
- `agent_default.tres` AnimationLibrary (ADR-0009 blocks-on-asset)

**Nothing committed.** Working tree has many modified + new files ready for review. User chooses what lands.

---

## Session Extract — Multi-Commit Cleanup + Sprint 1 Begin + VERIFY Sweep (2026-05-12, late)

After completing the inline architecture review + gate-check, user instructed to commit. 5 commits landed atomically:

1. **`ce1b01c`** (prior session) `docs(arch): remediate cross-doc conflicts, accept Foundation ADRs, add ADR-0010`
2. **`1325daa`** `docs(arch): finalize 13 ADRs + pre-production gate PASS + test/UX scaffolding` (5 new ADRs, 9 status flips, architecture-review report, traceability index, tests/ scaffold, .github/workflows/tests.yml, design/ux/*, gate-check)
3. **`314c3b6`** `docs(design): land prior-session GDDs + art bible + config + ACC prototype` (HOME.md, 7 GDDs, art-bible.md, design/registry/entities.yaml updates, CLAUDE.md / .claude/docs / VERSION.md tweaks, prototypes/acc-legibility)
4. **`c113636`** `docs: WCAG verdict + control manifest + Sprint 1 charter + risk register` (WCAG verified S2 #4A9A52 → #5BAD63; control-manifest.md v2026-05-12; sprint-1.md charter; risk-register with 5 OPEN + 5 carry-forward; .gitignore cleanup)
5. **`45633f6`** `feat(prototype): Sprint 1 Data Bridge scaffold — runnable in mock mode` (full Godot 4.6.2 prototype project at prototypes/data-bridge/: ConfigurationLoader, DataBridge per ADR-0001, AgentStatusLabel, Main scene, mock cycle, real-API hookup, findings.md skeleton)

**Sprint 1 Day 1 work complete on the scaffold side.** User now runs the prototype to harvest Q1-Q6 findings → ADR-0007.

### godot-specialist VERIFY sweep (background agent, 2 min 47 sec)
- Report: `docs/architecture/verify-sweep-2026-05-12.md`
- Result: **6 PASS / 5 CONCERN / 0 FAIL** across VERIFY-10..20
- ADR amendments applied (control manifest v2026-05-12.1):
  - **ADR-0004 A1**: AudioContext unlock primary path upgraded from no-op `set_bus_volume_db` (undocumented engine behaviour) to `AudioStreamPlayer.play()` on a silent 50ms OGG stream (guaranteed cross-browser activation). New asset required: `res://assets/audio/silence_50ms.ogg` (~1KB).
  - **ADR-0004 A2**: Safari non-integer browser zoom limitation documented; canonical smoke zoom = 100% / 200%.
  - **ADR-0011 A1**: New forbidden pattern `recursive_mouse_filter_ignore_on_hud_ancestor` — must not enable 4.5+ opt-in recursive IGNORE on HUD ancestors.
  - **ADR-0011 A2**: World nodes must not handle Tab in `_input()` (must use `_unhandled_input()` or action-mapped checks) so HUD toggle can suppress first.
  - **ADR-0013 A1**: Retina smoke test list expanded (2560×1600 MacBook Pro 13", 2880×1800 MacBook Pro 15"/16", 3024×1964 MacBook Pro 14" M-series).
- Top 3 smoke tests still required before code ships:
  1. VERIFY-12 (HIGHEST) — Web AudioContext on Chrome + Firefox + Safari with the new silent-stream pattern
  2. VERIFY-17 — `FIXED_SIZE_SCALE_INTEGER_ONLY` at ×8 (3840×2160)
  3. VERIFY-20 — `animation_finished` signal timing under `AnimationMixer` base class
- Control manifest version bumped to **2026-05-12.1**; VERIFY ledger table updated with verdicts.

### Status now
- 13 ADRs Accepted (5 of them with 2026-05-12.1 amendments)
- Pre-Production OPEN
- Sprint 1 scaffold ready; user-driven prototype run pending
- Asset gap: need to source `silence_50ms.ogg` (trivial ffmpeg) before first web build attempt; `pixel_5x7.ttf` (TTF source for ADR-0012); `agent_default.tres` AnimationLibrary (ADR-0009)

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

1. ~~`keep_integer` stretch mode path in Godot 4.6.2 Project Settings~~ — **CLOSED 2026-05-12 by ADR-0013.** Use `mode=viewport` + `aspect=keep` + `scale_mode=integer` (the 4.4+ replacement for the legacy `keep_integer` mode).
2. ~~`BitmapFont` class status — deprecated or still first-class in 4.6?~~ — **CLOSED 2026-05-12 by ADR-0012.** Folded into `FontFile` in Godot 4. Use TTF-via-FontFile with locked properties.
3. ~~`TileMapLayer` Y-sort behavior~~ — **CLOSED 2026-05-12 by ADR-0013.** Parent Node2D must have `y_sort_enabled=true` AND the TileMapLayer must have `y_sort_enabled=true`. Both required.
4. ~~Web export texture compression option location~~ — **CLOSED 2026-05-12 by ADR-0004.** `Project → Export → Web → Variant` tab; `vram_texture_compression/for_desktop=false`, `for_mobile=true`.
5. ~~BMFont `.fnt` import via `FontFile`~~ — **CLOSED 2026-05-12 by ADR-0012.** Still works in 4.6.2 (FontFile detects format) but we use TTF instead.
6. ~~`AnimationMixer`/`AnimationPlayer` API~~ — **CLOSED 2026-05-12 by ADR-0009.** AnimationPlayer inherits AnimationMixer in 4.4+; `active` property is on the base class, default true. Explicit at `_ready()` per ADR.
7. `HTTPRequest.request_completed` signal signature — confirm unchanged in 4.4–4.6 (OPEN — Data Bridge prototype)
8. `HTTPRequest.timeout` — confirm clean cancellation behavior in 4.6.2 (OPEN — Data Bridge prototype)
9. ~~`Tween` on freed node reference~~ — **CLOSED 2026-05-11 by ADR-0010.** `bind_node(target)` is the documented mitigation.
10. (ADR-0004) Confirm `JavaScriptBridge` singleton is available in 4.6.2 web export
11. (ADR-0004) Confirm `OS.has_feature("web")` is true at `_ready()` time in a 4.6.2 HTML5 build
12. (ADR-0004) Confirm AudioServer activity alone resumes the Web AudioContext on first user gesture in Chrome + Firefox + Safari
13. (ADR-0013) Confirm HiDPI handling on Mac Retina at 480×270 base — does `window/dpi/allow_hidpi=true` produce crisp ×N scaling?
14. (ADR-0013) Confirm web canvas behaviour at non-integer browser zoom — does `image-rendering: pixelated` in the shell hold up?
15. (ADR-0011) Confirm `MOUSE_FILTER_IGNORE` parent allows STOP child to receive clicks in 4.6.2
16. (ADR-0011) Confirm `set_input_as_handled()` in `_unhandled_input` prevents world from receiving the Tab keypress
17. (ADR-0012) Confirm `FIXED_SIZE_SCALE_INTEGER_ONLY` produces zero anti-aliasing at integer multiples in 4.6.2
18. (ADR-0012) Confirm Theme `default_font` propagation to nested Control subtrees
19. (ADR-0009) Confirm `AnimationLibrary` assignment via `add_animation_library(&"", library)` is the canonical 4.6.2 default-library path
20. (ADR-0009) Confirm `animation_finished` signal fires exactly once for a one-shot `LOOP_NONE` animation at end-of-track

## Biggest Risk

**Data bridge prototype**: The Data Bridge GDD is written but 4 ACs are prototype-gated. The prototype must answer 6 specific questions (see data-bridge.md Section C — Prototype Plan) before Agent State Machine GDD can be designed. Run the prototype as early as possible — BEFORE any art production begins.

## Recommended Next Step

**MUST be a FRESH session** (skill rule: `/architecture-review` cannot run in the same session as `/architecture-decision`).

1. **`/architecture-review`** — re-run against the 13 written ADRs. Expected verdict: PASS or CONCERNS-non-blocking (all HIGH gaps now covered; only outstanding gap is ADR-0007 which is correctly BLOCKED). Will produce updated traceability index showing TR coverage jumping from ~43% (Proposed) to ~98% (with the 5 new ADRs).
2. **After review passes**, flip 9 Proposed ADRs to **Accepted**: 0001, 0004, 0005, 0008, 0009, 0010, 0011, 0012, 0013. (ADR-0007 stays BLOCKED.)
3. **Then `/gate-check pre-production`** — should now PASS the previous 2026-05-11 FAIL (which was blocked on all-ADRs-Proposed + missing HIGH-risk ADRs).

Parallel paths once gate passes:
- **Data Bridge prototype** — unblocks ADR-0007 (Agent State Vocabulary) and GDD #6 (Agent State Machine)
- **Asset procurement** — TTF source for `pixel_5x7.ttf` (ADR-0012 blocks-on-asset); AnimationLibrary `.tres` for `agent_default` (ADR-0009 blocks-on-asset)
- **`/design-system agent-character-controller`** — GDD #7 already designed; needs review

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
