# ADR-0011: HUD Rendering Strategy

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | UI / CanvasLayer / Control |
| **Knowledge Risk** | LOW — CanvasLayer + Control API stable since Godot 4.0. The contentious aspect is the 480×270 viewport contract (established by ADR-0013) and the inverted `mouse_filter` default convention. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, ADR-0013 (viewport contract), commanders-room-hud GDD, ADR-0010 (Tween pause behaviour), ADR-0006 (signal subscription patterns) |
| **Post-Cutoff APIs Used** | None — CanvasLayer + Control + mouse_filter unchanged in 4.4–4.6 |
| **Verification Required** | New VERIFY-15: confirm `MOUSE_FILTER_IGNORE` inheritance behaviour in 4.6.2 (does a STOP child still receive clicks when its IGNORE parent does not?); new VERIFY-16: confirm `set_input_as_handled()` in `_unhandled_input` prevents the world from receiving the Tab keypress |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 Autoload Scene Composition (Accepted) — HUD lives under Main Scene, not Autoload. ADR-0006 Signal-Based Decoupling (Accepted) — HUD subscribes to ASM + TCB + Room System signals. ADR-0010 Tween Lifecycle (Proposed) — HUD slot timers use the mandated Tween pattern with `bind_node()`. ADR-0013 Stretch Mode + Pixel-Perfect (Proposed) — 480×270 viewport contract. ADR-0002 Config Loading + Persistence (Accepted) — `hud_visible` setting persists via `setting_changed`. |
| **Enables** | HUD implementation stories (TR-hud-001..012 minus 008/009 which are covered elsewhere); detail overlay implementation; slot interaction handling. |
| **Blocks** | All HUD implementation work until Accepted. |
| **Ordering Note** | Should be Accepted after ADR-0013 (depends on viewport contract) and before ADR-0012 (HUD layout drives bitmap font sizing constraints). |

## Context

### Problem Statement

The Commander's Room HUD is the player's primary information surface. It must:

1. **Render in screen-space** over the world view (per commanders-room-hud GDD)
2. **Never crop the world camera** — world should always show the full 480×270 viewport
3. **Be non-modal** — clicks on world (computers, agents) must pass through HUD chrome
4. **Survive pause** — slot timers and status updates continue during pause menus
5. **Support a clean detail-overlay layer** that does not require Z-order management when shown
6. **Express connection quality per agent** without doubling the slot node count
7. **Be toggleable** — user can hide HUD entirely for full-world visibility

Without an explicit topology decision, each HUD sub-feature would solve these independently, producing inconsistent mouse_filter chains, brittle Z-order, and divergent pause behaviour. TR-hud-001, 002, 003, 004, 005, 007, and 010 all hinge on these decisions.

### Constraints
- Engine: Godot 4.6.2 / GDScript / 2D Renderer / CanvasLayer + Control
- Viewport: 480×270 (per ADR-0013) scaled to window size by integer multiples
- Performance: ≤16.6ms/frame budget; HUD must be sub-1ms cost
- Pixel art: all HUD glyphs use a 5×7 bitmap font (per ADR-0012, planned)
- World view must remain fully visible — HUD chrome may occlude but never crop the camera

### Requirements
- Two-tier visual layering: chrome (always present) + overlay (on-demand)
- Click pass-through default (HUD does not block world interaction)
- Pause-immune HUD process_mode
- Single source of truth for connection-quality visual state
- One-keypress toggle to hide/show HUD entirely; preference persists across sessions

## Decision

### TL;DR
**Two CanvasLayers** — `HudLayer` (layer=10, status panel + 3×4 slot grid + completions strip) and `OverlayLayer` (layer=20, detail overlay). HUD root `process_mode = PROCESS_MODE_ALWAYS` for pause-immunity. All HUD Controls default to `mouse_filter = MOUSE_FILTER_IGNORE` with explicit `STOP` overrides on 14 click-targets. Connection-quality alpha applied as `modulate.a` per slot node, not a separate overlay. **Tab toggles both CanvasLayers' `visible`** and persists the choice via ConfigurationLoader. Layout anchored to the 480×270 viewport corners.

### Rendering Model: World is Full-Viewport; HUD Overlays

