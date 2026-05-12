# Interaction Patterns Library — The Situation Room

> **Status**: Baseline (MVP-scoped)
> **Last Updated**: 2026-05-12
> **Owner**: UX

The Situation Room has a small interaction surface — one room, mouse-first, no menus deep enough to warrant a navigation model. This library enumerates the canonical patterns so HUD + Room System + future Settings UI all behave consistently.

---

## P1 — Clickable Prop (diegetic)

**When**: An in-world Node2D (computer, monitor, future props) is interactable.

**Visual**: No persistent indicator. Hover changes cursor to `pointer` (Godot default for mouse_filter=STOP) AND adds a subtle `modulate.v` lift (+15% brightness) via Tween (per ADR-0010, with `bind_node()`).

**Interaction**:
- Mouse: hover → click
- Keyboard: (out of scope MVP — flagged in accessibility-requirements.md §2.1)

**Feedback**: One-shot Tween of `scale` (1.0 → 0.95 → 1.0) over 0.15s on click (squish). Signal `prop_interacted(prop_id)` emitted via Room System ownership (per ADR-0006).

**Anti-pattern**: Do not draw a glow outline or "[E]" hint above props — this is a diegetic-aesthetic project.

---

## P2 — HUD Slot (3×4 grid)

**When**: User clicks one of the 12 agent slots in the HUD slot grid.

**Visual**: Slot opacity reflects connection state (per ADR-0011 TR-hud-007). On hover: `modulate.v` +15% lift on top of whatever the connection-state alpha is. On click: open Detail Overlay (per P5).

**Interaction**:
- Mouse: hover → click
- Keyboard: Tab to focus (post-MVP), Enter to open detail

**mouse_filter**: STOP (per ADR-0011's 14 explicit overrides).

**Feedback**: Detail Overlay opens; clicked slot retains hover-lift while overlay is shown.

---

## P3 — Status Bar / Read-Only Chrome

**When**: HUD status panel, completions strip, any non-interactive HUD label.

**Visual**: Plain rendered text in 5×7 pixel font (per ADR-0012). No hover state. No cursor change.

**Interaction**: None — pass-through.

**mouse_filter**: IGNORE (per ADR-0011's inverted default).

**Anti-pattern**: Do not make read-only chrome look clickable (no underlines, no button frames).

---

## P4 — Toggle Key (HUD visibility)

**When**: User presses Tab to toggle HUD on/off (per ADR-0011 user requirement).

**Visual**: Hard cut — no fade, no transition.

**Interaction**:
- Keyboard: Tab (default; remappable per accessibility-requirements §2.3)
- Mouse: none (toggle is keyboard-only by design — keeps the click surface free)

**Feedback**: HUD visibly appears / disappears in a single frame. Persisted to `user://settings.json` via `ConfigurationLoader.set_setting(&"hud_visible", bool)`.

**Edge case**: Toggle while Detail Overlay is open also closes the overlay (per ADR-0011). Cleaner than leaving an orphan overlay.

---

## P5 — Detail Overlay (modal-look, non-modal-behavior)

**When**: User clicks a slot (P2) to inspect an agent.

**Visual**: Backdrop (60% black modulate) covers screen; centered DetailPanel (240×180 px) shows agent stats.

**Interaction**:
- Mouse: click backdrop OR Esc → dismiss; click DetailPanel content area = pass-through to content (no dismiss)
- Keyboard: Esc → dismiss

**mouse_filter**:
- OverlayRoot: IGNORE when hidden, STOP when shown (per ADR-0011)
- Backdrop: STOP
- DetailPanel + children: STOP

**Feedback**: Hard cut on open + close (no transition — matches P4 toggle aesthetic).

**Anti-pattern**: Do not require a "Close" button — backdrop-click or Esc must always dismiss. Do not block dismissal during animation (no transitional "input locked" state).

---

## P6 — Connection-Quality Alpha (passive feedback)

**When**: ASM emits `agent_connection_changed(agent_id, new_state)`.

**Visual**: Slot's own `modulate.a` writes per ADR-0011's alpha map (CONNECTED 1.0, STALE 0.5, DISCONNECTED 0.25, ERROR 0.25 + red tint).

**Interaction**: None — passive observation.

**Feedback**: Instantaneous write (no Tween). This is information-bearing; reduced-motion mode does not soften this further (the change IS the information per accessibility §1.3).

---

## P7 — Settings Widget (post-MVP)

**Status**: Out of scope for MVP — placeholder pattern for the future Settings panel.

**When**: User adjusts a setting (mute, volume, reduced_motion, key rebind).

**Expected interaction model**: vertical list of labelled rows; each row has one widget (toggle / slider / key-bind).

**Defer**: Full UX spec to be authored when Settings panel is scoped.

---

## P8 — Computer Prop Interaction (commander's room)

**When**: User clicks the commander's computer prop (per Room System GDD).

**Specialization of P1.** Computer is the only prop in MVP that emits a meaningful signal (`computer_interacted`).

**Visual**: Same hover/click feedback as P1.

**Edge case**: When HUD is hidden (P4), clicking the computer still works (world layer is unaffected by HUD visibility).

---

## Patterns NOT in this library (intentional)

- **Drag-and-drop**: Not used in MVP. No items to drag.
- **Long-press / hold**: Not used. All interactions are click or keypress.
- **Multi-select**: Not used. One slot = one agent.
- **Right-click context menus**: Not used. Mouse-first but click-only.
- **Scrolling**: Not used. Completions strip is capped at 6 entries (per TR-hud-003).
- **Tooltips**: Not used in MVP. Reconsider if discoverability playtest reveals confusion.
- **Drag-to-pan camera**: Not used. Camera is locked per ADR-0013.

---

## References

- ADR-0011 (HUD Rendering Strategy) — mouse_filter, toggle, overlay
- ADR-0010 (Tween Lifecycle) — hover lifts + click squishes use mandatory `bind_node()` pattern
- ADR-0006 (Signal-Based Decoupling) — signal patterns for prop interactions
- accessibility-requirements.md — keyboard alternatives, reduced motion
- art-bible.md — diegetic-aesthetic stance (no UI hints over props)
- design/gdd/room-system.md — computer prop ownership
