# Audio Manager

> **Status**: Designed — pending /design-review
> **Author**: Thomas + Claude
> **Last Updated**: 2026-05-09
> **Implements Pillar**: Pillar 3 — Satisfying Feedback

> **TL;DR (Claude: read this, skip the full doc unless you need detail)**
> Autoload singleton. Two buses: Master → Music (−18 dB default) + SFX (−12 dB default). 8 pre-instantiated AudioStreamPlayer pool nodes (no runtime allocation). API: `play_music(stream)`, `stop_music()`, `play_sfx(stream)`, `stop_sfx_all()`, `set_music_volume(db)`, `set_sfx_volume(db)`, `toggle_mute()`. Audio Manager is stream-agnostic — callers own the agent-to-stream mapping. No ducking. Two-tier mute (M-key global + per-bus). Settings persist to `user://settings.json`. 20 acceptance criteria.

## Overview

The Audio Manager is an Autoload singleton that wraps Godot's `AudioServer` to provide a single, stable interface for all sound playback in The Situation Room. It owns the bus topology (Master → Music bus, Master → SFX bus), manages a pre-instantiated pool of `AudioStreamPlayer` nodes for concurrent sound effects, and exposes simple `play_music()`, `play_sfx()`, and `stop_music()` calls that any other system can invoke without knowing Godot's audio internals. The player experiences this through sound: the ambient bunker loop runs continuously in the background while discrete audio beats mark each meaningful event — a task completing, an agent entering an error state — giving the tool its sensory texture and making data feel like consequence rather than a dashboard update.

## Player Fantasy

The bunker hums. Even when nothing is happening, the room breathes — a low ambient drone that says the place is occupied, powered, working. When an agent finishes a task, a small clean beat lands: a switch closing, a stamp hitting paper, a relay clicking home. The player doesn't watch the dashboard; they listen to it. They know which agent finished before they look — because the bunker told them, the way a kettle tells you it's done.

This is the sonic expression of **Pillar 1 — Alive by Default**: the bunker is never silent, and silence would feel like failure. It also anchors **Pillar 3 — Satisfying Feedback**: every meaningful event has an audio beat, and without the Audio Manager, those beats do not exist.

## Detailed Design

### Core Rules

1. **Bus topology.** The Audio Manager owns two child buses under Master:
   - `Music` bus — carries the ambient bunker loop (one stream, looped, persistent)
   - `SFX` bus — carries all transient sounds (completion beats, alert)
   - Master bus volume is OS-controlled. The Audio Manager never touches Master.

2. **Pool architecture.** On `_ready()`, the Audio Manager pre-instantiates 8 `AudioStreamPlayer` nodes as children, all assigned to the `SFX` bus. No SFX player is ever created at runtime. A separate, dedicated `AudioStreamPlayer` on the `Music` bus handles ambient playback and is not part of the pool.

3. **Pool slot selection.** When `play_sfx()` is called, the Audio Manager iterates the pool and assigns the first player where `playing == false`. If no free slot exists, the call is silently dropped and a warning is logged (`push_warning`). Dropped sounds are an acceptable failure mode for a personal productivity tool.

4. **Ambient loop behavior.** The Music bus plays at constant volume at all times. There is no ducking, sidechaining, or volume modulation in response to SFX events. Completion beats and alerts are fully layered over the ambient loop. The ambient is structurally independent of all game events.

5. **Default bus volumes.**

   | Bus | Default | Rationale |
   |-----|---------|-----------|
   | Master | 0 dB | OS-controlled |
   | Music | −18 dB | Texture, not feature — present but not demanding |
   | SFX | −12 dB | Events land 6 dB above ambient; quiet for background |

6. **Mute system.** Two independent tiers:
   - **Global mute** — single-keystroke toggle (`M` key) that sets all buses to −80 dB simultaneously. On untoggle, restores pre-mute values. Visual state remains active regardless of mute.
   - **Per-bus mute** — Music and SFX buses mutable independently via a future settings panel. Muting Music only preserves alerts while silencing the ambient loop.
   - Mute state and volume values persist across sessions in a `user://settings.json` file. The Audio Manager owns reading and writing this file on startup and on change.

7. **Completion beat characteristics** (design-time constraints enforced by sound designer, not runtime):

   | Property | Constraint |
   |----------|------------|
   | Attack | ≤ 5 ms |
   | Duration | 0.4 – 1.2 seconds (onset to full decay) |
   | Frequency | 1 kHz – 8 kHz; no sustained content above 8 kHz |
   | Volume | −12 dBFS relative to Master |
   | Max simultaneous | 3 — a 4th concurrent beat is dropped, not queued |
   | Differentiation rule | Each agent type's beat must differ from all others in at least 2 of: (a) pitch center, (b) timbre category (tonal / percussive / textural), (c) duration tier (short 0.4–0.6 s / medium 0.6–0.9 s / long 0.9–1.2 s) |