A critical clarification: because the HUD lives on a CanvasLayer (screen-space overlay), **the world camera always sees the full 480×270 viewport**. HUD chrome paints *over* the world; it does not shrink the world view. World content beneath the HUD is rendered — just visually occluded.

The user can hide the HUD entirely (Tab) to see the full world without any occlusion.

### Two-CanvasLayer Topology

```
Main Scene
├── WorldRoot (Node2D, y_sort_enabled = true)
│   ├── TileMapLayers + Agents (per ADR-0013)
│   └── Camera2D (zoom = 1, pixel-snap)
│
├── HudLayer (CanvasLayer, layer = 10)
│   └── HudRoot (Control, mouse_filter = IGNORE, process_mode = PROCESS_MODE_ALWAYS)
│       ├── StatusPanel (TR anchor)
│       ├── SlotGrid (TL anchor, 3×4 = 12 slots)
│       └── CompletionsStrip (BC anchor)
│
└── OverlayLayer (CanvasLayer, layer = 20)
    └── OverlayRoot (Control, visible = false initially, process_mode = PROCESS_MODE_ALWAYS)
        ├── Backdrop (ColorRect, modulate.a = 0.6, mouse_filter = STOP)
        └── DetailPanel (Control, mouse_filter = STOP)
```

Why two layers:
- Chrome is always there; overlay slides in when needed — clean separation
- Z-order is determined by `layer` (10 < 20), no `move_to_front()` calls needed
- Layer numbers leave room for future layers (system messages = 30, pause menu = 40) without renumbering
- Each layer can independently set `visible` for toggling

### HUD Visibility Toggle

The user can hide the entire HUD with a single keypress (Tab). State persists across sessions.

```gdscript
# hud.gd (HudLayer root script)
func _ready() -> void:
    visible = ConfigurationLoader.get_setting(&"hud_visible", true)
    OverlayLayer.visible = false  # detail overlay always starts closed

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"toggle_hud"):
        visible = not visible
        if not visible:
            OverlayLayer.visible = false  # close detail overlay if open
        ConfigurationLoader.set_setting(&"hud_visible", visible)
        get_viewport().set_input_as_handled()
```

Toggle contract:
- Default state on first launch: visible (so the user discovers the HUD)
- Toggle key: input action `toggle_hud`, mapped to `KEY_TAB` by default (remappable)
- What toggles: both `HudLayer.visible` and `OverlayLayer.visible` together (clean state — never an "overlay visible without chrome" oddity)
- Persists: yes, via `ConfigurationLoader.set_setting(&"hud_visible", bool)`
- During pause: yes, because `process_mode = PROCESS_MODE_ALWAYS` keeps the input handler live

When HUD is hidden, the user sees the unobstructed world view at full viewport scale.

### Pause-Immune Process Mode

Both `HudRoot` and `OverlayRoot` set `process_mode = PROCESS_MODE_ALWAYS`. This means:
- Slot timers (1.5s `+` glyph after `beat_fired`) continue ticking during pause
- Status panel updates from `agent_state_changed` arrive even when world is paused
- Toggle key works during pause
- Detail overlay can be opened, scrolled, and dismissed during pause

Tween targets in the HUD inherit this `process_mode`, so the `bind_node()` pattern from ADR-0010 keeps slot-timer Tweens running during pause.

### Inverted Mouse Filter Default

Godot's Control default is `MOUSE_FILTER_STOP` (intercept clicks). The HUD needs the opposite — clicks must pass through chrome to the world. This ADR establishes an inverted default for the HUD subtree.

| Control | `mouse_filter` |
|---|---|
| HudLayer root (HudRoot) | IGNORE |
| StatusPanel root + all children | IGNORE |
| SlotGrid root | IGNORE |
| **Individual SlotControl (×12)** | **STOP** — clickable to open detail overlay |
| CompletionsStrip root + all children | IGNORE |
| OverlayLayer root (OverlayRoot) | IGNORE when `visible == false`, STOP when `visible == true` |
| OverlayRoot.Backdrop | STOP — click to dismiss |
| OverlayRoot.DetailPanel + interactive children | STOP |

Total STOP overrides: 14 specific Controls (12 slots + backdrop + detail panel). Everything else IGNORE.

