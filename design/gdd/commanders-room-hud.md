# Commander's Room HUD

> **Status**: Designed — pending /design-review in fresh session (PROVISIONAL: ASM interface not yet finalized — see OQ-1)
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-11
> **Implements Pillar**: Pillar 4 — Commander Always Home + Pillar 2 — Readable at a Glance

## Overview

The Commander's Room HUD is a two-part system: a permanent screen-edge status panel and a click-to-expand detail overlay. The screen-edge panel is always visible — regardless of which room the camera is in, it sits at the edge of the player's screen and assembles its content from three sources: the Agent State Machine (what each agent is currently doing), the Room System (who is configured), and the Task Completion Beat's event feed (which tasks have recently finished). Each configured agent is represented by one colored glyph using the three-glyph vocabulary (●/▬/+), and a recent completions strip accumulates the last several beats with their timestamps. Nothing on the panel moves unless state changes. Nothing requires reading — color and glyph communicate current status; the strip records what has been accomplished. The panel does not interrupt; it confirms that the operation is alive and productive without demanding attention.

The computer on the Commander's desk is a clickable prop in the room — it looks like any other room object. Clicking it opens a detail overlay on the player's screen: Zone 1 shows all agents and their current state, Zone 2 is a scrollable activity log of recent completions, and Zone 3 shows the selected agent's accumulated statistics. The room continues running behind the overlay. The primary panel is always-visible; the detail view is on demand. The player glances at the screen edge, reads, returns to work in under one second — and clicks the computer when they want to know more.

## Player Fantasy

The screen-edge panel collapses the entire bunker into a single readable shape. One look — at the corner of the screen — and the Commander knows: who is moving, who is waiting, what just finished, what just broke. The glyphs are few, the strip is short, and that is the point. The Commander is not reading a dashboard; the Commander is *recognizing* the state of their operation the way a chef recognizes a kitchen in a single sweep of the eye. When a fuller picture is needed, the computer on the desk is there — click, and the details are on screen. The room doesn't pause. The work keeps going.

The fantasy is the cognitive pleasure of total comprehension. The deep satisfaction of running something complex and still feeling, at every moment, that you have it. Not because you stared at a log or counted rows in a spreadsheet — because your operation built itself a shape you could learn, and now you know it by sight.

This is the expression of **Pillar 2 — Readable at a Glance** and **Pillar 4 — Commander Always Home**: the screen-edge panel is always there, the glyphs are always on, and the bunker's state is always a glance away.

## Detailed Design

### Core Rules

**Screen-Edge Status Panel (always visible)**

1. The primary status panel is a screen-space UI element (CanvasLayer) rendered on top of all scene content. It is always visible — it does not hide, sleep, or require the camera to be in any particular room.

2. The panel is positioned at the edge of the screen (default: bottom-right corner). Exact position and screen margins are tuning knobs. The panel must not overlap critical scene content at the default viewport resolution.

3. The panel arranges all agent slots in a **3-column × 4-row grid** (12 slots, matching `max_agents = 12`). Slot positions are fixed: agent N occupies slot N, where `row = floor(N / 3)` and `col = N mod 3`. Order follows the `agents` array in `config.json`. Positions never shift when agents are added or removed.

4. Each slot renders exactly one glyph. Glyph and color together encode the agent's complete current state:

| Glyph | Color | Hex | Meaning |
|-------|-------|-----|---------|
| ● | Green | `#5BAD63` | WORKING — agent actively processing |
| ▬ | Amber | `#D4882A` | IDLE — agent waiting or available |
| + | Green | `#5BAD63` | COMPLETED — task just finished (transient, 1.5 s) |
| ● | Sienna | `#A03520` | ERRORED — agent has encountered an error |
| ▬ | Neutral dim `#4A4035` @ ~40% alpha | — | EMPTY — no agent configured for this slot |

5. STALE and DISCONNECTED are **data-quality overlays** — they reduce the alpha of the current glyph, preserving color identity:
   - **STALE**: current glyph at **0.5 alpha**
   - **DISCONNECTED**: current glyph at **0.25 alpha**

6. The COMPLETED (+) glyph is transient. On receipt of `beat_fired(agent_id, timestamp)`:
   - a. Set slot glyph to `+` green immediately.
   - b. Start a per-slot countdown timer of **1.5 s** (matching `BEAT_TOTAL_SEC`).
   - c. On timer expiry: if last-known ASM state is WORKING → ● green; if ERRORED → ● Sienna; otherwise → ▬ amber.
   - d. Second `beat_fired` for the same slot before expiry → restart timer from 1.5 s.
   - e. ASM `"working"` signal during timer window → cancel timer, switch to ● green immediately.

