# Control Manifest — The Situation Room

**Manifest Version**: 2026-05-12.3
**Engine**: Godot 4.6.2
**Source**: 14 Accepted ADRs (0001–0014) + amendments per `verify-sweep-2026-05-12.md` + Sprint 1 ADR-0007 finalisation + Cross-GDD review reconciliation
**Status**: Active

**Version log**:
- `2026-05-12` — initial extraction from 13 Accepted ADRs
- `2026-05-12.1` — post-engine-verify-sweep amendments: AudioContext unlock pattern upgraded (ADR-0004 A1); HUD recursive-IGNORE guardrail (ADR-0011 A1); world Tab-handler restriction (ADR-0011 A2); Retina smoke-test list expanded (ADR-0013 A1); VERIFY ledger updated with sweep verdicts
- `2026-05-12.2` — **ADR-0007 Agent State Vocabulary** authored + Accepted after Sprint 1 Data Bridge prototype against real Anthropic API. All 14 architectural ADRs now in final state. New Agent State Machine layer added below.
- `2026-05-12.3` — Cross-GDD review (`design/reviews/gdd-cross-review-2026-05-12.md`) reconciled. Five Feature/Presentation/Foundation GDDs updated to ASM's locked contract (ACC/AAL/HUD/TCB/Room): StringName→String for agent_id, 3-arg agent_state_changed, ACC drops task_completed emission claim, Room System API alignment, computer_interacted signal documented. Data Bridge GDD amended with B1-B5 (request_dispatched/settled, 4xx-fatal, agent_poll_failed removed). ConfigLoader public API extended with `get_setting`/`set_setting` for arbitrary keys + `entities.yaml` ingestion. ASM ACs tightened (AC-12 ±50ms, AC-26 ConfigLoader reference, AC-29 two-part check, AC-30 corruption-mode enumeration).

> **For programmers**: This is your flat rules sheet. Required / Forbidden / Guardrails per layer. Extracted mechanically from Accepted ADRs. Where you need the **why**, read the ADR. Where you need the **what**, this manifest is enough.
>
> **For stories**: Every story embeds `Manifest Version: 2026-05-12`. If the manifest version on disk differs from the version in the story, `/story-done` flags staleness — re-read this file and reconcile.

---

## Universal rules (apply across all layers)

### Required
- All `.gd` files use static typing (`var x: int`, `func foo() -> void`). No untyped variables in shipping code.
- All cross-system communication via **typed Godot signals** (ADR-0006). Direct method calls only within a single system.
- All tuning values come from `ConfigurationLoader` or `design/registry/entities.yaml` — no hardcoded magic numbers (ADR-0002, ADR-0013).
- All file extensions follow `.claude/docs/technical-preferences.md`:
  - Game code: `.gd` → routed through godot-gdscript-specialist
  - Shaders: `.gdshader` → godot-shader-specialist
  - Scenes: `.tscn`, `.tres` → godot-specialist
- Engine version stamp Godot 4.6.2; cross-reference `docs/engine-reference/godot/` before using any post-cutoff API.

### Forbidden
- `direct_cross_system_state_write` — writing a property owned by another system (ADR-0006). Exception: presentation-property carve-out from ADR-0010 (see Animation layer below).
- `new_autoload_without_adr` — adding any Autoload not in ADR-0003's approved list (ConfigurationLoader + AudioManager are the only two).
- `process_polling_for_state` — `_process()` polling for state changes (ADR-0006). Use signal subscription instead.
- `scene_tree_discovery` — `get_tree().get_root().find_node(...)` for cross-system lookups (ADR-0006). Use injected references or signals.
- Hardcoded numbers in game logic — see Universal Required above.

### Guardrails
- Every public method has a doc comment (per `.claude/docs/coding-standards.md`).
- Every new system requires an ADR before implementation begins.
- Commits reference the relevant story ID and/or ADR.

---

## Configuration / Persistence layer

