# Game Concept: The Situation Room

*Created: 2026-05-08*
*Status: Draft*

---

## Elevator Pitch

> A top-down underground bunker where your real AI agents have physical
> presence — you watch them work in real time through a game-like interface.
> It's a living dashboard, not a dead form.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Gamified productivity tool / ambient dashboard |
| **Platform** | TBD — run `/setup-engine` to configure |
| **Target Audience** | Solo developer managing a personal AI agent team |
| **Player Count** | Single-user |
| **Session Length** | 2–10 minutes (check-in style, open when needed) |
| **Monetization** | None — personal tool |
| **Estimated Scope** | Small (2–3 weeks MVP, solo) |
| **Comparable Titles** | Factorio (system satisfaction), Terraria (room-based world), Fallout Vaults (institutional underground aesthetic) |

---

## Core Fantasy

Your AI agents are running. You built this system, and you can see it
working — agents animated in their rooms, tasks completing with satisfying
visual and audio beats. You never have to ask what's happening; the bunker
shows you at a glance. It's the moment a Minecraft redstone contraption
clicks to life, or a Fallout settlement starts humming on its own — except
it's your real AI agent team, and they're doing real work.

---

## Unique Hook

Like a developer dashboard, AND ALSO a living top-down bunker where your
AI agents have physical presence and every task completion feels satisfying
to watch.

The difference from every other dashboard: data is spatial and animated,
not numeric and static. You read the bunker the way you read a factory
floor — by watching, not by clicking.

---

## Visual Identity Anchor

**Direction**: Institutional Underground

**Visual rule**: Everything looks built to work, not to impress — but it
works beautifully.

**Supporting principles**:
1. **Pixel art (16–32px)** — readable at any zoom, nostalgic, low art
   overhead. Crisp lines, flat fills, deliberate palette.
   *Design test*: If an element can't be read at 1× zoom, simplify it.

2. **Warm amber / green CRT palette** — Fallout terminal meets Minecraft
   underground. Institutional warmth, not clinical white.
   *Design test*: Does new UI feel like it belongs in a working bunker, or
   a modern SaaS product? If the latter, retheme it.

3. **Mechanical detail density** — pipes, vents, status lights, blinking
   indicators. The bunker has texture; it's been lived in.
   *Design test*: Is there something always moving in the background? If
   not, add a detail layer.

**Color philosophy**: Amber and warm grey as primaries. Muted green for
active/healthy states. Dull red for alerts. No saturated blues or modern
gradients — this is a bunker, not a SaaS dashboard.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the user FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | 2 | Visual animation quality, audio completion beats, ambient bunker sound |
| **Fantasy** (make-believe) | N/A | Not a fantasy game — the user IS the commander |
| **Narrative** (drama, story) | N/A | No story arc — the bunker reflects real work |
| **Challenge** (mastery) | N/A | No challenge — this is a tool |
| **Fellowship** (social) | N/A | Single-user, personal tool |
| **Discovery** (exploration) | 3 | Understanding what agents have been doing; seeing a busy room and reading its state |
| **Expression** (creativity) | 4 | Configuring the bunker to reflect your agent setup |
| **Submission** (relaxation, flow) | 1 | Primary — watching a well-oiled system run. Zero friction. |

### Key Dynamics (Emergent user behaviors)

- Users will naturally open the bunker when starting their day — it becomes
  a morning ritual, not a chore
- Users will want to expand to more rooms as they add agents — the bunker
  growing is a reward for team growth
- Users will optimize agent configuration to make the bunker look more
  active and satisfying — "configuration quality" becomes legible in the
  visual output

### Core Mechanics (Systems we build)

1. **Real-time agent status visualization** — each agent's state maps to
   room animations (idle, working, completed, errored)
2. **Task completion beats** — visual pulse + audio beat when agents
   complete work; the primary moment of satisfaction
3. **Commander's Room** — the user's own context always visible: current
   task, recent completions, overall system status

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Tool Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | User configures the system; AI executes. You're the architect, not the worker. | Supporting |
| **Competence** (mastery, skill growth) | Satisfaction in good configuration — "I set this up well." No skill ceiling. | Minimal |
| **Relatedness** (connection, belonging) | The bunker represents your relationship with your AI team — you can see what they're doing, feel the connection to their work. | Core |

### User Type Appeal

- [x] **Achievers** — watching task completions accumulate, rooms unlocking
  as the team grows
- [x] **Explorers** — understanding what agents have been doing; reading
  the bunker's state