7. The status panel is **reactive, not polling**. All state derives from two subscribed signal sources:
   - `AgentStateMachine.agent_state_changed(agent_id: StringName, new_state: StringName)` — drives glyph updates. *(Provisional — ASM GDD not yet designed.)*
   - `TaskCompletionBeat.beat_fired(agent_id: StringName, timestamp: float)` — drives COMPLETED transitions and completions strip.

8. The **completions strip** sits adjacent to the glyph grid (below or beside — layout is a tuning knob). Each `beat_fired` prepends one entry: `[HH:MM] [agent_id]`. Ordered most recent first. Caps at `hud_completion_strip_size` entries (default 6); oldest drop off.

9. The status panel is **display-only**. It receives no mouse input. If a click geometrically overlaps the panel area, it passes through to the scene beneath.

10. Nothing on the status panel moves unless agent state changes. Between events, it is fully static.

---

**Commander's Room Computer Prop**

11. The computer on the Commander's desk is a **clickable room object** — a sprite in the Commander's Room scene, visually consistent with other room props. It renders no HUD content, contains no screen readout, and has no animated elements of its own.

12. The prop has a click detection area (e.g., `Area2D` with collision shape) sized to match its sprite bounds. When clicked, it emits a signal (e.g., `computer_interacted`) that the HUD system listens to and responds by opening the detail overlay.

13. The prop must be visually distinguishable as interactive without relying on hover state (web and tablet targets do not support hover-only affordances). The specific affordance mechanism is deferred — see Open Questions.

---

**Detail Overlay**

14. The detail overlay is a **screen-space panel** (CanvasLayer) that opens when the computer prop is clicked. It is non-modal: room scene, ambient animations, beat effects, and signal processing all continue while it is open.

15. The overlay does **not** move the camera. It appears on top of the scene. No camera nudge.

16. The overlay has three fixed **vertical zones**:
   - **Zone 1 — Agent Rows (~25%)**: One compact row per configured agent — glyph, agent ID label, state label. Clicking a row selects that agent and refreshes Zone 3.
   - **Zone 2 — Activity Log (~40%)**: Scrollable list of recent `beat_fired` events, most recent first. Format: `[HH:MM] [agent_id] — task completed`. Mouse wheel scrolls. Capped at `hud_log_max_entries` entries (default 50).
   - **Zone 3 — Profile / Stats (~35%)**: Selected agent's data — `tasks_completed` count (HUD-accumulated) plus any fields returned by `AgentStateMachine.get_agent_stats(agent_id) → Dictionary`. Field-agnostic. Stats refresh on row selection; no live-update while open (MVP constraint).

17. Zone height proportions are tuning knobs — not hardcoded pixel values.

18. **Statistics ownership**:
    - `tasks_completed` per agent: HUD accumulates internally by counting `beat_fired` events per `agent_id`. Not sourced from ASM.
    - All other statistics: `AgentStateMachine.get_agent_stats(agent_id) → Dictionary` on demand.
    - Revenue, payload, and business metrics: deferred to post-prototype.

19. **Input rules for the overlay**:
    - Zone 1 row click: select agent, refresh Zone 3.
    - Mouse wheel: scrolls Zone 2.
    - Click outside the overlay panel rect: closes overlay.
    - Escape: closes overlay from any state.
    - All input blocked during OPENING and CLOSING transitions.

### States and Transitions

**Per-Slot State** (one independent instance per configured slot):

| Slot State | Glyph | Color | Alpha | Entry Condition |
|-----------|-------|-------|-------|----------------|
| EMPTY | ▬ | Neutral `#4A4035` | ~40% | No agent configured for this slot index |
| IDLE | ▬ | Amber `#D4882A` | 1.0 | ASM signals `"idle"` |
| WORKING | ● | Green `#5BAD63` | 1.0 | ASM signals `"working"` |
| COMPLETED | + | Green `#5BAD63` | 1.0 | `beat_fired` received; 1.5 s timer running |
| ERRORED | ● | Sienna `#A03520` | 1.0 | ASM signals `"errored"` |

Data-quality overlays (applied independently of slot state, except EMPTY):

| Overlay | Alpha | Entry Condition |
|---------|-------|----------------|
| STALE | 0.5 | ASM reports STALE connection for this agent |
| DISCONNECTED | 0.25 | ASM reports DISCONNECTED for this agent |
| (none) | 1.0 | Connection healthy |