### Required (ADR-0002, ADR-0003, ADR-0004; extended 2026-05-12.3 per C-9 of cross-GDD review)
- ConfigurationLoader is an Autoload (ADR-0003).
- ConfigurationLoader parses `config.json` per-platform path resolution (PC/macOS/web/editor).
- ConfigurationLoader also ingests `res://design/registry/entities.yaml` at bootstrap (read-only, design-time tuning constants).
- `user://settings.json` is the persistent runtime mutation surface; written via `set_setting(key, value)` which emits `setting_changed(key, value)`.
- **Arbitrary-key access**: `get_setting(key: String, default: Variant) -> Variant` reads from `user://settings.json` first, then `entities.yaml`, then returns `default`. `set_setting(key, value)` always writes to `user://settings.json`. Keys are dotted strings (e.g. `asm.completed_decay_sec`, `asm_stats_<agent_id>`, `audio.master_volume_db`).
- Schema versioning: `schema_version: int` field present; mismatch → CONFIG_INVALID state.
- Corrupt persisted blob handling: callers are responsible for type-checking the returned value and falling back to default + `push_warning` if shape is wrong (per ASM §5 E-14 pattern).
- Test-mode fallback returns safe defaults when config absent (editor only).
- **Web override (ADR-0004)**: after parsing `config.json`, if `OS.has_feature("web")` and `not _config.get("mock", false)`, force `_config["mock"] = true` and set `_config["web_mock_forced"] = true`. Emit `push_warning`.

### Forbidden
- Any post-parse mutation of `_config` **except** the ADR-0004 web override.
- Consumers calling `set_setting` for non-`user://settings.json` keys (no other persistence surfaces).

---

## Data Bridge layer

### Required (ADR-0001, ADR-0004, ADR-0008)
- One `HTTPRequest` node per agent (max 12), pre-instantiated, never freed at runtime.
- Independent per-agent polling coroutines.
- Raw `String` payload — no JSON parsing at the bridge layer.
- Bearer token auth per-agent: `Authorization: Bearer [token]`.
- Backoff per ADR-0001: grace(1 failure) → STALE(2nd) → DISCONNECTED(4th), cap 30s, auto-heal on recovery.
- Signals emitted: `agent_response_received(agent_id: String, payload: String)` and `agent_connection_changed(agent_id: String, new_state: String)`.
- `agent_id: String` everywhere (never `StringName`).
- **Mock mode (ADR-0008)**: when `ConfigurationLoader.is_mock()` is true, instantiate `MockBridge` driver instead of HTTPRequest pool. Same signal interface.
- Mock cycle: read `assets/data/mock/[agent_id].json` array sequentially.

### Forbidden
- Web build: any code path that creates an `HTTPRequest` for an AI API (`web_real_api_polling`).
- JSON parsing inside Data Bridge.
- `request_completed` handlers that close over freed nodes.

---

## Audio layer

### Required (Audio Manager GDD, ADR-0003, ADR-0004)
- AudioManager is the second of two approved Autoloads.
- Bus topology: `Master → Music` + `Master → SFX`.
- Pool: 8 pre-instantiated `AudioStreamPlayer` nodes; no runtime allocation.
- Caller owns stream lookup (Audio Manager is stream-agnostic).
- Default volumes: Music −18 dB, SFX −12 dB, Alert −8 dB.
- Global mute (M key) + per-bus mute via Settings panel.
- **Web AudioContext (ADR-0004 A1 amended 2026-05-12.1)**: on web, instantiate a dedicated silent `AudioStreamPlayer` referencing `res://assets/audio/silence_50ms.ogg`. On first `InputEventMouseButton` or `InputEventKey` press, call `.play()` on it. This is the **guaranteed cross-browser AudioContext-wake mechanism** — the old no-op `set_bus_volume_db` pattern is undocumented engine behaviour and is now the fallback path only. Smoke test on Chrome + Firefox + Safari before any web release.