VERIFY-15 closure pending: confirm that `MOUSE_FILTER_IGNORE` on a parent does not block clicks reaching a `STOP` child. Per Godot 4 docs, IGNORE means "this Control doesn't receive mouse events but doesn't stop them either"; STOP children still process clicks. Smoke test before shipping.

**TR-hud-010 is satisfied by this pattern** (detail overlay non-modal, status panel `mouse_filter = MOUSE_FILTER_IGNORE`).

### Connection-Quality via Slot modulate.a

Rather than a separate overlay ColorRect per slot, each slot script applies `modulate` directly based on ASM connection state:

```gdscript
# slot.gd
func _on_connection_state_changed(state: String) -> void:
    match state:
        "CONNECTED":
            modulate = Color(1.0, 1.0, 1.0, 1.0)
        "STALE":
            modulate = Color(1.0, 1.0, 1.0, 0.5)
        "DISCONNECTED":
            modulate = Color(1.0, 1.0, 1.0, 0.25)
        "ERROR":
            modulate = Color(1.5, 0.7, 0.7, 0.6)  # red-shifted tint + dimmed
```

Driver: each slot subscribes to `ASM.agent_connection_changed(agent_id, new_state)` with `.bind(agent_id)` filtering per ADR-0006 Tier 2.

**TR-hud-007 is satisfied** by this single-write-per-state-change pattern. No separate overlay nodes; no extra draw calls.

### Layout (anchored to 480×270 viewport)

```
┌────────────────────────────────────────────────────────────┐  480 wide
│ ░░░░░░░░░░░░░░ World renders FULL VIEWPORT ░░░░░░░░░░░░░░░ │
│ ░┌──────────────┐░░░░░░░░░░░░░░░░░░░░░░░░░┌──────────────┐│
│ ░│ Slot Grid    │░░░░░░░░░░░░░░░░░░░░░░░░░│ Status Panel ││
│ ░│ TL anchor    │░ The world camera sees ░│ TR anchor    ││
│ ░│ offset 4,4   │░ everything here too — ░│ offset -4,4  ││
│ ░│              │░ HUD just paints       ░│              ││
│ ░│ 76×120 px    │░ on top.                ░│ 88×80 px     ││
│ ░│              │░                        ░│              ││
│ ░│ 3 cols ×     │░                        ░│ Agent count: ││
│ ░│ 4 rows       │░                        ░│ X / 12       ││
│ ░│              │░                        ░│ Connected: Y ││
│ ░└──────────────┘░░░░░░░░░░░░░░░░░░░░░░░░░└──────────────┘│
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░┌────────────────────────────┐░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░│ Completions Strip          │░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░│ BC anchor, offset 0,-4     │░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░│ 6 entries max, recency L→R │░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░│ ~280×24 px                 │░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░└────────────────────────────┘░░░░░░░░░░░ │
└────────────────────────────────────────────────────────────┘  270 tall
```

Anchor strategy (Godot Control anchors):
- SlotGrid: `anchor_left/top = 0`, `anchor_right/bottom = 0`, offset (4, 4)
- StatusPanel: `anchor_left/right = 1`, `anchor_top/bottom = 0`, offset (-4, 4)
- CompletionsStrip: `anchor_left/right = 0.5`, `anchor_top/bottom = 1`, offset (0, -4)
- DetailPanel: centred (`anchor_*/2 = 0.5`), 240×180 px

Total HUD chrome footprint when visible: ~30% of viewport area. When toggled off via Tab: 0%.

### Detail Overlay Open/Close

Slot click handler (the only "interactive" HUD path):

```gdscript
# slot.gd
func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        OverlayLayer.show_detail(agent_id)
        accept_event()
```

`OverlayLayer.show_detail(agent_id)`:
1. Populate `DetailPanel` from `ASM.get_agent_stats(agent_id)`
2. Set `OverlayRoot.visible = true`
3. Set `OverlayRoot.mouse_filter = MOUSE_FILTER_STOP` (was IGNORE)

Dismiss paths (any one):
- Click `Backdrop` → `OverlayRoot.visible = false`, mouse_filter back to IGNORE
- Press Esc → same (handled in `_unhandled_input` on OverlayRoot)
- Press Tab → both layers toggle off (handled in HudLayer root)

### Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│ Main Scene                                                 │
│                                                            │
│  WorldRoot (layer = world)                                 │
│   └── TileMap + Agents + Camera2D                          │
│                                                            │
│  HudLayer  (CanvasLayer, layer = 10)                       │
│   └── HudRoot (mouse_filter = IGNORE, mode = ALWAYS)       │
│       ├── StatusPanel (IGNORE)                             │
│       ├── SlotGrid (IGNORE)                                │
│       │    └── Slot[0..11] (STOP — clickable)              │
│       └── CompletionsStrip (IGNORE)                        │
│                                                            │
│  OverlayLayer (CanvasLayer, layer = 20)                    │
│   └── OverlayRoot (visible = false, mode = ALWAYS)         │
│       ├── Backdrop (STOP)                                  │
│       └── DetailPanel (STOP)                               │
│                                                            │
│  Input Flow:                                               │
│   ├── Click on world  → passes through HUD IGNORE          │
│   ├── Click on slot   → opens overlay                      │
│   ├── Click on overlay backdrop → dismisses overlay        │
│   ├── Tab keypress    → toggles both CanvasLayers          │
│   └── Esc keypress    → dismisses overlay (if open)        │
└────────────────────────────────────────────────────────────┘
```

### Key Interfaces

This ADR does not introduce new public signals. It adds:
- Input action: `toggle_hud` (default KEY_TAB)
- ConfigurationLoader setting: `hud_visible: bool` (default true, persisted)
- Slot subscribes to `ASM.agent_connection_changed(agent_id, state)` via `.bind(agent_id)` (per ADR-0006)

Registry updates when Accepted:
- `hud_canvaslayer_topology` api_decision: two-CanvasLayer split with layer numbers 10 + 20
- `hud_default_mouse_filter_pass` api_decision: HUD subtree defaults to IGNORE; STOP is an explicit override
- `hud_process_mode_always` api_decision: HUD root + Overlay root always process during pause
- `hud_toggle_via_action` api_decision: single input action toggles both CanvasLayers
- `single_canvaslayer_hud` forbidden_pattern: chrome and overlay must not share a CanvasLayer
- `hud_separate_connection_overlay` forbidden_pattern: connection quality must be `modulate.a` on the slot itself, not a sibling ColorRect

## Alternatives Considered

### Alternative A — Single CanvasLayer for chrome + overlay

- **Description**: One CanvasLayer; detail overlay is a sibling Control hidden by default.
- **Pros**: One fewer node; simpler hierarchy.
- **Cons**: Z-order requires `move_to_front()` calls when overlay opens; chrome must disable its own mouse_filter while overlay is up (fragile); toggling visibility hits one node but the overlay's z-position would shift relative to future layers (system messages, pause menu).
- **Rejection Reason**: Two layers cost almost nothing; the topology clarity is worth it.

### Alternative B — HUD in main scene tree (no CanvasLayer)

- **Description**: Status panel etc. as plain Control nodes parented to WorldRoot; manually offset by Camera2D position each frame.
- **Pros**: No CanvasLayer to manage.
- **Cons**: Every HUD node needs per-frame Camera2D-compensation math; pixel-snap math becomes error-prone; doesn't gain anything over CanvasLayer.
- **Rejection Reason**: CanvasLayer is the documented Godot pattern for screen-space UI.

### Alternative C — UI Toolkit / Window node for detail overlay

- **Description**: Detail overlay as a `Window` node (popup window).
- **Pros**: Built-in dismiss handling; modal semantics.
- **Cons**: Popup windows don't honour the viewport scale (would render at OS native size, not the upscaled 480×270 framework); breaks the pixel-art aesthetic.
- **Rejection Reason**: Aesthetic violation.

### Alternative D — Connection-quality as separate per-slot ColorRect overlay

- **Description**: Each slot has a sibling ColorRect that paints translucent grey based on connection state.
- **Pros**: Slot's own modulate stays clean for animation purposes.
- **Cons**: Doubles slot node count (12 → 24); the overlay would have to track the slot's position; any future slot-level animation has to remember to update the overlay too.
- **Rejection Reason**: One `modulate.a` write is simpler and produces identical visual.

### Alternative E — Inverted toggle: HUD hidden by default, Tab shows

- **Description**: First launch shows full-screen world; user discovers Tab to show HUD.
- **Pros**: Cinematic on first launch.
- **Cons**: User has no idea the HUD exists; no information until they explore controls.
- **Rejection Reason**: Discoverability fails. Default = visible.

### Alternative F — Hold-to-show instead of toggle

- **Description**: Tab held = HUD shown; release = hidden. Like a peek.
- **Pros**: Lightweight; great for "glance at status."
- **Cons**: User wants to leave HUD on while doing other things; hold model fights that. User explicitly asked for toggle.
- **Rejection Reason**: User requirement is toggle.

### Alternative G — Fade transition on toggle

- **Description**: HUD fades in/out over 0.3s on Tab.
- **Pros**: Polished.
- **Cons**: User explicitly asked for "simple on and off"; fade adds Tween coordination across two CanvasLayers and complicates the pause-immune behaviour.
- **Rejection Reason**: Out of scope per user direction.

## Consequences

### Positive
- Clean two-tier topology — chrome and overlay are independently managed
- World view always full-viewport; HUD never crops camera (TR-hud-001)
- Non-modal click pass-through (TR-hud-010) satisfied with explicit + auditable mouse_filter map
- Pause-immune (TR-hud-004 slot timers during pause; toggle works during pause)
- Connection-quality (TR-hud-007) is a one-line write per state change
- Toggle gives user agency over screen real-estate
- Layer numbers (10, 20) leave room for future overlays without renumbering
- 14 explicit `STOP` overrides are auditable in code review

### Negative
- Two CanvasLayers add structural complexity vs. one
- Inverted mouse_filter convention is non-default Godot — onboarding hazard
- Toggle persistence creates a new setting key (`hud_visible`) — minor ConfigLoader surface
- HUD chrome occludes ~30% of viewport when visible (mitigated by toggle)

### Risks

| Risk | Mitigation |
|---|---|
| Developer adds a HUD Control with default STOP, breaks click-pass-through | Code review checklist: "Every HUD Control's mouse_filter is explicitly set"; lint check; documented in control manifest |
| `MOUSE_FILTER_IGNORE` parent blocks STOP child clicks (VERIFY-15) | Smoke test in GUT (instantiate HUD, simulate click on slot, assert handler fires); manual smoke before shipping |
| Tab keypress leaks to world (no `set_input_as_handled`) | Explicit `set_input_as_handled()` in the toggle handler; GUT test asserts world doesn't receive Tab when HUD handles it |
| User toggles HUD off, forgets it exists, thinks app is broken | Default = visible; future post-MVP: subtle "Tab: HUD" hint when hidden for >30s |
| Detail overlay shown while HUD hidden creates orphaned state | Toggle handler force-closes overlay when hiding HUD |
| Slot's modulate.a write conflicts with future slot animation Tween | Document: connection-quality writes `modulate` directly; any animation Tween must write `modulate` from current value, not a hardcoded neutral |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `commanders-room-hud.md` | TR-hud-001 (Screen-edge CanvasLayer panel + screen-space detail overlay) | Two CanvasLayers, anchored chrome + centred overlay |
| `commanders-room-hud.md` | TR-hud-002 (3×4 slot grid state sync with ASM) | SlotGrid layout; slot script subscribes to ASM signals per ADR-0006 |
| `commanders-room-hud.md` | TR-hud-003 (Completions strip cap 6 entries) | CompletionsStrip layout; cap enforced in strip script |
| `commanders-room-hud.md` | TR-hud-004 (Per-slot 1.5s timers for `+` glyph after `beat_fired`) | HudRoot `PROCESS_MODE_ALWAYS` keeps timers running during pause |
| `commanders-room-hud.md` | TR-hud-005 (`tasks_completed` per-agent accumulator) | Slot script maintains counter; updated on `beat_fired` |
| `commanders-room-hud.md` | TR-hud-007 (Connection-quality alpha overlay) | `modulate.a` per slot driven by ASM state; alpha map codified |
| `commanders-room-hud.md` | TR-hud-010 (Detail overlay non-modal, status panel IGNORE) | Inverted mouse_filter default + 14 STOP overrides |

## Performance Implications
- **CPU**: HUD chrome = ~50 Control nodes; per-frame layout cost is sub-100µs. Slot signal handlers are zero-cost when no state change occurs.
- **Memory**: Two CanvasLayers + ~50 Controls = ~50KB; negligible
- **Load Time**: Zero impact (HUD instantiated alongside main scene)
- **Network**: N/A
- **Draw Calls**: HUD adds ~15 draw calls (chrome) + ~5 when overlay shown; well within 1000-call budget

## Migration Plan
No existing code to migrate (pre-production). Apply at first HUD implementation story.

## Validation Criteria
- GUT test: `test_hud_two_canvaslayers` — instantiate Main Scene; assert HudLayer.layer == 10 and OverlayLayer.layer == 20
- GUT test: `test_hud_root_process_mode_always` — assert HudRoot.process_mode == PROCESS_MODE_ALWAYS
- GUT test: `test_hud_mouse_filter_inversion` — assert HudRoot.mouse_filter == IGNORE and Slot[0].mouse_filter == STOP
- GUT test: `test_hud_click_passthrough` — simulate click on a world position covered by status panel; assert world receives the click
- GUT test: `test_hud_slot_click_opens_overlay` — simulate click on a slot; assert OverlayLayer.visible becomes true
- GUT test: `test_hud_toggle_persists` — simulate Tab keypress; assert ConfigurationLoader.get_setting("hud_visible") flips
- GUT test: `test_hud_toggle_closes_overlay` — open detail overlay; press Tab; assert OverlayLayer.visible == false
- GUT test: `test_slot_connection_alpha_map` — emit `agent_connection_changed(STALE)`; assert slot.modulate.a == 0.5
- Manual smoke: open detail overlay, press Esc → overlay dismisses; click world behind status panel → world receives click; pause game, press Tab → HUD toggles during pause

## Related Decisions
- ADR-0003 Autoload Scene Composition — HUD lives under Main Scene, not Autoload
- ADR-0006 Signal-Based Decoupling — HUD subscribes via Tier 2 patterns (`.bind(agent_id)`)
- ADR-0010 Tween Lifecycle — HUD Tweens use `bind_node()` + `PROCESS_MODE_ALWAYS` for pause-immunity
- ADR-0013 Stretch Mode + Pixel-Perfect — 480×270 viewport contract this ADR builds on
- ADR-0002 Config Loading + Persistence — `hud_visible` setting persists via `setting_changed`
- ADR-0012 BitmapFont/FontFile Strategy (planned) — defines the 5×7 font this HUD renders
- New VERIFY-15, VERIFY-16 — opened by this ADR
- TR-hud-001, TR-hud-002, TR-hud-003, TR-hud-004, TR-hud-005, TR-hud-007, TR-hud-010 — covered by this ADR

---

## Amendment 2026-05-12 (post-engine-verify-sweep)

Source: `docs/architecture/verify-sweep-2026-05-12.md` (godot-specialist consultation)

### A1 — Recursive IGNORE propagation guardrail (4.5+ feature)

**VERIFY-15 verdict**: PASS (HIGH confidence) — but with one new guardrail surfaced.

Godot 4.5 introduced an opt-in feature that allows `MOUSE_FILTER_IGNORE` to propagate recursively to descendants (overriding their own `mouse_filter` values). This ADR's 14-explicit-STOP-override model is **incompatible** with that feature: if any ancestor of the 12 slot Controls is set to recursive-IGNORE, all slot clicks would be silently masked.

**New forbidden pattern** (added to `docs/architecture/control-manifest.md`):
- `recursive_mouse_filter_ignore_on_hud_ancestor` — do not enable the 4.5+ recursive `MOUSE_FILTER_IGNORE` propagation feature on any Control that is an ancestor of the 12 slot Controls.

The default (non-recursive) IGNORE behaviour — which this ADR relies on — is unchanged in 4.5+. We just have to avoid the new opt-in.

### A2 — World Tab handler restriction (VERIFY-16 implementation note)

**VERIFY-16 verdict**: PASS (HIGH confidence).

Subtlety surfaced: `set_input_as_handled()` in `_unhandled_input` correctly suppresses the event for any node that also uses `_unhandled_input`, but a node using `_input()` would receive the Tab *before* HudLayer's `_unhandled_input` fires. The HUD toggle cannot suppress that.

**New implementation contract**: World nodes must NOT handle Tab in `_input()`. Use `_unhandled_input()` or `InputMap` action-mapped checks so the HUD toggle can suppress the Tab event first. Documented in the control manifest under "Input handling" rules.