Transition rules:
- `EMPTY → any`: only on agent added to config (requires restart — hot-reload is post-MVP).
- `IDLE ↔ WORKING`: ASM `agent_state_changed` signal.
- `IDLE or WORKING → COMPLETED`: `beat_fired` received; 1.5 s timer starts.
- `COMPLETED → WORKING`: ASM `"working"` signal during timer, OR timer expires with last-known state WORKING.
- `COMPLETED → ERRORED`: timer expires with last-known state ERRORED → ● Sienna.
- `COMPLETED → IDLE`: timer expires with last-known state IDLE (or unknown).
- `COMPLETED → COMPLETED`: second `beat_fired` before expiry — timer resets to 1.5 s.
- `any (except EMPTY) → ERRORED`: ASM `"errored"` signal.
- `ERRORED → IDLE or WORKING`: ASM recovery signal.
- Data-quality overlays transition independently — a COMPLETED slot can carry a STALE overlay (+ glyph at 0.5 alpha).

**Detail Overlay State Machine:**

| State | Description |
|-------|-------------|
| CLOSED | Overlay not rendered. Computer prop is clickable in the room. |
| OPENING | Overlay appearing (fade-in, ~100–150 ms). Input blocked. |
| OPEN | All three zones visible and interactive. |
| CLOSING | Overlay disappearing (fade-out, ~100–150 ms). Input blocked. |

Transitions: `CLOSED → OPENING` (computer prop clicked) → `OPEN` (fade completes) → `CLOSING` (Escape / click outside) → `CLOSED` (fade completes).

### Interactions with Other Systems

| System | Direction | Interface | Notes |
|--------|-----------|-----------|-------|
| Agent State Machine | ASM → HUD | `agent_state_changed(agent_id: StringName, new_state: StringName)` | Drives per-slot glyph on status panel. **Provisional** — ASM GDD not yet designed. |
| Agent State Machine | HUD → ASM | `get_agent_stats(agent_id: StringName) → Dictionary` | Called on Zone 3 refresh. Field-agnostic. |
| Agent State Machine | ASM → HUD | Connection quality per agent (STALE / DISCONNECTED / healthy) | Mechanism TBD — drives alpha overlays on status panel. |
| Room System | Room System → HUD | `get_all_agent_ids() → Array[StringName]` | Read at `_ready`. Initialises slot grid. |
| Task Completion Beat | TCB → HUD | `beat_fired(agent_id: StringName, timestamp: float)` | Drives COMPLETED glyph, completions strip, `tasks_completed` accumulation. |
| Configuration Loader | Config → HUD | `agents` array + `max_agents = 12` constant | Slots beyond configured agents render as EMPTY. |
| Room System (prop) | Player → Prop → HUD | Computer prop emits signal on click → HUD opens detail overlay | Prop is a room scene object; HUD is a CanvasLayer. They communicate via signal. |
| Audio Manager | None | — | HUD has no audio output. All beat audio is owned by Task Completion Beat. |
| Commander Character | None | — | No dependency in either direction. |

## Formulas

**F1 — Slot Grid Position**

Maps a zero-based slot index N to a (row, col) cell in the 3-column × 4-row grid:

```
row = floor(N / 3)
col = N mod 3
```

Where: `0 ≤ N < max_agents` (max_agents = 12), `0 ≤ row ≤ 3`, `0 ≤ col ≤ 2`.

Slot order is determined by the agent array in `config.json`. The formula is the only spatial logic the HUD contains — all slot positions are derived, never hand-authored.

**F2 — COMPLETED Glyph Timer**

The per-slot countdown timer that drives the `+ → (IDLE | WORKING)` revert:

```
T_completed = BEAT_TOTAL_SEC   [default: 1.5 s]
```

Where `BEAT_TOTAL_SEC` is the Task Completion Beat GDD's tuning knob `BEAT_TOTAL_SEC`. The HUD timer **must equal** this value — they describe the same beat window from two sides (TCB controls duration of the visual beat in the room; HUD controls duration of the + glyph). If `BEAT_TOTAL_SEC` is retuned in TCB, the HUD timer must be updated to match. This cross-system dependency is registered in the entity registry as `beat_total_seconds`.

**F3 — Data-Quality Alpha**

Alpha applied to the current slot glyph based on ASM connection quality:

```
α = 1.0    (connection healthy)
α = 0.5    (STALE — hud_stale_alpha, default 0.5)
α = 0.25   (DISCONNECTED — hud_disconnected_alpha, default 0.25)
α = hud_empty_slot_alpha   (EMPTY slot — default 0.4, applied to neutral-dim ▬)
```

All four alpha values are tuning knobs. The DISCONNECTED value (`0.25`) is intentionally low — the glyph should read as "barely there" to communicate broken trust while still preserving color identity for when connection restores.

**F4 — Detail Panel Zone Heights**

Divides the total panel height `H` into three contiguous zones:

