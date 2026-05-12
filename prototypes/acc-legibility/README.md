# Prototype: ACC Legibility Test

**Status**: In Progress
**Created**: 2026-05-09
**Hypothesis**: Can a user identify `idle`, `working`, `completed`, and `errored` agent states within 3 seconds using animation alone — no text labels?

---

## How to Run

1. Open **Godot 4.6.2**
2. Click **Import** → navigate to this folder → select `project.godot`
3. Press **F5** (or the ▶ Play button)

No assets to install. Everything is drawn programmatically.

---

## What You're Looking At

A single bunker room with 4 agents, one per quadrant, each locked in a different state:

| Quadrant | State | Visual |
|---|---|---|
| Top-left | IDLE_WANDERING | Amber rectangle, wanders around randomly |
| Top-right | WORKING | Green rectangle, stationary at a desk, gentle bob |
| Bottom-left | COMPLETED_BEAT | Flashes white → scale pop → returns to amber wandering |
| Bottom-right | ERRORED | Red/sienna rectangle, frozen, red `!` above it |

---

## Controls

| Key | Action |
|---|---|
| **H** | Toggle state name labels on/off — this is the legibility test |
| **R** | Reset all agents to starting positions and states |
| **SPACE** | Trigger the COMPLETED beat animation + toggle ERRORED ↔ IDLE |

The COMPLETED agent also auto-cycles every 4 seconds without input.

---

## The Test

Press **H** to hide labels. Ask someone (or yourself):

> "Which agent is doing work right now? Which one had an error? Which one just finished something?"

**Pass**: All 4 states correctly identified in under 3 seconds.
**Fail**: Any state is ambiguous or confused with another.

This test must pass before full sprite art production begins (ACC GDD Acceptance Criteria #1).

---

## Findings

*(Update this section when the test has been run)*

- [ ] Test run with: [name/date]
- [ ] Pass / Fail
- [ ] Notes on which states were ambiguous (if any)
- [ ] Recommended art changes before production

---

## Files

```
project.godot        — Godot 4.6.2 project config
Main.tscn            — Minimal entry point scene
scripts/Main.gd      — Room geometry + agent setup + input handling
scripts/AgentPreview.gd — Per-agent state machine and visuals
```

---

*This is a throwaway prototype. Do not migrate this code to production. Findings inform `design/gdd/agent-character-controller.md`.*