- [ ] **Socializers** — N/A, single-user
- [ ] **Competitors** — N/A, no competition

### Flow State Design

This is a tool, not a game. Flow comes from watching a satisfying system
run, not from challenge matching skill.

- **Onboarding**: Open the bunker — Commander's Room is immediately visible,
  agent status shows within seconds, no tutorial needed
- **Difficulty scaling**: N/A — no challenge design required
- **Feedback clarity**: Every task completion has a clear visual + audio
  event; agent state is always legible at a glance
- **Recovery from failure**: No failure state — if an agent errors, the
  room shows a dull red alert state; no penalty, just information

---

## Core Loop

### Moment-to-Moment (30 seconds)

An agent is visibly working in its room — animated character, room detail
active, subtle ambient motion. When a task completes: a satisfying visual
pulse and audio beat. A new task begins automatically. The bunker is never
still; it breathes.

### Short-Term (5 minutes)

Open the bunker. Scan the Commander's Room — see current status, recent
completions. Adjust one parameter or assign a new task (light
configuration). Step back. Watch the bunker work through it. Feel the
completion beat. Close.

### Session-Level (2–10 minutes)

Come back to the bunker. See what agents completed while you were away —
completed tasks leave visible traces in their rooms. Reconfigure if needed.
Watch for a few minutes. Leave satisfied. The bunker doesn't demand you
stay; it rewards you when you check in.

### Long-Term Progression

The bunker starts with one room: the Commander's Room. As the user's AI
agent team grows, new rooms unlock — each new agent earns a room. Rooms
accumulate history. The bunker becomes richer and busier over time, a
living map of the user's growing AI operation.

### Retention Hooks

- **Curiosity**: What did my agents do while I was away? The bunker shows
  the answer immediately.
- **Investment**: The bunker represents the user's actual work and actual
  agent team — it's meaningful, not fictional.
- **Mastery**: N/A — no skill progression. Retention comes from utility,
  not game mechanics.

---

## Game Pillars

### Pillar 1: Alive by Default
The interface is never static. Agents animate, status updates in real
time, the bunker breathes. If something isn't animated, it's not finished.

*Design test*: Between a static information panel and an animated agent
state, always choose the agent. If we can't animate it, reconsider whether
it belongs in the bunker at all.

### Pillar 2: Readable at a Glance
Every piece of information is legible without any interaction. Understand
the state of the entire agent team in under 5 seconds. Interaction is
optional, never required.

*Design test*: If a feature requires clicking to understand, it's not done.
Add an ambient visual that communicates the same thing passively.

### Pillar 3: Satisfying Feedback
Every meaningful event — task complete, agent status change, new work
started — has a deliberate visual and audio beat. The tool rewards you for
watching it.

*Design test*: Does this event have a sound and an animation? If either is
missing, it's not done.

### Pillar 4: Commander Always Home
The user's own overview is always accessible and always current. The
Commander's Room is the ground truth. You never feel lost in your own
tool.

*Design test*: Can the user find their own status within one second of
opening the bunker? If not, surface it.

### Pillar 5: Earn Each Room
Add rooms only when an agent exists to fill them. The tool grows with the
team, not ahead of it. Depth before breadth.

*Design test*: Is a room being added because an agent needs it, or because
it would look cool? If the latter, wait.

### Anti-Pillars (What This Is NOT)

- **NOT a chatbot interface**: No NPC-style dialogue or chat input. Agent
  status is visualized, never conversational. This violates "Readable at
  a Glance."
- **NOT charts or graphs**: No numeric data visualization. Information is
  spatial, animated, and ambient — not tabular. This violates "Alive by
  Default."
- **NOT mandatory interaction**: The bunker should look alive and current
  with zero daily maintenance. You open it, it's already running.
- **NOT speculative rooms**: No rooms built in anticipation of future
  agents. One room at a time, earned by real agents. This violates "Earn
  Each Room."

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- |---- |
| Minecraft | Underground exploration, systems that work, the satisfaction of automation | No gameplay challenge — this is a tool, not a game | Validates the underground atmosphere and the system-comes-alive moment |
| Terraria | Room-based world design, visual density, top-down underground spaces | 2D top-down (not side-scrolling), real data not fictional | Validates the room-as-unit-of-meaning metaphor |
| Fallout (Vaults) | Institutional underground aesthetic, retro-futurist palette, amber terminal lighting | No narrative, no survival — pure interface | Validates the visual direction and institutional warmth |
| Factorio | The satisfaction of watching a running system; readable at a glance | No building mechanics — the bunker is a view, not a construction | Validates the "readable factory floor" as a model for information display |