### Forbidden
- Runtime allocation of `AudioStreamPlayer` nodes (use the pre-instantiated pool).
- Audio Manager looking up streams from registries (caller's job).

---

## Rendering / Viewport layer

### Required (ADR-0013)
- Project Settings:
  - `display/window/stretch/mode = "viewport"`
  - `display/window/stretch/aspect = "keep"`
  - `display/window/stretch/scale_mode = "integer"` (NOT the pre-4.4 `keep_integer` mode)
  - `display/window/size/viewport_width = 480`
  - `display/window/size/viewport_height = 270`
  - `window/dpi/allow_hidpi = true`
- Camera2D: `zoom = Vector2(1, 1)`, `position_smoothing_enabled = false`.
- Constants: `CELL_SIZE: int = 16`, `MODULE_SIZE: int = 8`.
- Y-sort topology: parent Node2D `y_sort_enabled = true` AND TileMapLayer (Wall) `y_sort_enabled = true`. Both required.
- All cell↔world conversions go through `TileMapRenderer.cell_to_world(cell)` / `.world_to_cell(world)` helpers.

### Forbidden
- `non_integer_camera_zoom` — any Camera2D with `zoom != Vector2(1, 1)`.
- `subpixel_tile_position` — positioning a Node2D at non-integer pixel coords on a Y-sorted layer.
- `hardcoded_cell_size_literal` — any literal `16` or `8` in tile math (use the constants).
- Stretch mode `canvas_items` or `disabled` (use `viewport`).

---

## HUD layer

### Required (ADR-0011, ADR-0012)
- Two CanvasLayers: `HudLayer` (layer=10) for chrome; `OverlayLayer` (layer=20) for detail overlay.
- `HudRoot` + `OverlayRoot` both `process_mode = PROCESS_MODE_ALWAYS`.
- Default `mouse_filter = MOUSE_FILTER_IGNORE` for the entire HUD subtree. Explicit `STOP` only on the 14 listed Controls (12 slots + Backdrop + DetailPanel).
- Input action `toggle_hud` mapped to `KEY_TAB`; persisted to `user://settings.json` via `ConfigurationLoader.set_setting(&"hud_visible", bool)`.
- Toggle hides BOTH CanvasLayers; force-closes overlay when hiding chrome.
- Theme: `HudRoot.theme = preload("res://assets/themes/pixel.tres")`.
- Slot connection alpha: `modulate.a` map: CONNECTED 1.0, STALE 0.5, DISCONNECTED 0.25, ERROR 0.25 + red tint.

### Forbidden
- `single_canvaslayer_hud` — chrome and overlay must not share a CanvasLayer.
- `hud_separate_connection_overlay` — connection quality is `modulate.a` on the slot itself, not a sibling ColorRect.
- `per_label_font_override` — fonts come from Theme, never via `add_theme_font_override(...)`.
- `multiple_hud_font_sizes_mvp` — exactly one font size (7px) for MVP.
- `recursive_mouse_filter_ignore_on_hud_ancestor` — do NOT enable Godot 4.5+'s opt-in recursive `MOUSE_FILTER_IGNORE` propagation feature on any Control that is an ancestor of the 12 slot Controls. It would override the 14 explicit STOP overrides and silently mask all slot clicks (ADR-0011 A1).
- `world_tab_handler_in_input` — world nodes must NOT handle Tab in `_input()`. Use `_unhandled_input()` or InputMap action-mapped checks so the HUD toggle can suppress Tab first (ADR-0011 A2).

---

## Font / Text layer

### Required (ADR-0012)
- Font resource: `res://assets/fonts/pixel_font_5x7.tres` (a `FontFile` resource).
- Source: `res://assets/fonts/pixel_5x7.ttf`.
- FontFile properties (locked):
  - `fixed_size = 7`
  - `fixed_size_scale_mode = FIXED_SIZE_SCALE_INTEGER_ONLY`
  - `antialiasing = FONT_ANTIALIASING_NONE`
  - `subpixel_positioning = SUBPIXEL_POSITIONING_DISABLED`
  - `hinting = HINTING_NONE`
  - `generate_mipmaps = false`
  - `oversampling = 1.0`
- Theme: `res://assets/themes/pixel.tres` with `default_font = preload(...)` + `default_font_size = 7`.

### Forbidden
- `bitmap_font_class_usage` — never reference `BitmapFont` class (it's `FontFile` in Godot 4).
- Per-Label font assignment via `add_theme_font_override` (see HUD layer).

---

## Animation layer

### Required (ADR-0009, ADR-0010)
- **Tween (one-shot transient effects)**: every `create_tween()` immediately followed by `.bind_node(target)`. Re-trigger via `kill()` + new `create_tween()`. Cleanup via `finished` signal connection (never `await tween.finished` when target may free). Pause via owning Node's `process_mode`.
- **AnimationPlayer (state-driven repeating effects)**: per-agent and per-room instances. `active = true` explicit at `_ready()`. Subscribe to `agent_state_changed` via `.bind(agent_id)` per ADR-0006 Tier 2.
- AnimationLibrary path convention: `res://assets/animations/agent_<type>.tres`.
- Animation names canonical: `idle`, `working`, `completed`, `errored`.
- Loop policy: `idle`/`working`/`errored` LOOP_LINEAR; `completed` LOOP_NONE → on `animation_finished`, re-read ASM state and play the matching animation (not hardcoded `idle`).
- **Presentation-property carve-out**: animating `modulate`, `scale`, transient `position`/`rotation` on a cross-system Node2D/Control is **exempt** from `direct_cross_system_state_write`, provided the sanctioned reference is injected and the Tween follows the `bind_node()` pattern.

### Forbidden
- `tween_without_bind_node` — every `create_tween()` requires immediate `bind_node()`.
- `await tween.finished` — use signal connection.
- `Tween.stop()` for re-trigger — use `kill()` + new tween.
- `animatedsprite_for_state_anim` — use AnimationPlayer + AnimationLibrary, not AnimatedSprite2D.
- `animationplayer_for_oneshot_property` — use Tween for one-shot property effects, not AnimationPlayer.
- `hardcoded_revert_after_oneshot` — post-`completed` revert reads ASM state, not assumes `idle`.

### Reduced motion (per accessibility-requirements.md §1.3)
- If `ConfigurationLoader.get_setting(&"reduced_motion", false)` is true:
  - Tween durations clamp to ≤ 0.1s (step-cut behaviour)
  - AnimationPlayer ambient loops freeze on first frame
  - Connection-quality alpha changes still apply instantly (information-bearing)

---

## Test framework + CI

### Required (ADR-0014)
- GUT 9.x as the sole approved test addon. Installed at `addons/gut/`.
- Test directories: `tests/unit/`, `tests/integration/`.
- Naming: files `test_[system]_[feature].gd`; functions `test_[scenario]_[expected]()`.
- Headless runner: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
- CI: `.github/workflows/tests.yml` runs on push to main + PRs; failing tests block merge (hard gate).
- `addons/gut/` excluded from export presets.

### Forbidden
- Disabling failing tests to make CI green.
- Tests with random seeds, `OS.get_ticks_msec()` assertions, or other non-determinism.
- Tests that depend on execution order.
- Test fixtures with inline magic numbers (use constants / factory functions).

---

## Signal patterns

### Required (ADR-0005, ADR-0006)
- **task_completed** is emitted **only** by Agent State Machine. Signature: `task_completed(agent_id: String)`.
- **agent_state_changed** signature: `agent_state_changed(agent_id: String, new_state: String, previous_state: String)`.
- Cross-system signal subscription patterns (ADR-0006 Tier model):
  - Tier 1 — broadcast: `signal.connect(handler)`, no filtering
  - Tier 2 — per-entity: `signal.connect(handler.bind(agent_id))` — filter inside handler
  - Tier 3 — autoload lookup: read-only `get_agent_state(id)` etc., never write
- Data Bridge signal names canonical: `agent_response_received`, `agent_connection_changed` (NOT `payload_received`, `connection_state_changed`).

### Forbidden
- Any system besides ASM emitting `task_completed`.
- Cross-system *write* via Tier 3 (read-only API only).
- Multiple subscribers using Tier 2 with conflicting `.bind()` payloads on the same signal.

---

## Agent State Machine (ASM) layer

### Required (ADR-0007 + ADR-0005 + ADR-0006)

- **Vocabulary** (exactly four states): `idle`, `working`, `completed`, `errored`. String values (NOT StringName per ADR-0001 contract).
- **Connection state stays separate** from agent state (orthogonality). HUD composes both per ADR-0011.
- **Derivation rule**: ASM parses `agent_response_received(agent_id, payload)` JSON. Match on `stop_reason`:
  - `end_turn`, `max_tokens`, `stop_sequence` → `completed`
  - `tool_use`, `pause_turn` → `working`
  - `refusal` → `errored`
  - HTTP error envelope (`type: "error"`) → `errored`
  - Unparseable JSON → `errored`
  - Unknown `stop_reason` → `completed` + `push_warning` (conservative fallback)
- **`completed` is transient** — Timer of `COMPLETED_DECAY_SEC = 1.5` schedules decay back to `idle` on entry. Matches TR-hud-004 slot glyph timer.
- **`task_completed(agent_id)` emits on every entry into `completed`** (per ADR-0005). TCB subscribes.
- **`working` requires in-flight tracking** — Data Bridge must expose `is_request_in_flight(agent_id)` or signal dispatch/settle. Pending ADR-0001 amendment.
- Public read-only API: `get_agent_state(id) -> String`, `get_agent_stats(id) -> Dictionary`, `is_agent_known(id) -> bool` (per ADR-0006 Tier 3).

### Forbidden
- `agent_state_stringname` — agent state strings must be `String`, not `StringName` (consistency with ADR-0001 `agent_id: String`).
- `completed_persistent_no_decay` — `completed` must decay to `idle` after 1.5s. Stale glyphs break the "satisfying feedback then return to ambient" pillar.
- `errored_auto_decay` — `errored` must NOT auto-decay. It persists until the next non-error response.
- `task_completed_from_non_completed_entry` — `task_completed` fires ONLY on transitions INTO `completed`, never on transitions out or on `idle/working/errored` directly.
- `inline_stop_reason_match` — production code must use the canonical mapping table from ADR-0007, not ad-hoc inline `match` blocks in random consumers.

## Blocked / pending

**None.** All 14 ADRs are Accepted as of 2026-05-12 pm. No architectural blocks remain in the Pre-Production critical path.

---

## VERIFY items (engine-empirical claims)

**Sweep status (2026-05-12)**: godot-specialist consulted on items 10–20. Full report: `docs/architecture/verify-sweep-2026-05-12.md`. **6 PASS / 5 CONCERN / 0 FAIL.** Items 7 + 8 remain pending Data Bridge prototype (Sprint 1).

| # | Claim | ADR | Verdict (2026-05-12) | Resolution path |
|---|---|---|---|---|
| 7 | `HTTPRequest.request_completed` signal signature unchanged in 4.4–4.6 | 0001 | OPEN | Data Bridge prototype (Sprint 1) |
| 8 | `HTTPRequest.timeout` clean cancellation in 4.6.2 | 0001 | OPEN | Data Bridge prototype (Sprint 1) |
| 10 | `JavaScriptBridge` singleton available in 4.6.2 web export | 0004 | **PASS** (HIGH) | — closed |
| 11 | `OS.has_feature("web")` true at `_ready()` in 4.6.2 HTML5 build | 0004 | **PASS** (HIGH) | — closed |
| 12 | AudioServer activity resumes Web AudioContext on first gesture in Chrome/Firefox/Safari | 0004 | **CONCERN** (LOW) | Web build smoke on 3 browsers. ADR-0004 A1 amended: primary path now `AudioStreamPlayer.play()` on silent stream |
| 13 | HiDPI Mac Retina produces crisp ×N scaling at 480×270 | 0013 | **CONCERN** (MED) | Smoke on 2560×1600, 2880×1800, 3024×1964 |
| 14 | `image-rendering: pixelated` holds at non-integer browser zoom | 0013/0004 | **CONCERN** (MED) | Known Safari limitation documented; canonical zoom = 100% / 200% |
| 15 | `MOUSE_FILTER_IGNORE` parent allows STOP child to receive clicks in 4.6.2 | 0011 | **PASS** (HIGH) | Closed — new guardrail added (`recursive_mouse_filter_ignore_on_hud_ancestor`) |
| 16 | `set_input_as_handled()` in `_unhandled_input` consumes Tab from world | 0011 | **PASS** (HIGH) | Closed — new contract: world must not handle Tab in `_input()` |
| 17 | `FIXED_SIZE_SCALE_INTEGER_ONLY` produces zero anti-aliasing at integer multiples | 0012 | **CONCERN** (MED) | Visual smoke at ×1/×2/×4/×8 (especially ×8 = 3840×2160) |
| 18 | Theme `default_font` propagates to nested Control subtrees | 0012 | **PASS** (HIGH) | Closed — GUT test sufficient |
| 19 | `AnimationLibrary` assignment via `add_animation_library(&"", lib)` is canonical | 0009 | **PASS** (HIGH) | — closed |
| 20 | `animation_finished` fires exactly once for LOOP_NONE animation at end-of-track | 0009 | **CONCERN** (MED) | GUT test `test_completed_finishes_reverts_to_current_asm_state` |
| 21 | `tool_use` and `pause_turn` stop_reasons map to `working` correctly in production | 0007 | OPEN | Smoke test when first non-trivial agent task surfaces them |
| 22 | `refusal` stop_reason maps to `errored` and slot renders correctly | 0007 | OPEN | Rare event; validate when first observed |

### Empirical smoke tests still required before code lands

Three highest-priority smoke tests from the sweep:

1. **VERIFY-12 (HIGHEST)** — Web AudioContext on Chrome + Firefox + Safari. If `AudioStreamPlayer.play()` on the silent stream fails on Safari, AudioManager unlock strategy needs another iteration. Run before first web build ships.
2. **VERIFY-17** — `FIXED_SIZE_SCALE_INTEGER_ONLY` at ×8 (3840×2160). Manual visual smoke at 4K window before HUD font pipeline signed off.
3. **VERIFY-20** — `animation_finished` signal timing under `AnimationMixer` base class. GUT smoke before ACC implementation stories marked Done.

---

## How to use this manifest

- **Writing a story**: copy `Manifest Version: 2026-05-12` into the story header. `/story-done` checks staleness against the current manifest version.
- **Code review**: every Required is an asserted property; every Forbidden is a search target (grep, lint, or eyeballed). Use this as your review checklist.
- **Onboarding**: read this front-to-back before your first commit. Then read the ADRs that govern the layer you're touching.

## When to update this manifest

- New ADR Accepted → extract its Required / Forbidden into the relevant layer + bump `Manifest Version`.
- ADR Superseded → strike the old rules, add new, bump version, document the supersession.
- Cross-cutting change (e.g. ADR-0007 finally Accepted) → version bump + propagate.

## Source ADRs

ADR-0001 (Data Bridge), ADR-0002 (Config), ADR-0003 (Autoload), ADR-0004 (Web Export), ADR-0005 (task_completed source), ADR-0006 (Signal decoupling), ADR-0008 (Mock mode), ADR-0009 (AnimationPlayer), ADR-0010 (Tween), ADR-0011 (HUD), ADR-0012 (BitmapFont), ADR-0013 (Stretch Mode), ADR-0014 (Test Framework + CI).