```
H_Z1 = H × zone_1_fraction   [default: 0.25]
H_Z2 = H × zone_2_fraction   [default: 0.40]
H_Z3 = H × zone_3_fraction   [default: 0.35]

Constraint: zone_1_fraction + zone_2_fraction + zone_3_fraction = 1.0
```

The three fractions are tuning knobs. Implementation must enforce the constraint: if any fraction is changed, the others must be adjusted to keep the sum at 1.0. `H` is the rendered pixel height of the detail panel, determined by the scene layout.

## Edge Cases

**EC-1: beat_fired arrives for an ERRORED agent**

An agent completes a task (`beat_fired` fires) while ASM state is ERRORED. `beat_fired` takes precedence — slot switches to `+` green for 1.5 s. On timer expiry, the slot reverts to the current ASM state: if ERRORED → ● Sienna; if WORKING → ● green; if IDLE → ▬ amber. The timer revert logic checks all three states explicitly, not just WORKING vs. "otherwise idle."

**EC-2: beat_fired for an unrecognised agent_id**

`beat_fired` carries an `agent_id` not present in the configured agent list. HUD ignores the event and emits a `push_warning()`. No slot is modified. No completions strip entry is created. This can occur if config and TCB subscriptions are out of sync at startup.

**EC-3: STALE or DISCONNECTED overlay arrives during COMPLETED timer**

Data quality degrades while a `+` glyph is active. Both effects apply simultaneously: the `+` glyph renders at overlay alpha (0.5 STALE, 0.25 DISCONNECTED). When the timer expires, the slot reverts to the last-known ASM state glyph — also at overlay alpha. Overlay state is independent of the COMPLETED timer; they do not cancel each other.

**EC-4: Zero agents configured**

All 12 slots render as EMPTY (▬ neutral-dim at 40% alpha). Completions strip is empty. Zone 2 in the detail view shows an empty-state label ("No activity yet"). Zone 3 shows nothing (no agent to select). HUD is valid and non-crashing with zero agents.

**EC-5: Only one agent configured**

Slot 0 (top-left) renders as a live glyph. Slots 1–11 render as EMPTY. The grid is visually sparse but functionally correct. No layout changes are applied — empty slots are a designed affordance that communicates available capacity.

**EC-6: Initial state sync at _ready**

Signals are subscribed in `_ready`. Any state-change signals emitted before `_ready` completes would be missed. On `_ready`, the HUD must perform a sync pass: query the current ASM state for each configured agent and set each slot's initial glyph without animation. This ensures the display is correct immediately on scene load, not merely after the next state-change signal fires.

**EC-7: Detail view opens with no activity history**

Zone 2 (activity log) is empty on first launch. Display a non-interactive label: *"No task completions recorded this session."* No error is raised.

**EC-8: Zone 2 scroll position on re-open**

When the detail view closes and reopens, Zone 2 scroll resets to the top (most recent entries visible first). Preserving scroll position across open/close cycles is post-MVP.

**EC-9: beat_fired during detail overlay OPENING or CLOSING transition**

Signal processing is not gated on detail view state. `beat_fired` arriving mid-transition updates the slot glyph immediately and appends to the completions strip. Transitions do not delay or buffer signal handling.

**EC-10: Rapid successive beat_fired for the same agent**

Each `beat_fired` resets the COMPLETED timer to 1.5 s (Rule 6d). If an agent completes tasks faster than the 1.5 s window, the `+` glyph remains continuously active. The strip appends each event regardless — rapid completions produce multiple entries. This is valid and desirable: strip throughput communicates agent productivity.

**EC-11: get_agent_stats returns an empty dictionary**

ASM returns `{}` for an agent. Zone 3 shows only the HUD-accumulated `tasks_completed` count. No other fields are rendered. No error is raised — field-agnostic rendering handles the empty case by rendering nothing beyond what the HUD itself owns.

## Dependencies

**Upstream — systems the Commander's Room HUD depends on:**

| System | What the HUD Consumes | Notes |
|--------|----------------------|-------|
| Agent State Machine | Signal `agent_state_changed(agent_id, new_state)` for glyph updates; method `get_agent_stats(agent_id) → Dictionary` for Zone 3 stats | **Provisional** — ASM GDD not yet designed. Signal name, state string vocabulary, and connection-quality reporting mechanism may change. |
| Task Completion Beat | Signal `beat_fired(agent_id, timestamp)` | Drives COMPLETED glyph, completions strip, and `tasks_completed` accumulation. Constant `beat_total_seconds = 1.5 s` must stay in sync with TCB's `BEAT_TOTAL_SEC` tuning knob. |
| Room System | `get_all_agent_ids() → Array[StringName]` (or equivalent) | Read at `_ready` to initialise slot grid. Slot count and order must match the `agents` array in `config.json`. Must use `commanders_room_id = "commander"` constant — never hardcoded. |
| Configuration Loader | `agents` array (ordered list of configured agents), `max_agents = 12` constant | Read at startup. Determines grid size and EMPTY slot count. |

