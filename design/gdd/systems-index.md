# Systems Index: The Situation Room

> **Status**: Draft
> **Created**: 2026-05-08
> **Last Updated**: 2026-05-08
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

The Situation Room is a real-time AI agent dashboard with a game-like bunker aesthetic.
Its mechanical scope is unusually narrow — there is no combat, no economy, no skill
progression. Instead, the tool needs four things to work: a live data feed from real AI
agent APIs, a visual language that communicates agent state through animation alone, a
satisfying feedback moment for each task completion, and a room-based spatial layout
that earns each room only when an agent exists to fill it.

The complexity lives at the edges. The data bridge between Godot and real AI agent APIs
is technically unproven and is the highest-risk system in the project. The legibility of
agent state communicated through animation alone — without text labels or charts — is an
open design question. Every other system in this index exists to support one or more of
the five game pillars: **Alive by Default**, **Readable at a Glance**, **Satisfying
Feedback**, **Commander Always Home**, and **Earn Each Room**.

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Configuration Loader (inferred) | Integration | MVP | Designed | design/gdd/configuration-loader.md | — |
| 2 | Data Bridge | Integration | MVP | Designed* | design/gdd/data-bridge.md | Configuration Loader |
| 3 | Agent State Machine | Integration | MVP | Designed | design/gdd/agent-state-machine.md | Data Bridge, Configuration Loader |
| 4 | Audio Manager | Audio | MVP | Designed | design/gdd/audio-manager.md | — |
| 5 | TileMap Renderer (inferred) | Core | MVP | Designed | design/gdd/tilemap-renderer.md | — |
| 6 | Room System (inferred) | Core | MVP | Designed | design/gdd/room-system.md | Configuration Loader |
| 7 | Camera/Viewport System (inferred) | Core | Vertical Slice | Not Started | — | Room System |
| 8 | Agent Character Controller (inferred) | Character & Animation | MVP | Designed | design/gdd/agent-character-controller.md | Agent State Machine, TileMap Renderer, Room System |
| 9 | Commander Character (inferred) | Character & Animation | Vertical Slice | Not Started | — | Room System, TileMap Renderer |
| 10 | Ambient Animation Layer | Character & Animation | MVP | Designed | design/gdd/ambient-animation-layer.md | Room System, TileMap Renderer, Agent State Machine |
| 11 | Task Completion Beat | Feedback | MVP | Designed* | design/gdd/task-completion-beat.md | Agent State Machine, Audio Manager |
| 12 | Alert State System | Feedback | Vertical Slice | Not Started | — | Agent State Machine, TileMap Renderer |
| 13 | Commander's Room HUD (inferred) | UI | MVP | Designed* | design/gdd/commanders-room-hud.md | Agent State Machine, Room System, Task Completion Beat |
| 14 | History/Activity Log | UI | Alpha | Not Started | — | Agent State Machine, Room System |
| 15 | State Persistence (inferred) | Persistence | Alpha | Not Started | — | Room System, Agent State Machine, History/Activity Log |
| 16 | Main Scene Bootstrap | Architecture | MVP | Designed | design/gdd/main-scene-bootstrap.md | All systems — see note below |

> **Note on #16**: Main Scene Bootstrap defines the Godot scene hierarchy, autoload
> initialization order, and signal wiring between all systems. It is designed last (after
> all GDDs exist) and implemented first (it is the application entry point). It will be
> produced by `/create-architecture`, not `/design-system`.

---

## Categories

