# Task Completion Beat

> **Status**: Designed — pending /design-review in fresh session
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Pillar 3 — Satisfying Feedback
> **⚠ PROVISIONAL**: Agent State Machine GDD not yet complete. Room node resolution interface remains provisional pending ASM GDD. Signal source resolved by ADR-0005 (AgentStateMachine is the sole emitter of task_completed). `agent_type` resolution finalized 2026-05-11 — see Open Questions §2 + §3.

## Overview

The Task Completion Beat is the satisfaction layer for every agent task that finishes successfully. When the Agent State Machine signals that a task has completed, the Task Completion Beat subscribes to that event, resolves the appropriate audio stream from its internal `AgentSoundRegistry` (which maps each agent type to a distinct completion sound), and calls `AudioManager.play_sfx(stream)` to land the beat. Simultaneously, it triggers a brief visual pulse at the room level — overlaying the character's own completion animation, which the Agent Character Controller owns independently — and records the event by emitting a `beat_fired(agent_id: String, timestamp: float)` signal that the Commander's Room HUD uses to populate its recent completions panel. The player experiences this as a small, clean, deliberate moment: not fanfare — consequence. Something that was running has finished. The bunker registered it.

## Player Fantasy

Something completed. The room knows it, and now you know it. The tone is brief and exact — the kind of sound a well-built machine makes when a switch lands home. For two seconds the room glows, your agent does its small private celebration, and then everything settles back to amber idle. Each beat is a discrete thing: a latch clicking shut, a file stamped closed, one more job accounted for. The bunker confirms, in its own quiet language, that it is doing the work.

Over a session the beats begin to compose. Tasks finish at their own pace and you start to hear the rhythm — one here, a pause, two close together when the team is in flow. You begin to recognize the tones: that's the writer, that's the analyst. You weren't listening for them, but you learned them. The bunker isn't waiting for you to pay attention; it's working, and the rhythm of small completions becomes the texture of a productive afternoon. Each click is individual. The pattern across an hour is something else — the sound of agents doing exactly what you built them to do.

## Detailed Design

### Core Rules

1. **Stateless event responder.** The Task Completion Beat has no persistent game state. It is a pure signal subscriber: it receives `task_completed(agent_id)`, executes a one-shot beat sequence, and immediately returns to idle. Multiple simultaneous beats run as independent one-shot sequences on separate room nodes — no queue, no cooldown, no coordination.

2. **Beat sequence (all actions fire at t=0 — the frame the signal is received):**
   1. Resolve `agent_type: String` from `agent_id` via `ConfigurationLoader.get_agent(agent_id).get(&"agent_type", "default")`.
   2. Resolve `AudioStream` from `AgentSoundRegistry[agent_type]`. If no entry: fall back to `AgentSoundRegistry["default"]`. If no default: skip audio + `push_warning("TCB: no stream for agent_type [x] and no default registered")`.
   3. Call `AudioManager.play_sfx(stream)` — audio begins this frame.
   4. Emit `beat_fired(agent_id: String, timestamp: float)` — timestamp is `Time.get_unix_time_from_system()`.
   5. Retrieve the completing agent's room Node2D and begin the room modulate Tween (Rule 3).

3. **Room modulate Tween shape.** The Tween targets the completing agent's room root Node2D's `modulate` property. Three-phase shape:

   | Phase | Duration | `modulate` value |
   |---|---|---|
   | Attack (ramp up) | 0.3 s | Neutral `Color(1, 1, 1, 1)` → peak `Color(1.15, 1.35, 1.15, 1.0)` |
   | Hold (at peak) | 0.5 s | `Color(1.15, 1.35, 1.15, 1.0)` — sustained green-warm lift |
   | Decay (ramp down) | 0.7 s | Peak → neutral `Color(1, 1, 1, 1)` |
   | **Total** | **1.5 s** | Within the 2.0 s window owned by ACC's `COMPLETED_BEAT` state |

   The peak color (`Color(1.15, 1.35, 1.15, 1.0)`) produces a ~40% luminance boost with a green-warm bias. It shifts the room from its ambient amber-toned idle toward the active-green of the status palette without becoming a flat green overlay.