**Downstream — systems that depend on the Commander's Room HUD:**

None. The Commander's Room HUD is the terminal node of the Presentation Layer. No other system reads from it or subscribes to signals it emits.

**Registry constants this GDD must agree with:**

| Constant | Value | Owner GDD | Constraint on HUD |
|----------|-------|-----------|-------------------|
| `max_agents` | 12 | configuration-loader.md | Grid must have exactly 12 slots. |
| `beat_total_seconds` | 1.5 s | task-completion-beat.md | COMPLETED timer must equal this value. |
| `commanders_room_id` | `"commander"` | room-system.md | Must never hardcode the room ID string. |
| `max_poll_retries` | 4 | data-bridge.md | DISCONNECTED overlay is declared after this many consecutive failures — HUD must not use a different threshold. |
| `completed_beat_duration_seconds` | 2.0 s | agent-character-controller.md | Upper bound for the beat window; `beat_total_seconds` (1.5 s) must remain ≤ this value. |

**Bidirectionality note:** The Task Completion Beat GDD lists the Commander's Room HUD as a downstream consumer of `beat_fired`. That dependency is documented in the TCB GDD's Interactions section (Open Question OQ-8 covers the case where no HUD subscriber exists). The two GDDs are consistent.

## Tuning Knobs

| Knob | Default | Safe Range | Gameplay Aspect Affected |
|------|---------|------------|--------------------------|
| `hud_completion_strip_size` | 6 | 3–12 | Number of recent completion entries visible on the primary display strip. Larger values show more history at a glance but compress the strip vertically; smaller values lose context. Must fit within the primary display rect. |
| `hud_completed_timer_sec` | 1.5 s | — | Duration of the `+` COMPLETED glyph before reverting. **Must equal `beat_total_seconds` (1.5 s) at all times.** Do not tune independently — retune via `BEAT_TOTAL_SEC` in the Task Completion Beat GDD and update both together. |
| `hud_stale_alpha` | 0.5 | 0.3–0.7 | Alpha of the current glyph when ASM connection is STALE. Below 0.3: glyph reads as near-invisible, losing color identity. Above 0.7: STALE barely distinguishable from healthy. |
| `hud_disconnected_alpha` | 0.25 | 0.1–0.4 | Alpha when ASM connection is DISCONNECTED. Must remain visibly lower than `hud_stale_alpha` to maintain a clear two-tier degradation signal. |
| `hud_empty_slot_alpha` | 0.4 | 0.2–0.6 | Alpha of the neutral-dim ▬ in unconfigured EMPTY slots. Should be clearly dimmer than the IDLE ▬ at full alpha to avoid confusion between "no agent" and "idle agent." |
| `hud_panel_anchor` | `bottom_right` | `top_left`, `top_right`, `bottom_left`, `bottom_right` | Screen corner where the status panel is anchored. Must not obstruct primary scene content at default viewport resolution. |
| `hud_panel_margin_px` | 8 | 4–24 | Pixel gap between the status panel edge and the screen boundary. |
| `hud_overlay_fade_duration_sec` | 0.12 | 0.05–0.25 | Duration of the detail overlay fade-in and fade-out. Below 0.05 s: snaps jarringly. Above 0.25 s: feels sluggish. |
| `hud_log_max_entries` | 50 | 20–200 | Maximum scroll depth for Zone 2 (activity log). Entries beyond this limit are dropped (oldest first). Caps memory; rarely relevant unless an agent completes many tasks per session. |
| `zone_1_fraction` | 0.25 | 0.15–0.35 | Zone 1 (agent rows) height as a fraction of total panel height. Constraint: `zone_1_fraction + zone_2_fraction + zone_3_fraction = 1.0` must hold at all times. |
| `zone_2_fraction` | 0.40 | 0.30–0.50 | Zone 2 (activity log) height fraction. Scroll provides depth, so this zone can be relatively compact without losing information. |
| `zone_3_fraction` | 0.35 | 0.25–0.45 | Zone 3 (profile/stats) height fraction. Must accommodate at least `tasks_completed` + 3–5 stat fields at minimum legible font size. |

## Visual/Audio Requirements

**Visual — Screen-Edge Status Panel**