| Category | Description | Systems in This Project |
|----------|-------------|------------------------|
| **Integration** | Systems that connect the game engine to real external data | Configuration Loader, Data Bridge, Agent State Machine |
| **Core** | Infrastructure systems that everything else depends on | TileMap Renderer, Room System, Camera/Viewport System |
| **Character & Animation** | Character sprites, state-driven animation, and ambient motion | Agent Character Controller, Commander Character, Ambient Animation Layer |
| **Feedback** | Event-driven response systems (visual and audio) | Task Completion Beat, Alert State System |
| **Audio** | Sound and music management | Audio Manager |
| **UI** | Player-facing information displays | Commander's Room HUD, History/Activity Log |
| **Persistence** | Save state and continuity between sessions | State Persistence |
| **Architecture** | Scene structure and system wiring (not a GDD — produced by `/create-architecture`) | Main Scene Bootstrap |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | Required for the core hypothesis: does a live-data top-down bunker feel more alive than a static dashboard? | Prototype (2–3 weeks) | Design FIRST |
| **Vertical Slice** | One complete, polished experience demonstrating the full visual and feedback language | V0.5 demo | Design SECOND |
| **Alpha** | All retention-layer systems present; the tool is usable between sessions | V1 (3–5 rooms) | Design THIRD |
| **Full Vision** | Per-room visual specialization, expanded room unlock rules, content-complete | Ongoing | Design as needed |

---

## Dependency Map

### Foundation Layer — no dependencies on other game systems

1. **Configuration Loader** — reads an external config file; nothing runs without knowing which agents to connect to
2. **Audio Manager** — wraps Godot's AudioServer; feedback systems call into it but it needs nothing from them
3. **TileMap Renderer** — wraps Godot's TileMapLayer; character and ambient systems place things within it but it has no runtime dependency on them

### Core Layer — depends on Foundation

1. **Data Bridge** — depends on: Configuration Loader (endpoints + credentials)
2. **Room System** — depends on: Configuration Loader (agent list → room registry)
3. **Agent State Machine** — depends on: Data Bridge (raw state-change events → canonical game states)
4. **Camera/Viewport System** — depends on: Room System (room registry for multi-room navigation)

### Feature Layer — depends on Core