4. **Additive to existing visual systems.** The room modulate Tween is additive to — and independent of — all other visual responses on the same frame:
   - **ACC's** `completed` character animation (ACC subscribes independently to the same signal; character reaction is ACC's domain).
   - **AAL's** COMPLETED prop state (AAL fires a white flash on ambient props for 0.5 s; this is a prop-level micro-event within the room's rising green lift). The AAL props flash white inside a room that is brightening green — the effects layer without coordination.
   No cross-system method calls are needed. Each system responds to the shared signal and applies its effect to its own nodes.

5. **AgentSoundRegistry.** TCB owns an `AgentSoundRegistry` — a lookup table mapping `agent_type: StringName → AudioStream`. Streams are preloaded at scene startup. A `"default"` key is always required (missing default is a startup error, not a warning). Asset path convention: `assets/audio/sfx/completion/[agent_type].ogg` for type-specific beats; `assets/audio/sfx/completion/default.ogg` for the fallback. *(The exact data structure — Dictionary vs. Resource subclass — is an implementation choice; it belongs in an ADR.)*

6. **Per-room, independent Tweens.** When multiple agents complete simultaneously, each room runs its own modulate Tween independently. There is no bunker-wide pulse. Multiple rooms brightening simultaneously reads as "team in flow" while preserving the spatial contrast that makes individual completions legible (one bright room among dim ones).

7. **Same-room Tween collision.** If a new `task_completed` signal arrives for an agent whose room modulate Tween is already running, the existing Tween is killed and a new Tween begins from the room's current `modulate` value toward peak. This produces a "double-tap" lift without resetting to neutral first, and without visual glitching.

8. **Audio pool pass-through.** TCB always calls `AudioManager.play_sfx(stream)` unconditionally. The Audio Manager handles pool exhaustion (8-slot pool, silent drop at overflow). TCB has no concurrent-beat counting logic — that is entirely the Audio Manager's domain.

9. **Commander's Room HUD data contract.** `beat_fired(agent_id: String, timestamp: float)` is the complete signal TCB emits. TCB does not own the HUD, the recent completions panel, or any display formatting. The HUD subscribes and is responsible for rendering.

10. **Room node resolution.** To apply the modulate Tween, TCB needs a reference to the completing agent's room root Node2D. *(Provisional: exact interface TBD pending Room System GDD expansion — likely `RoomSystem.get_room_id_for_agent(agent_id)` followed by a scene-tree group lookup, e.g., nodes in the `"bunker_rooms"` group with a matching `room_id` property.)*

---

### States and Transitions

None. The Task Completion Beat is stateless. It has no internal states, no per-agent flags, and no per-room flags. All lifecycle management is delegated to Godot's Tween system (which tracks active/complete state natively) and the Audio Manager's pool.

---

### Interactions with Other Systems

| System | Direction | Interface | Notes |
|---|---|---|---|
| **Agent State Machine** *(provisional)* | → TCB | `task_completed(agent_id: String)` | Primary trigger. Provisional — review after ASM GDD |
| **Configuration Loader** | → TCB | `ConfigurationLoader.get_agent(agent_id) → Dictionary` | TCB reads `agent_type` field from the dict (default `"default"`) to resolve the registry key |
| **Room System** | → TCB | Room Node2D resolution — interface provisional | Required to apply modulate Tween to the correct room |
| **Audio Manager** | TCB → | `AudioManager.play_sfx(stream: AudioStream) → void` | TCB passes preloaded stream; Audio Manager is stream-agnostic |
| **Commander's Room HUD** | TCB → | `beat_fired(agent_id: String, timestamp: float)` signal | HUD subscribes for its recent completions panel |

## Formulas

**F1 — Beat Total Duration**

```
T_total = T_attack + T_hold + T_decay
```

| Variable | Constant Name | Value | Description |
|---|---|---|---|
| `T_attack` | `BEAT_ATTACK_SEC` | 0.3 s | Ramp from neutral modulate to peak |
| `T_hold` | `BEAT_HOLD_SEC` | 0.5 s | Sustained at peak modulate |
| `T_decay` | `BEAT_DECAY_SEC` | 0.7 s | Return from peak to neutral modulate |
| `T_total` | `BEAT_TOTAL_SEC` | 1.5 s | Full beat duration |