**Non-game inspirations**:
- NASA Mission Control — the calm authority of a room full of activity, where
  each station is someone's domain
- Unix terminal aesthetics — calm, functional, alive; information density
  without visual noise
- Industrial control rooms — physical dashboards with status lights,
  analogue meters, always-on displays

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **User** | The developer themselves — this is a personal tool |
| **Context** | Building and managing a real AI agent team for development work |
| **Session pattern** | Opens when starting work; checks in periodically; uses alongside other tools |
| **Current tools** | AI agent APIs, terminals, code editors — clinical and functional |
| **Unmet need** | A management interface that feels alive and satisfying, not dead and clinical |
| **Dealbreaker** | Anything that adds friction, requires maintenance, or feels like another thing to manage |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | TBD — run `/setup-engine`. Godot 4 is a strong candidate: free, excellent 2D, exports to web, HTTPRequest for API integration. |
| **Key Technical Challenges** | (1) Data bridge: connecting game engine to real AI agent APIs/websockets. (2) Visual legibility: communicating agent state through animation alone, without text or charts. |
| **Art Style** | Pixel art, 2D top-down, 16–32px characters and tiles |
| **Art Pipeline Complexity** | Medium — custom pixel art, character animations (idle, working, completed), room tile sets |
| **Audio Needs** | Moderate — ambient bunker loop, distinct completion beat per agent type, alert sound |
| **Networking** | None (multiplayer) — local HTTP/websocket calls to AI agent services |
| **Content Volume** | MVP: 1 room, 1 agent, 1 animation set. V1: 3–5 rooms, per-room tile variants. |
| **Procedural Systems** | None — rooms are hand-designed, not generated |

---

## Risks and Open Questions

### Design Risks
- Passive observation may become wallpaper — the bunker looks pretty but
  stops being meaningfully informative after the novelty fades
- Visual metaphor may not be legible enough — without charts, users may
  not be able to read complex agent states at a glance

### Technical Risks
- Data bridge between game engine and real AI agent APIs is the hardest
  engineering problem in the MVP — must be solved before anything else
- First-time developer building both a game-like interface AND a real tool
  simultaneously — scope risk is high

### Market Risks
- N/A — personal tool, not commercial

### Scope Risks
- Aesthetic seduction: easy to spend weeks perfecting the bunker's look
  and never connect real data — the data bridge must come first
- Feature creep: the bunker concept invites expansion; "Earn Each Room"
  pillar must be enforced strictly

### Open Questions
- **What engine/stack?** Resolved by running `/setup-engine`.
- **How does the data bridge work?** MVP prototype must test this first —
  before any art is produced.
- **What does "agent status" mean visually?** Each state (idle, working,
  completed, errored) needs a distinct animation — needs prototype to
  validate legibility.

---

## MVP Definition

**Core hypothesis**: A top-down bunker room with an animated Commander
and one live agent data feed feels more satisfying and alive than a
traditional status dashboard.

**Required for MVP**:
1. Commander's Room — one room, ambient animation, always active
2. One live data connection — one AI agent's status updating in real time
3. One task completion beat — a distinct visual pulse and audio beat when
   the agent completes a task

**Explicitly NOT in MVP**:
- Multiple rooms
- Complex per-room visualizations
- Polished pixel art — placeholder sprites are fine to validate the concept
- Audio beyond a single completion beat
- Character movement or pathfinding
- Configuration UI inside the bunker — configure externally for MVP

### Scope Tiers

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | Commander's Room only | Ambient animation, 1 live data source, 1 completion beat | 2–3 weeks |
| **V1** | 3–5 rooms | Each agent has a room, rooms reflect agent specialization visually | 2–3 months |
| **Full Vision** | Unlimited rooms | Rooms grow and change as agents mature; bunker history visible | Ongoing |

---

## Next Steps

- [ ] Run `/setup-engine` to configure engine and populate version-aware reference docs
- [ ] Run `/art-bible` to create the visual identity specification before writing GDDs
- [ ] Run `/design-review design/gdd/game-concept.md` to validate concept completeness
- [ ] Decompose concept into systems with `/map-systems`
- [ ] Author per-system GDDs with `/design-system`
- [ ] Plan technical architecture with `/create-architecture`
- [ ] **Prototype the data bridge first** — validate that the engine can receive
  real agent status before building any art
- [ ] Run `/playtest-report` after prototype to validate the core hypothesis
- [ ] Plan first sprint with `/sprint-plan new`