1. **Agent Character Controller** — depends on: Agent State Machine (drives animation), TileMap Renderer (sprite placement), Room System (room assignment)
2. **Commander Character** — depends on: Room System (fixed to Commander's Room), TileMap Renderer
3. **Ambient Animation Layer** — depends on: Room System, TileMap Renderer, Agent State Machine (some ambient details respond to agent state)
4. **Task Completion Beat** — depends on: Agent State Machine (`task_completed` event), Audio Manager (plays the beat)
5. **Alert State System** — depends on: Agent State Machine (`agent_errored` event), TileMap Renderer (room tile state change)

### Presentation Layer — depends on Feature

1. **Commander's Room HUD** — depends on: Agent State Machine (status data), Room System (agent list), Task Completion Beat (recent completions panel)
2. **History/Activity Log** — depends on: Agent State Machine (completion events), Room System (room-level log)

### Polish Layer — depends on everything

1. **State Persistence** — depends on: Room System (config), Agent State Machine (agent history), History/Activity Log (log entries)

---

## Circular Dependencies

**None found.** The dependency graph is a clean directed acyclic graph. ✅

---

## Bottleneck Systems

Systems with many dependents — high-risk if their design is unstable.

| System | # Dependents | Risk | Note |
|--------|-------------|------|------|
| **Agent State Machine** | 6 | HIGH | If the state model (`idle/working/completed/errored`) changes, every visual system must update. Lock this early. |
| **Room System** | 5 | HIGH | Room data contract is queried by Camera, Character Controllers, Ambient Layer, HUD, and History Log. |
| **Configuration Loader** | 2 | MEDIUM | Low-risk technically, but its schema defines what the Data Bridge and Room System can know at startup. |

---

## High-Risk Systems

Systems that are technically unproven, design-uncertain, or scope-dangerous. Prototype early.

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **Data Bridge** | Technical | Real AI agent APIs have unknown response formats, authentication methods, rate limits, and error modes. Connection may fail silently. | GDD must specify a prototype approach. Validate with real API calls before building any visualization. |
| **Agent State Machine** | Design | The state model must accurately reflect what real APIs can actually report — not what we assume they report. A wrong model propagates to all 6 dependent systems. | Design the State Machine GDD AFTER the Data Bridge prototype reveals what data is actually available. |
| **Agent Character Controller** | Design | Will animation alone communicate `idle/working/completed/errored` legibly without text labels? This is the central legibility question of the entire tool. | GDD must specify a legibility test. Build a visual prototype with placeholder art to validate before full art production. |

---

## Recommended Design Order

Design these systems in this sequence. Foundation systems #1–3 are independent and can
be designed in parallel. After #3, follow the numbered sequence.

| # | System | Priority | Layer | Effort | Why This Order |
|---|--------|----------|-------|--------|----------------|
| 1 | Configuration Loader | MVP | Foundation | S | Everything that reads external data depends on the config schema. Design this first so the rest of the pipeline can be specified. |
| 2 | Audio Manager | MVP | Foundation | S | No dependencies; design in parallel with #1. Must be defined before Task Completion Beat (#9) can spec its audio behavior. |
| 3 | TileMap Renderer | MVP | Foundation | S | No dependencies; design in parallel. All spatial systems need the tile grid spec before they can define where things live. |
| 4 | Data Bridge | MVP | Core | M | Highest-risk system — its GDD includes the prototype plan. Design it first in Core; the prototype results inform Agent State Machine (#6). |
| 5 | Room System | MVP | Core | M | Design alongside #4. Defines the room/agent data contract queried by 5 downstream systems. MVP version: 1 hardcoded room. |
| 6 | Agent State Machine | MVP | Core | M | Design after Data Bridge prototype reveals actual API output. The state model (`idle/working/completed/errored`) must map to real data. |
| 7 | Agent Character Controller | MVP | Feature | M | Primary proof of "Alive by Default" (Pillar 1). Animation state machine drives `idle/working/completed/errored` visually. |
| 8 | Ambient Animation Layer | MVP | Feature | M | MVP explicitly requires ambient animation. Can be designed in parallel with #7 — independent of the character animation system. |
| 9 | Task Completion Beat | MVP | Feature | S | The core satisfaction moment of the tool. Short GDD; design it with deliberate care rather than treating it as trivial. |
| 10 | Commander's Room HUD | MVP | Presentation | M | Seals the MVP: the user can read overall status in under 1 second (Pillar 4). Designed last in MVP — requires #6, #5, and #9 to be defined. |
| 11 | Alert State System | VS | Feature | S | Completes the state model. Short GDD since the pattern is established by #7. |
| 12 | Commander Character | VS | Feature | S | User avatar with ambient idle animation. One room, one loop. |
| 13 | Camera/Viewport System | VS | Core | S | Viewport config + multi-room navigation. Required for V1 room expansion. |
| 14 | History/Activity Log | Alpha | Presentation | M | The "what happened while I was away?" hook. Depends on #6 and #5 designs being stable. |
| 15 | State Persistence | Alpha | Polish | M | Save/load across sessions. Designed last because it wraps the stable versions of everything else. |

*Effort: S = 1 design session, M = 2–3 sessions, L = 4+ sessions.*

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 16 |
| Systems with GDDs (design-system) | 15 |
| Systems with GDDs started | 9 |
| Systems with GDDs reviewed | 0 |
| Systems with GDDs approved | 0 |
| MVP systems designed | 9 / 10 (10th blocked — Agent State Machine) |
| Vertical Slice systems designed | 0 / 3 |
| Alpha systems designed | 0 / 2 |

---

## Next Steps

- [ ] Design MVP systems in order: run `/design-system configuration-loader` first
- [ ] Run `/design-system data-bridge` — include prototype plan in the GDD
- [ ] After Data Bridge GDD + prototype, revisit Agent State Machine GDD to verify state model matches real API output
- [ ] Run `/design-review design/gdd/[system].md` after each GDD is authored
- [ ] Run `/gate-check pre-production` when all 10 MVP system GDDs are complete and reviewed
- [ ] Run `/create-architecture` after all MVP GDDs are approved — produces Main Scene Bootstrap and the technical blueprint
- [ ] Run `/prototype data-bridge` (or embed prototype scope in the Data Bridge GDD) before any art production begins