**Constraint**: `T_total` must remain ≤ `completed_beat_duration_seconds` (2.0 s, owned by `agent-character-controller.md`). Current value: 1.5 s. The remaining 0.5 s reserve allows the ACC's character animation to complete and transition to `IDLE_WANDERING` before the beat window officially closes.

*Example*: If `BEAT_DECAY_SEC` is tuned up to 1.0 s, `T_total` = 1.8 s — still within budget. If tuned to 1.5 s, `T_total` = 2.3 s — **exceeds budget**. Clamp `T_decay` to ≤ 1.2 s.

---

**F2 — Room Modulate Interpolation**

```
attack:  modulate(t) = lerp(C_neutral, C_peak,    ease(t / T_attack))
hold:    modulate(t) = C_peak
decay:   modulate(t) = lerp(C_peak,    C_neutral,  ease((t − T_attack − T_hold) / T_decay))
```

| Variable | Value | Description |
|---|---|---|
| `C_neutral` | `Color(1.0, 1.0, 1.0, 1.0)` | Room modulate at rest — renders all colors as authored |
| `C_peak` | `Color(1.15, 1.35, 1.15, 1.0)` | Green-warm luminance peak — ~40% luminance boost, green channel elevated 20 pp above red/blue |
| `ease` | `TRANS_SINE / EASE_IN_OUT` | Godot Tween easing applied to both attack and decay phases |

*Example*: Amber ambient tile `Color(0.83, 0.53, 0.16, 1.0)` at peak modulate `Color(1.15, 1.35, 1.15, 1.0)` → rendered as `Color(0.955, 0.716, 0.184, 1.0)` — a warm golden-green. Full white surfaces clamp to white; the green shift is visible only on mid-range colors. Net effect: the amber bunker warms and greens without blowing out.

**Constraint check**: `T_total` = 1.5 s ≤ `completed_beat_duration_seconds` = 2.0 s ✅

## Edge Cases

**E1 — No audio stream registered for agent_type, no default either**
The `AgentSoundRegistry` lookup for `agent_type` returns `null`. The fallback lookup for `"default"` also returns `null`. TCB skips the `play_sfx()` call entirely, emits `push_warning("TCB: no stream for agent_type [x] and no default registered")`. The visual beat and `beat_fired` signal both fire normally. During development, if a new agent type is added before its sound file is produced, the system degrades gracefully — a warning in the console, not a crash.

**E2 — Multiple agents in the same room complete simultaneously (same frame)**
Two `task_completed` signals arrive on the same frame for agents in the same room. The first creates a Tween from neutral toward peak. The second kills the first and creates a new one from the current modulate value — which is still at or near neutral since the first Tween hadn't yet run. Net result: one Tween from effectively neutral. Visually identical to a single completion. No glitch.

**E3 — Same-room rapid succession (second beat within the Tween window)**
A second agent in the same room completes 0.6 s after the first — while the room is near peak. The existing Tween is killed. A new Tween starts from the room's current elevated modulate value toward peak. The room re-peaks without resetting to neutral first. Reads as "two events, same location" — a mild double-tap that is accurate, not a glitch.

**E4 — Audio pool overflow (many simultaneous completions)**
TCB always calls `play_sfx()` regardless of concurrent beat count. If the Audio Manager's pool is saturated (all 8 slots busy), it silently drops the sound and logs a `push_warning`. The visual beat fires for all agents regardless. TCB does not compensate for dropped sounds — that is the Audio Manager's concern.

**E5 — Task completes while the game is muted**
The Audio Manager applies the mute transparently — `play_sfx()` is called normally but no sound is heard. The visual beat and `beat_fired` signal fire normally. TCB has no awareness of mute state.

**E6 — Room node not resolved (room not yet spawned or agent has no room assignment)**
If the room Node2D lookup fails at beat-fire time, TCB skips the modulate Tween and emits `push_warning("TCB: could not resolve room node for agent [x] — visual beat skipped")`. Audio and `beat_fired` signal still fire. The completion is still audible and recorded by the HUD — just without the room visual.