8. **Alert sound characteristics** (design-time constraints, not runtime):

   | Property | Constraint |
   |----------|------------|
   | Trigger | Single-shot per error event; does not repeat even if error persists |
   | Duration | ≤ 2.0 seconds |
   | Frequency | 800 Hz – 1.5 kHz center; no content above 4 kHz |
   | Volume | −8 dBFS relative to Master (loudest single sound in the system) |
   | Timbre | Harmonically clean — tone, click, or short chord; no noise or distortion |

---

### States and Transitions

The Audio Manager has no formal state machine. Godot Autoloads initialize synchronously before any game scene runs, so the manager is always ready by the time any consumer calls it. Runtime properties:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `_music_player` | AudioStreamPlayer | pre-instantiated | Dedicated music bus player |
| `_sfx_pool` | Array[AudioStreamPlayer] | 8 nodes | Pre-instantiated SFX players |
| `_music_volume_db` | float | −18.0 | Current Music bus level |
| `_sfx_volume_db` | float | −12.0 | Current SFX bus level |
| `_muted` | bool | false | Global mute state |
| `_volume_before_mute` | Dictionary | {music: −18.0, sfx: −12.0} | Restore values on unmute |

The only conditional logic is the pool availability check in `play_sfx()`.

---

### Interactions with Other Systems

The Audio Manager knows nothing about agents, tasks, or game events. It knows only about `AudioStream` objects and bus volume levels. The calling system is always responsible for resolving which stream to pass.

| Consumer | Method Called | Data Passed | Audio Manager Response |
|----------|--------------|-------------|------------------------|
| Task Completion Beat | `play_sfx(stream)` | `AudioStream` for this agent type (resolved by caller from AgentSoundRegistry) | Assigns to free pool slot and plays |
| Alert State System | `play_sfx(stream)` | Alert `AudioStream` | Assigns to free pool slot and plays |
| Main Scene Bootstrap | `play_music(stream)` | Ambient loop `AudioStream` | Plays on Music player, looped |
| Main Scene Bootstrap | `set_music_volume(db)` | Restored user preference | Sets Music bus level |
| Main Scene Bootstrap | `set_sfx_volume(db)` | Restored user preference | Sets SFX bus level |

**Public API surface:**

| Method | Signature | Effect |
|--------|-----------|--------|
| `play_music` | `(stream: AudioStream) -> void` | Stops current music, plays new stream looped |
| `stop_music` | `() -> void` | Stops music player (hard cut — no fade in MVP) |
| `play_sfx` | `(stream: AudioStream) -> void` | Grabs free pool slot, plays once |
| `stop_sfx_all` | `() -> void` | Stops all pool players (scene transitions, emergency silence) |
| `set_music_volume` | `(db: float) -> void` | Sets Music bus volume; persists to settings |
| `set_sfx_volume` | `(db: float) -> void` | Sets SFX bus volume; persists to settings |
| `toggle_mute` | `() -> void` | Toggles global mute; persists state to settings |

## Formulas

There are no gameplay formulas in the Audio Manager — it contains no balance math or game mechanics. The only defined calculations are dB conversions used for volume control.