*Form and placement:*
The status panel is a screen-space UI element anchored to a screen corner (default: bottom-right). It renders as a compact, bordered terminal surface using the project's "Institutional Underground" aesthetic: dark background, bitmap font, no decorative chrome. It must be small enough not to obscure significant scene area at the default viewport resolution.

*Screen palette:*
All panel rendering uses the locked project color system. No new colors:

| Element | Color | Hex | Notes |
|---------|-------|-----|-------|
| Panel background | Void Black | `#0A0A0F` | Dark terminal background; creates contrast for all glyphs |
| WORKING / COMPLETED glyph | Active Green | `#5BAD63` | Locked palette |
| IDLE glyph | Amber | `#D4882A` | Locked palette |
| ERRORED glyph | Sienna | `#A03520` | Locked palette |
| EMPTY slot glyph | Institutional Grey-Warm | `#4A4035` | At `hud_empty_slot_alpha` (~40%) — must read clearly dimmer than IDLE ▬ |
| Completions strip text | Amber | `#D4882A` | Strip records past events — amber matches the "at rest" register |
| Panel border | Institutional Grey-Warm | `#4A4035` | Thin 1-px border only; no shadows or gradients |

*Typography:*
All text uses the project's locked bitmap font (5×7 px). No other typeface. Glyph characters (●, ▬, +) must be available in the chosen bitmap font or substituted with the closest pixel-art equivalent. All text must remain pixel-crisp — no anti-aliasing.

*Glyph grid:*
3×4 grid with consistent cell spacing. Each glyph cell must be legible at panel scale without zoom. No labels beside the glyphs in the primary panel — color and character communicate state alone.

*Completions strip:*
Compact strip adjacent to the glyph grid. Each entry: `[HH:MM] [agent_id]` in bitmap font. Purely typographic — no icons or glyphs in the strip.

---

**Visual — Commander's Room Computer Prop**

The computer prop is art direction, not HUD design. It should:
- Read as a computer/terminal in context without being visually dominant — just another piece of bunker furniture.
- Have no rendered screen content, no glow, no animated readout.
- Carry a subtle interactive affordance that works without hover (specific mechanism is an open question — see Open Questions).

The prop is designed and owned by the Art team following the Art Bible. The HUD system only cares that the prop has a click detection area and emits the correct signal.

---

**Visual — Detail Overlay**

The detail overlay uses the same terminal palette as the status panel. It is a larger screen-space panel appearing over the scene — flat dark background, opaque, 1-px borders. No blur, no backdrop filter, no drop shadows. Zone separator lines use `#4A4035`. All text in bitmap font (5×7 px). Long agent IDs truncate with `…` — no word wrap.

---

**Audio**

The Commander's Room HUD (both the status panel and the detail overlay) has **no audio output of its own.** All completion sounds are owned by the Task Completion Beat system. Panel open and close interactions are currently silent (MVP). If overlay interaction sounds are desired later, they belong to the Audio Manager's SFX bus — see Open Questions.

## UI Requirements

**Screen-Edge Status Panel**

- Implemented as a `CanvasLayer` with a high layer index so it renders above all scene content.
- Anchored to a screen corner via `hud_panel_anchor` (default: bottom-right). Margin from screen edge: `hud_panel_margin_px` (default: 8 px). Both are tuning knobs.
- The panel is **display-only**: it receives no mouse or keyboard input. All input events pass through it to the scene beneath (`mouse_filter = MOUSE_FILTER_IGNORE` on all panel nodes).
- No hover states. The panel must be visually self-explanatory at rest. Web and tablet targets do not support hover-only affordances.
- Alpha changes (STALE/DISCONNECTED overlays) are applied per-slot, not globally. Each slot node controls its own `modulate.a` independently.
- The COMPLETED timer is a per-slot `Timer` node (or equivalent). Each slot manages its own timer independently — they do not share a global countdown.

**Commander's Room Computer Prop**

- A room scene object (Sprite2D + Area2D, or similar) on the Commander's desk within the Commander's Room scene.
- The click detection area must precisely match the visible sprite region — transparent and margin pixels must not register clicks.
- On click, emits a signal consumed by the HUD system. The prop does not open the overlay itself; it delegates via signal.
- Must have an interactive affordance that works without hover. Candidates (deferred to Open Questions): cursor change on pointer enter, a subtle ambient animation, or a proximity label. All options must function on web/tablet.

**Detail Overlay**