**E7 — Agent removed from config while its room modulate Tween is running**
If the room Node2D is freed mid-Tween, Godot 4's Tween detects the dead reference and stops cleanly. No crash. *(VERIFY: Godot 4.6.2 Tween behavior on freed node reference — add to project VERIFY list.)*

**E8 — `beat_fired` signal emitted with no subscribers**
If the Commander's Room HUD is not yet instantiated or has not connected to `beat_fired`, the emit is a no-op in Godot's signal system. No crash, no error.

## Dependencies

### Upstream (what Task Completion Beat depends on)

| System | Status | What TCB needs |
|---|---|---|
| **Agent State Machine** *(provisional)* | 🔴 Not designed | `task_completed(agent_id: String)` signal — primary trigger. TCB subscribes to this signal on startup. *(Review this interface after ASM GDD is written.)* |
| **Configuration Loader** | ✅ Designed | `ConfigurationLoader.get_agent(agent_id) → Dictionary` — TCB reads the `agent_type` field (default `"default"` if absent) to resolve the `AgentSoundRegistry` key. Must be callable at signal receipt time (i.e., during gameplay, not just at startup). |
| **Room System** | ✅ Designed | Room Node2D resolution: TCB needs to retrieve the root Node2D for a given agent's assigned room to apply the modulate Tween. *(Provisional — Room System GDD may need expansion to expose `get_room_node_for_agent(agent_id) → Node2D` or equivalent.)* |
| **Audio Manager** | ✅ Designed | `AudioManager.play_sfx(stream: AudioStream) → void` — called to play the completion beat. Must be initialized as an Autoload before TCB's first signal can fire. |

### Downstream (systems that depend on Task Completion Beat)

| System | Priority | What it needs from TCB |
|---|---|---|
| **Commander's Room HUD** | MVP | `beat_fired(agent_id: String, timestamp: float)` signal — the HUD subscribes to populate its recent completions panel. TCB emits the raw event; the HUD owns all display logic. |

### Internal asset dependencies

| Asset | Required | Failure mode |
|---|---|---|
| `assets/audio/sfx/completion/default.ogg` | **Mandatory** — must exist at startup | Startup error if missing; no graceful fallback for the fallback |
| `assets/audio/sfx/completion/[agent_type].ogg` | Per registered agent type | Missing type-specific file falls back to `default.ogg` gracefully |

## Tuning Knobs

| Knob | Constant Name | Default | Safe Range | Affects |
|---|---|---|---|---|
| Tween attack duration | `BEAT_ATTACK_SEC` | 0.3 s | 0.1–0.5 s | Speed of the room's rise to peak. Below 0.1 s reads as a flash, not a lift. Above 0.5 s the peak arrives too slowly to feel like a response. |
| Tween hold duration | `BEAT_HOLD_SEC` | 0.5 s | 0.2–1.0 s | How long the room stays at peak luminance. Below 0.2 s the green state is barely perceptible. Above 1.0 s the hold outlasts the character animation and the room lingers awkwardly after the agent has moved on. |
| Tween decay duration | `BEAT_DECAY_SEC` | 0.7 s | 0.3–1.2 s | Return speed. Below 0.3 s snaps back; above 1.2 s pushes `T_total` over the 2.0 s budget constraint. **Do not exceed 1.2 s.** |
| Peak modulate — green channel | `BEAT_PEAK_GREEN` | 1.35 | 1.15–1.5 | Green channel intensity of the lift. At 1.15 the shift is subtle; at 1.5 it becomes aggressive and risks reading as an alert color. |
| Peak modulate — red/blue channels | `BEAT_PEAK_RB` | 1.15 | 1.0–1.25 | Brightness of the lift on non-green channels. At 1.0 = pure green push; at 1.25 = near-white lift with green tint. |
| Tween easing type | `BEAT_EASE_TYPE` | `TRANS_SINE / EASE_IN_OUT` | Any Godot `Tween.TransitionType` | Acceleration curve for attack and decay. `TRANS_SINE` is the natural default. `TRANS_LINEAR` produces a mechanical feel. `TRANS_ELASTIC` and `TRANS_BOUNCE` are inappropriate — do not use. |