**F1 — Linear to dB conversion** (reference formula, not implemented in GDScript — Godot's AudioServer accepts dB natively):

```
db = 20 × log₁₀(linear_amplitude)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `linear_amplitude` | float | 0.0 – 1.0 | Linear amplitude (0 = silence, 1 = unity) |
| `db` | float | −∞ – 0 dB | Decibel value passed to `AudioServer.set_bus_volume_db()` |

Godot provides `linear_to_db(linear)` and `db_to_linear(db)` as built-in functions. Use these rather than computing manually.

**F2 — Safe volume clamp** (enforced in `set_music_volume()` and `set_sfx_volume()`):

```
clamped_db = clamp(input_db, MIN_VOLUME_DB, MAX_VOLUME_DB)
```

| Variable | Default | Safe Range | Description |
|----------|---------|------------|-------------|
| `MIN_VOLUME_DB` | −80.0 dB | — | Effective silence (Godot does not use −∞) |
| `MAX_VOLUME_DB` | 6.0 dB | — | +6 dB ceiling to prevent clipping |
| `input_db` | — | any float | Raw input from settings panel or config |
| `clamped_db` | — | [−80, 6] | Value passed to AudioServer |

*Example*: If the settings panel passes `input_db = 20.0`, the clamp returns `6.0`. If it passes `−100.0`, the clamp returns `−80.0`.

## Edge Cases

**E1 — All SFX pool slots busy**
If `play_sfx()` is called when all 8 pool players have `playing == true`, the sound is silently dropped. A `push_warning("AudioManager: SFX pool exhausted — sound dropped")` is logged. No crash, no queue. Rationale: in a personal productivity tool, an occasional missed beat is preferable to stall, queue backlog, or delayed playback that arrives out of context.

**E2 — `play_music()` called while music is already playing**
The current music player is stopped immediately (hard cut) and the new stream begins. There is no crossfade in MVP. This covers the case where the Main Scene Bootstrap calls `play_music()` a second time (e.g., after a settings change or scene reload).

**E3 — `play_sfx()` called with a null or invalid stream**
If `stream` is `null`, the call returns immediately with `push_error("AudioManager: play_sfx() received null stream")`. No pool slot is consumed. The caller (Task Completion Beat or Alert State System) is responsible for passing a valid `AudioStream`.

**E4 — `toggle_mute()` called when settings file is unwritable**
The mute state change is applied in memory (buses go silent) but a `push_warning` logs that persistence failed. On next launch, mute defaults to `false`. The developer's session is not interrupted.

**E5 — `settings.json` missing or malformed on startup**
If `user://settings.json` does not exist or fails to parse, the Audio Manager silently uses its hardcoded defaults (Music: −18 dB, SFX: −12 dB, muted: false). A `push_warning` is logged. The file is not created at startup — it is created only on first volume change or mute toggle.

**E6 — Volume set to exactly −80 dB without using `toggle_mute()`**
The bus is silenced via `set_music_volume(-80.0)` or `set_sfx_volume(-80.0)`. This is valid. The `_muted` flag remains `false`. If the user then calls `toggle_mute()`, it reads the pre-mute restore values — which may themselves be −80 dB. On unmute, the bus returns to −80 dB (not to the hardcoded default). This is correct: the user explicitly set −80 dB as their preferred level.

**E7 — `stop_sfx_all()` called mid-completion-beat**
All pool players are stopped immediately. Any beat currently playing is cut. This is the intended behavior for scene transitions or emergency silence. There is no fade-out.

**E8 — Simultaneous completion beats and the "max 3" rule**
The "max 3 simultaneous beats" constraint is a sound design rule (enforced at audio production time), not a runtime limit enforced by code. The 8-slot pool can physically handle all 8 simultaneous sounds. The design intent is that beats are short enough (0.4–1.2 s) that 3-at-once is the realistic ceiling in normal use. The pool drops sounds only when ALL 8 slots are busy — not at 3 overlaps.

## Dependencies

### Upstream (what Audio Manager depends on)

**None.** The Audio Manager is a Foundation-layer system with zero upstream dependencies. It initializes from hardcoded defaults and reads `user://settings.json` (a file it owns, not another system's output).

### Downstream (systems that depend on Audio Manager)

| System | Priority | What it needs from Audio Manager |
|--------|----------|----------------------------------|
| **Task Completion Beat** | MVP | `play_sfx(stream)` — plays the completion beat for a finished agent task |
| **Alert State System** | Vertical Slice | `play_sfx(stream)` — plays the alert sound when an agent enters error state |

### Data Contract

Any system calling `play_sfx()` must resolve its own `AudioStream` before calling. The Audio Manager does not hold an audio asset registry; it does not know about agent types, event types, or sound names. The caller owns the lookup.

**AgentSoundRegistry** (owned by Task Completion Beat) is the expected lookup mechanism for completion beats — a dictionary or resource that maps `agent_type → AudioStream`. This is a dependency of Task Completion Beat, not of Audio Manager.

### Interface Note for Downstream GDDs

When writing the Task Completion Beat GDD and Alert State System GDD, reference Audio Manager's public API surface (defined in Section C). Both systems must pass a preloaded `AudioStream` — not a file path string.

## Tuning Knobs

| Knob | Constant Name | Default | Safe Range | Affects |
|------|--------------|---------|------------|---------|
| SFX pool size | `SFX_POOL_SIZE` | 8 | 4 – 16 | Max simultaneous transient sounds; below 4 risks exhaustion on burst completions, above 16 wastes memory for negligible benefit |
| Music bus default | `DEFAULT_MUSIC_VOLUME_DB` | −18.0 dB | −24 – −12 dB | How present the ambient loop feels; below −24 is inaudible, above −12 competes with SFX events |
| SFX bus default | `DEFAULT_SFX_VOLUME_DB` | −12.0 dB | −18 – −6 dB | How audible completion beats and alerts are; above −6 the alert begins to feel startling |
| Volume ceiling | `MAX_VOLUME_DB` | 6.0 dB | fixed | Hard cap applied via F2 clamp to prevent clipping |
| Silence floor | `MIN_VOLUME_DB` | −80.0 dB | fixed | Effective silence in Godot (AudioServer does not use −∞) |
| Completion beat max simultaneous | *(sound design rule, not a constant)* | 3 | 1 – 5 | How many beats can overlap before the mix becomes indistinct; enforced at audio production time |
| Alert volume offset | *(sound design rule, not a constant)* | −8 dBFS | −10 – −6 dBFS | Alert prominence relative to Master; enforced at audio production time |

**Post-MVP enhancements** (not built now — document for future tuning):
- `MUSIC_FADE_DURATION_SEC` — crossfade duration when switching ambient tracks (default 2.0s; requires a second music player)
- `SFX_ALERT_REPEAT_DELAY_SEC` — delay before alert replays on sustained error (explicitly chosen not to implement in MVP)

## Visual/Audio Requirements

[To be designed]

## UI Requirements

[To be designed]

## Acceptance Criteria

### Group 1 — Initialization

**AC-01** `[unit test]`
Given the application launches,
When `AudioManager._ready()` completes,
Then `AudioServer` has a `Music` bus and an `SFX` bus as children of Master, and `SFX_POOL_SIZE` (8) `AudioStreamPlayer` nodes exist as children of AudioManager, all assigned to the `SFX` bus.

**AC-02** `[unit test]`
Given `user://settings.json` does not exist,
When `AudioManager._ready()` completes,
Then the Music bus volume is −18.0 dB, the SFX bus volume is −12.0 dB, and `_muted` is `false`.

**AC-03** `[unit test]`
Given `user://settings.json` exists with valid music_db, sfx_db, and muted values,
When `AudioManager._ready()` completes,
Then bus volumes and mute state match the saved values.

**AC-04** `[unit test]`
Given `user://settings.json` exists but contains malformed JSON,
When `AudioManager._ready()` completes,
Then hardcoded defaults are used, a `push_warning` is emitted, and no crash occurs.

---

### Group 2 — Music Playback

**AC-05** `[integration test]`
Given the Audio Manager is initialized,
When `play_music(stream)` is called with a valid looping `AudioStream`,
Then the Music bus player begins playing and `_music_player.playing == true`.

**AC-06** `[integration test]`
Given music is already playing,
When `play_music(new_stream)` is called,
Then the previous stream stops immediately and the new stream begins (hard cut, no crash).

**AC-07** `[integration test]`
Given music is playing,
When `stop_music()` is called,
Then `_music_player.playing == false`.

---

### Group 3 — SFX Pool

**AC-08** `[unit test]`
Given all 8 pool players have `playing == false`,
When `play_sfx(stream)` is called,
Then the first pool player is assigned the stream and begins playing.

**AC-09** `[unit test]`
Given all 8 pool players have `playing == true`,
When `play_sfx(stream)` is called,
Then the sound is dropped, a `push_warning` is emitted, and no crash or queue occurs.

**AC-10** `[unit test]`
When `play_sfx(null)` is called,
Then the method returns immediately, a `push_error` is emitted, no pool slot is consumed, and no crash occurs.

**AC-11** `[integration test]`
Given one or more pool players are active,
When `stop_sfx_all()` is called,
Then all pool players have `playing == false` immediately.

---

### Group 4 — Volume Control

**AC-12** `[unit test]`
When `set_music_volume(-18.0)` is called,
Then `AudioServer.get_bus_volume_db(music_bus_index) == -18.0` and the value is written to `user://settings.json`.

**AC-13** `[unit test]`
When `set_music_volume(20.0)` is called (above MAX_VOLUME_DB),
Then the actual bus volume is clamped to 6.0 dB.

**AC-14** `[unit test]`
When `set_sfx_volume(-100.0)` is called (below MIN_VOLUME_DB),
Then the actual bus volume is clamped to −80.0 dB.

---

### Group 5 — Mute

**AC-15** `[unit test]`
Given `_muted == false` with Music at −18 dB and SFX at −12 dB,
When `toggle_mute()` is called,
Then both buses are set to −80 dB, `_muted == true`, and `_volume_before_mute` stores `{music: -18.0, sfx: -12.0}`.

**AC-16** `[unit test]`
Given `_muted == true`,
When `toggle_mute()` is called,
Then both buses are restored to their pre-mute values and `_muted == false`.

**AC-17** `[unit test]`
Given `_muted == true`,
When the game renders,
Then visual state (room colors, agent sprites) is unchanged — mute affects audio output only.

**AC-18** `[integration test]`
Given the user toggles mute and then restarts the application,
When `AudioManager._ready()` completes,
Then the mute state and volume values match what was saved.

---

### Group 6 — API Isolation

**AC-19** `[unit test]`
When `play_sfx(stream)` is called,
Then the Audio Manager does not inspect or read any property of the calling system — it only uses the passed `AudioStream`.

**AC-20** `[unit test]`
Given a new agent type is added to the project,
When the Task Completion Beat system resolves the correct stream and calls `play_sfx(stream)`,
Then the Audio Manager plays the sound without any code change to AudioManager itself.

## Open Questions

[To be designed]