- Implemented as a second `CanvasLayer` (or a Control child shown/hidden) rendering above the status panel.
- Positioned at a fixed location on screen (centered, or offset toward the computer prop — tuning knob or scene-defined).
- Flat `Panel` or `ColorRect` with child `Control` nodes for the three zones. No `SubViewport`.
- Zone 1 rows are individually clickable (`Button` or equivalent with `MOUSE_FILTER_STOP` — not hover-dependent).
- Zone 2 scroll: `ScrollContainer` capturing wheel events. No scroll bar widget required for MVP.
- Zone 3: `VBoxContainer` of label nodes; non-interactive (`MOUSE_FILTER_IGNORE`).
- Click-outside detection: a full-screen transparent `ColorRect` behind the overlay captures click events and closes the overlay. Active only while OPEN.
- Escape key handled globally (not restricted to overlay focus).
- Input fully blocked during OPENING and CLOSING fade transitions to prevent double-triggering.

## Acceptance Criteria

**AC Group 1 — Panel Initialization**

| # | AC | Pass Condition |
|---|-----|---------------|
| 1 | Status panel visible on load | Panel renders at the correct screen corner within 1 frame of scene load. No flash or delayed appearance. |
| 2 | Initial slot sync | Each configured agent slot displays the correct glyph for its current ASM state immediately on `_ready`. Does not wait for the next state-change signal. |
| 3 | EMPTY slots render correctly | All slots beyond the configured agent count show ▬ neutral-dim `#4A4035` at ~40% alpha. |

**AC Group 2 — Glyph State Transitions**

| # | AC | Pass Condition |
|---|-----|---------------|
| 4 | IDLE glyph | On ASM `agent_state_changed(id, "idle")`: slot shows ▬ amber `#D4882A` at 1.0 alpha. |
| 5 | WORKING glyph | On ASM `agent_state_changed(id, "working")`: slot shows ● green `#5BAD63` at 1.0 alpha. |
| 6 | ERRORED glyph | On ASM `agent_state_changed(id, "errored")`: slot shows ● sienna `#A03520` at 1.0 alpha. |

**AC Group 3 — COMPLETED Timer**

| # | AC | Pass Condition |
|---|-----|---------------|
| 7 | COMPLETED glyph appears | On `beat_fired(id, t)`: slot immediately shows `+` green `#5BAD63`. |
| 8 | COMPLETED → IDLE revert | After 1.5 s with no interrupting signals (last-known state IDLE): slot reverts to ▬ amber. |
| 9 | COMPLETED → WORKING revert | Timer expires with last-known state WORKING: slot reverts to ● green. |
| 10 | COMPLETED → ERRORED revert | Timer expires with last-known state ERRORED: slot reverts to ● sienna. |
| 11 | Timer reset on second beat | Second `beat_fired` before expiry: slot remains `+` green; timer resets to 1.5 s from reset moment. |
| 12 | ASM working overrides timer | ASM `"working"` signal during COMPLETED window: timer cancels immediately; slot shows ● green. |

**AC Group 4 — Data-Quality Overlays**

| # | AC | Pass Condition |
|---|-----|---------------|
| 13 | STALE overlay | STALE signal for agent X: slot glyph renders at 0.5 alpha; glyph character and color unchanged. |
| 14 | DISCONNECTED overlay | DISCONNECTED signal for agent X: slot glyph renders at 0.25 alpha; glyph character and color unchanged. |
| 15 | Overlay independence | STALE arrives during COMPLETED timer: `+` glyph shows at 0.5 alpha; timer continues; revert on expiry also at 0.5 alpha. |
| 16 | Overlay recovery | Healthy-connection signal restores slot to 1.0 alpha. |

**AC Group 5 — Completions Strip**

| # | AC | Pass Condition |
|---|-----|---------------|
| 17 | Strip appends on beat | Each `beat_fired` prepends `[HH:MM] [agent_id]` to strip; entry appears immediately. |
| 18 | Strip cap enforced | When strip exceeds `hud_completion_strip_size`: the oldest entry is removed. Strip never exceeds the cap. |

**AC Group 6 — Computer Prop Interaction**

| # | AC | Pass Condition |
|---|-----|---------------|
| 19 | Prop opens overlay | Clicking computer prop in Commander's Room: detail overlay appears (fade-in ≤ `hud_overlay_fade_duration_sec`). |
| 20 | Prop re-click is safe | Clicking prop while overlay is already OPEN or mid-transition: no double-open, no crash. |
| 21 | Panel pass-through | Clicking through the screen-edge status panel area: input reaches the scene beneath; no panel interaction fires. |

**AC Group 7 — Detail Overlay**