**Budget constraint**: `BEAT_ATTACK_SEC + BEAT_HOLD_SEC + BEAT_DECAY_SEC` must remain ≤ 1.5 s to preserve 0.5 s buffer under `completed_beat_duration_seconds` = 2.0 s. Consider a debug-build assertion: `assert(BEAT_TOTAL_SEC <= completed_beat_duration_seconds)`.

**Post-MVP note**: Agent-type-specific Tween shapes (e.g., "analyst" beats feel tighter than "writer" beats) are a natural extension of the registry. Not in scope at MVP — all agent types share the same Tween shape.

## Visual/Audio Requirements

**Visual**

The room modulate Tween is implemented entirely in code — no additional art assets are required for the visual beat. The effect is a runtime Tween on the room root Node2D's `modulate` property.

**Audio production requirements (for sound designer):**

All completion beat audio files must conform to the constraints established in `audio-manager.md`:

| Constraint | Requirement |
|---|---|
| Attack | ≤ 5 ms |
| Duration | 0.4–1.2 s (onset to full decay) |
| Center frequency | 1 kHz – 8 kHz |
| Volume | −12 dBFS relative to Master |
| Format | OGG Vorbis |
| File path | `assets/audio/sfx/completion/[agent_type].ogg` |
| Default fallback | `assets/audio/sfx/completion/default.ogg` (mandatory) |

**Tone differentiation rule** (from `audio-manager.md`): Each registered `agent_type` beat must differ from all others in ≥2 of: (a) pitch center, (b) timbre category (tonal / percussive / textural), (c) duration tier (short 0.4–0.6 s / medium 0.6–0.9 s / long 0.9–1.2 s).

**Recommended palette principle**: 3 timbre categories × 4 pitch tiers = 12 distinct tone slots — sufficient to cover the maximum 12 agents without repetition. Duration is the secondary differentiator. Timbre and pitch should reflect agent role character (e.g., low tonal for analytical roles; bright percussive for fast/precise roles).

**Must NOT sound like the alert**: Alert center frequency is 800 Hz–1.5 kHz at −8 dBFS. Completion beats must remain above 1 kHz center and must not use the alert's harmonic profile.

## UI Requirements

The Task Completion Beat has no UI of its own. Its UI contribution is indirect:

- The `beat_fired(agent_id: String, timestamp: float)` signal is consumed by the Commander's Room HUD to populate its **recent completions panel**. The HUD owns all display logic, formatting, and layout for that panel.
- The room modulate Tween is a visual-world effect (room lighting), not a UI element. It does not use any CanvasLayer or Control node.

No additional UI specification is required for TCB.

## Acceptance Criteria

### Group 1 — Registry Initialization

**AC-01** `[unit test]`
Given the scene bootstraps,
When `TaskCompletionBeat._ready()` completes,
Then `AgentSoundRegistry` contains a valid preloaded `AudioStream` at the `"default"` key, and no null entries exist for any key present in the dictionary.

**AC-02** `[unit test]`
Given `assets/audio/sfx/completion/default.ogg` is missing,
When `TaskCompletionBeat._ready()` completes,
Then a startup error is logged and the missing-default condition is surfaced (not a silent failure).

---

### Group 2 — Beat Trigger

**AC-03** `[integration test]`
Given a `task_completed(agent_id)` signal is emitted,
When TCB receives the signal,
Then `AudioManager.play_sfx()` is called within the same frame — before any `await` yields.

**AC-04** `[integration test]`
Given a `task_completed(agent_id)` signal is emitted,
When TCB receives the signal,
Then `beat_fired(agent_id, timestamp)` is emitted within the same frame, and `timestamp` equals `Time.get_unix_time_from_system()` at signal receipt time (within one-frame tolerance).

---

### Group 3 — Audio Resolution

**AC-05** `[unit test]`
Given `AgentSoundRegistry` has an entry for agent_type `"researcher"`,
When a `task_completed` signal fires for an agent with `agent_type == "researcher"`,
Then `AudioManager.play_sfx()` is called with the `"researcher"` AudioStream (not the `"default"` stream).

**AC-06** `[unit test]`
Given `AgentSoundRegistry` has no entry for agent_type `"unknown_role"` but has a `"default"` entry,
When `task_completed` fires for an agent with `agent_type == "unknown_role"`,
Then `AudioManager.play_sfx()` is called with the `"default"` AudioStream, and no `push_error` is emitted.

**AC-07** `[unit test]`
Given `AgentSoundRegistry` has no entry for `"unknown_role"` AND no `"default"` key,
When `task_completed` fires,
Then `AudioManager.play_sfx()` is NOT called, a `push_warning` is emitted, and the visual beat and `beat_fired` signal still fire.

---

### Group 4 — Visual Beat

**AC-08** `[integration test]`
Given `task_completed(agent_id)` fires for an agent in Room A,
When the Tween completes,
Then Room A's root Node2D `modulate` returns to `Color(1, 1, 1, 1)` within `BEAT_TOTAL_SEC` (1.5 s ± one frame).

**AC-09** `[integration test]`
Given `task_completed` fires and the Tween is running,
When the Tween reaches its hold phase,
Then Room A's `modulate` is `Color(1.15, 1.35, 1.15, 1.0)` (within float epsilon tolerance).

**AC-10** `[integration test]`
Given `task_completed` fires for Agent A (Room A) and Agent B (Room B) on the same frame,
When both Tweens are running,
Then Room A's modulate Tween and Room B's modulate Tween operate independently — each reaches peak and returns on its own timeline.

**AC-11** `[integration test]`
Given a room modulate Tween is in progress (Room A at approximately 0.8× peak),
When a second `task_completed` fires for another agent in Room A,
Then the existing Tween is killed, a new Tween begins from the room's current modulate value (not from neutral), and Room A reaches peak without resetting to `Color(1, 1, 1, 1)` first.

---

### Group 5 — Graceful Degradation

**AC-12** `[integration test]`
Given the Audio Manager is muted (global mute active),
When `task_completed` fires,
Then the visual beat Tween runs normally, `beat_fired` is emitted normally, and no errors are logged — the mute is handled entirely by the Audio Manager.

**AC-13** `[integration test]`
Given the room Node2D for an agent cannot be resolved,
When `task_completed` fires,
Then `play_sfx()` is called, `beat_fired` is emitted, a `push_warning` is emitted about the missing room node, and no crash or unhandled error occurs.

---

### Group 6 — Budget Constraint

**AC-14** `[unit test / debug assertion]`
Given `BEAT_ATTACK_SEC + BEAT_HOLD_SEC + BEAT_DECAY_SEC` is computed at startup,
Then the sum is ≤ `completed_beat_duration_seconds` (2.0 s). If the sum exceeds the budget, a debug assertion fires in non-release builds.

## Open Questions

1. **`task_completed` signal source**: This GDD treats the trigger as coming from the Agent State Machine (ASM). The ACC GDD also defines a `task_completed(agent_id)` signal on the character controller itself. Which is the canonical source — ASM or ACC? If TCB subscribes to ACC directly, it must subscribe to each ACC instance individually (up to 12 subscriptions); if it subscribes to the ASM, one subscription handles all agents. **Defer to Agent State Machine GDD.**

2. **~~`ConfigurationLoader.get_agent_type(agent_id)`~~** — RESOLVED 2026-05-11. TCB calls `ConfigurationLoader.get_agent(agent_id).get(&"agent_type", "default")`. `get_agent()` already exists per Configuration Loader GDD line 132.

3. **~~`agent_type` field in config.json schema~~** — RESOLVED 2026-05-11. Added to per-agent schema in Configuration Loader GDD as optional `string` field with default `"default"`.

4. **Room System interface for room node resolution**: Room System GDD does not currently expose a Node2D reference for a given agent's room. TCB needs `get_room_node_for_agent(agent_id) → Node2D` or equivalent. **Flag for Room System GDD review.**

5. **Tween on freed node (E7 VERIFY)**: If an agent's room Node2D is freed while a modulate Tween is running, Godot 4.6.2's behavior is expected to be a clean stop (no crash). Needs engine verification. **Add to project VERIFY list.**

6. **AAL + TCB visual layering in practice**: AAL fires a white prop flash on the same frame as TCB's room modulate Tween. The intended visual is "props flash white inside a room brightening green." Confirm this reads as intended in the first integration playtest — the two effects may interact differently in the actual renderer than on paper.