| # | AC | Pass Condition |
|---|-----|---------------|
| 22 | Zone 1 population | Overlay opens: Zone 1 shows one row per configured agent with correct glyph, agent ID, and state label. |
| 23 | Zone 3 refresh on row click | Clicking a Zone 1 row: Zone 3 updates to show that agent's `tasks_completed` count and any fields from `get_agent_stats`. |
| 24 | Zone 2 log order | Zone 2 shows `beat_fired` events most-recent-first. |
| 25 | Zone 2 scroll | Mouse wheel scrolls Zone 2. Does not scroll Zone 1 or Zone 3. |
| 26 | Escape closes overlay | Escape key while OPEN: overlay closes (fade-out ≤ `hud_overlay_fade_duration_sec`). |
| 27 | Click-outside closes overlay | Click anywhere outside the overlay panel rect while OPEN: overlay closes. |
| 28 | Room non-modal | Ambient animations, beat effects, and `beat_fired` signal processing continue normally while overlay is OPEN. |

**AC Group 8 — Graceful Degradation**

| # | AC | Pass Condition |
|---|-----|---------------|
| 29 | Unknown agent_id ignored | `beat_fired` with unrecognised `agent_id`: HUD ignores it; `push_warning()` emitted; no slot modified; no crash. |
| 30 | Empty stats dict handled | `get_agent_stats` returns `{}`: Zone 3 shows only `tasks_completed`; no crash; no error label. |
| 31 | Zero agents configured | All 12 slots render EMPTY; strip shows no entries; overlay Zone 2 shows "No task completions recorded this session."; no crash. |

**AC Group 9 — Always-On Behaviour**

| # | AC | Pass Condition |
|---|-----|---------------|
| 32 | Panel visible in all rooms | Status panel remains visible when the camera is in any room, not only the Commander's Room. |
| 33 | Panel is always-on | No user action, game state, or room transition causes the status panel to hide or disappear. |

## Open Questions

**OQ-1: ASM provisional interface (BLOCKING for implementation)**

The Agent State Machine GDD is not yet designed. The signal names (`agent_state_changed`), state string vocabulary (`"idle"`, `"working"`, `"errored"`), and connection-quality reporting mechanism (STALE/DISCONNECTED) are all provisional. When the ASM GDD is authored, review this GDD against it and resolve any interface mismatches before implementation begins.

**OQ-2: Computer prop interactive affordance**

The computer prop must be recognisably clickable without hover-only affordances (web/tablet constraint). Candidates:
- **Cursor change** on `Area2D` pointer enter — works on web if the browser honours CSS cursor; may not work in all Godot web export configurations.
- **Proximity label** — a small "Interact" label that appears when the player is near the desk.
- **Subtle ambient animation** — a blinking cursor on the prop sprite, or a soft pulse on the monitor frame.

Which approach fits the "Institutional Underground" aesthetic without over-signalling? To be decided with Art Director before prop art is produced.

**OQ-3: Detail overlay position and size**

The spec says the overlay is "centered or offset toward the computer prop." Final position and dimensions must be established in prototype — they depend on room layout, viewport resolution, and how much scene area the overlay should obscure. Should the overlay slide in from a screen edge or appear in place?

**OQ-4: ASM connection-quality reporting mechanism**

The HUD requires per-agent STALE/DISCONNECTED state to apply alpha overlays. The mechanism is unresolved: it could be a second signal (`agent_connection_changed(id, quality)`), a polled property, or an extra parameter on `agent_state_changed`. To be resolved in the ASM GDD design session.

**OQ-5: Zone 2 live updates while overlay is open**

Current MVP spec: Zone 2 does not live-append new `beat_fired` events while the overlay is open. A user watching the overlay will not see completions appear in real time — they must close and reopen to see new entries. Is this acceptable for MVP, or should Zone 2 live-update? If live, scroll position behaviour must also be specified (new entries at top vs. pinning to current scroll position).

**OQ-6: Overlay interaction sounds (post-MVP)**

Panel open and close are currently silent. If UI sounds are added — a soft terminal click, a mechanical keyboard tap — they would route to Audio Manager's SFX bus at `−12 dB`. Tone and volume deferred to a post-MVP audio design session.

**OQ-7: hud_completed_timer_sec drift guard**

`hud_completed_timer_sec` must always equal `beat_total_seconds = 1.5 s`. If `BEAT_TOTAL_SEC` is retuned in the TCB GDD in the future, the HUD knob will silently drift. Should implementation include a debug assertion (`assert(hud_completed_timer_sec == TaskCompletionBeat.BEAT_TOTAL_SEC)`)? Or should the HUD read `BEAT_TOTAL_SEC` directly from TCB, eliminating the separate knob?

**OQ-8: Post-prototype business metrics in Zone 3**

Revenue, payload volume, and other business metrics depend on what real API payload fields the Data Bridge prototype surfaces. These cannot be designed until the prototype answers Data Bridge GDD open questions 4 and 5. At that point, Zone 3 should be revisited to specify which fields display, in what format, and with what labels.
