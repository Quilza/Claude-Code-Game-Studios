# Art Bible: The Situation Room

*Created: 2026-05-08*
*Status: Complete — AD-ART-BIBLE skipped (Lean mode)*
*Engine: Godot 4.6.2 — Pixel Art 2D, Top-Down*

---

## Section 1: Visual Identity Statement

### One-Line Visual Rule

> *"Every pixel earns its place by doing a job — if it isn't telling the player something, it shouldn't be there; and if it IS there, it should feel like it has been there for twenty years."*

This rule resolves ambiguity in both directions: it cuts decoration that has no informational function, and it demands that functional elements carry material weight and history.

### Supporting Visual Principles

#### Principle 1 — Functional Patina

Every surface and object reads as institutional hardware that has been running continuously — worn at the edges, labeled with tape, warm from use — not as a designed interface.

*Design test*: When choosing between a clean tile and a worn tile, choose the worn tile — unless it reduces legibility below the 5-second read threshold.

*Pillars served*: Alive by Default (patina implies ongoing operation); Earn Each Room (inhabited rooms, not installed ones)

#### Principle 2 — Operational Color

Color carries exactly one type of information: system state. Amber = resting/idle, green = active/healthy, red = alert/error. Any color used outside this language must be eliminated regardless of aesthetic appeal.

*Design test*: When a new element needs a color, ask "what state does this communicate?" If the answer is "none, it just looks good" — make it grey or amber-neutral.

*Pillars served*: Readable at a Glance (state legible in under 5 seconds); Commander Always Home (overview reads without clicking)

#### Principle 3 — Mechanical Confession

Every system — pipes, vents, wiring, status lights, cable runs — must be visibly connected to something real in the room, so the user can trace cause to effect by eye alone.

*Design test*: When deciding whether to show pipe routing between conduit and workstation, show the routing — legible cause-and-effect beats visual tidiness, always.

*Pillars served*: Satisfying Feedback (visible connections give weight to task completion); Readable at a Glance (cause-and-effect tracing replaces the need to click)

---

## Section 2: Mood & Atmosphere

### Foundational Baseline — The Cozy Bunker

Every state shares an underlying warmth. The baseline is amber at ~2700K (incandescent tungsten, not daylight). Surfaces are worn concrete, brushed steel, and rubber cable — they hold heat visually even when quiet. No state ever goes fully cold or clinical. The bunker is a home first; states modulate from there.

### State 1: Ambient Running

**Primary emotion**: Quiet confidence — a well-maintained machine doing exactly what it was built to do. No drama, no attention required.

**Lighting**: 2700K amber-warm. CRT monitors and status indicators cast amber pools. Low-medium contrast; shadows are soft. Amber underglow from floor-level indicator strips — never fully dark, never dominated by one source.

**Atmospheric descriptors**: Humming. Patient. Inhabited. Warm-dim. Purposeful.

**Energy level**: Measured. Indicator blinks at 2–3 second intervals; motion is deliberate and patterned.

**Key visual**: Agent workstation indicators pulse at 0.5Hz — slow, like breathing. Pulses are not synchronized across workstations; they drift in and out of phase, suggesting independent organisms in a shared space.

---

### State 2: Task Completion

**Primary emotion**: The click of a tumbler falling into place. Not celebration — the deep satisfaction of a mechanism doing its job correctly. Earned and brief.

**Lighting**: Momentarily shifts from 2700K toward 4000K neutral-warm green. The completing agent's room brightens ~40% in luminance, then eases back over `COMPLETION_RETURN_DURATION` seconds. Surrounding rooms remain at ambient; the contrast is spatial — one bright room among dim ones. A green ripple travels outward along visible pipe/cable runs and dissipates at the room boundary.

**Atmospheric descriptors**: Decisive. Resonant. Clean. Brief. Weight-bearing.

**Energy level**: Single sharp spike from measured to heightened, then controlled return to measured.

**Key visual**: Status indicator switches from amber-pulse to solid green hold for 3 seconds, then returns to amber-idle. Solidity (no pulse, no flicker) = completion. Movement = working; stillness in green = done.

**Tuning knob**: `COMPLETION_RETURN_DURATION` — range 1.2–2.0 seconds. Default: 1.5s. Tune in prototype to avoid feeling cheap (too short) or disruptive (too long).

---

### State 3: Agent Idle

**Primary emotion**: Comfortable waiting — a skilled worker sitting with hands folded, ready but not restless. Nothing is wrong.

**Lighting**: Drops slightly from 2700K toward 2400K — imperceptibly cooler, as if the workstation's heat has subsided. Dims to 60% of ambient running level. CRT monitor shows slow-scrolling amber terminal prompt with slight flicker.

**Atmospheric descriptors**: Subdued. Patient. Still. Warm-dim. Latent.

**Energy level**: Contemplative. Character animation slows; indicator blink drops to 0.25Hz.

**Key visual**: CRT monitor shows a single blinking cursor at 1Hz (500ms on / 500ms off). Everything else in the room is still. The cursor is proof-of-life and the universal signal for "waiting."

---

### State 4: Alert / Error

**Primary emotion**: Controlled urgency — a skilled operator notices a reading out of range and turns toward it. Not panic; not alarm. Closer to a low oil pressure light than a smoke alarm.

**Lighting**: Affected room shifts to 3200K with dull burnt sienna (#C0392B, heavily desaturated — never pure red). Pure red = emergency; desaturated = warning. Adjacent rooms retain amber baseline. Shadows in the error room are harder; the room feels harsher and less comfortable. Alert indicator pulses at irregular 1.5Hz (±20% gap variation — the system is trying to get attention without knowing how).

**Atmospheric descriptors**: Clipped. Deliberate. Dissonant. Contained. Insistent.

**Energy level**: Elevated but controlled. Agent animation shifts to "stopped" — work flow interrupted, not chaotic.

**Key visual**: Pipe/cable run indicator dots that normally animate along infrastructure freeze or reverse at the point of failure. The infrastructure interruption is physically visible — you can see where the chain broke.

---

### State 5: Startup / Wake

**Primary emotion**: Familiar ritual — the first cup of coffee before the day begins. Not drama; reliable. The user should feel the bunker is always intact, always ready.

**Lighting**: Begins at 1800K deep amber (near-firelight) and advances to 2700K ambient over 8–12 seconds. Floor-level amber indicator strips illuminate first, giving the bunker shape before detail. Rooms boot sequentially in order of last activity; Commander's Room first.

**Atmospheric descriptors**: Gradual. Reliable. Waking. Sequential. Grounded.

**Energy level**: Hushed, building to measured. No overlapping sounds — each room has a moment of quiet before the next begins.

**Key visual**: CRT monitors warm up one at a time with a single horizontal scan-line settle (phosphor warm-up, 0.5 seconds per monitor). Cannot be skipped. This is the "coming home" beat — the universal signal of trusted old hardware starting correctly.

---

### State 6: Commander Focus

**Primary emotion**: Command clarity — reviewing a status board knowing exactly where everything stands. Attention narrows. This is what the whole tool exists to deliver.

**Lighting**: Commander's Room brightens to 3000K (slightly cooler and brighter than ambient). Adjacent rooms dim 20% in luminance, creating a natural vignette around the focal room without artificial UI framing. The Commander's Room overhead strip — the only 3200K neutral-white source in the tool — activates, marking this room as the operational center.

**Atmospheric descriptors**: Clear. Purposeful. Centered. Focused. Authoritative.

**Energy level**: Contemplative but alert. Room activity continues at normal speed; the perceptual slowdown from dimmed surroundings supports reading.

**Key visual**: The wall-mounted summary status board (showing all agent states as indicator rows) increases glow by 30% in Commander Focus. Always present; in this state, impossible to miss.

**Implementation note**: Commander Focus requires tracking "is the user focused on Room 1" as an explicit state — this enables the adjacent room dimming. If this proves too complex for MVP, fall back to passive: Room 1 brightens without dimming others.

---

### State Differentiation Summary

| State | Temp | Contrast | Dominant Color | Energy |
|-------|------|----------|----------------|--------|
| Ambient Running | 2700K | Low-med | Amber | Measured |
| Task Completion | 2700K→4000K pulse | Momentarily high | Amber→green | Spike then return |
| Agent Idle | 2400K | Low | Amber dim | Contemplative |
| Alert / Error | 3200K | Med-high | Burnt sienna | Elevated, controlled |
| Startup / Wake | 1800K→2700K | Low→ambient | Deep amber | Hushed, building |
| Commander Focus | 3000K (room) | High (room) | Neutral-warm white accent | Contemplative, alert |

---

## Section 3: Shape Language

### 3.1 Character Silhouette Philosophy

**Unique custom designs.** Every character — the Commander (a visual representation of the user) and each AI agent — has a fully custom character design. The art bible does not prescribe specific design elements (headgear, props, clothing). Character design work happens per-character, post-art-bible.

**The non-negotiable rule: silhouette distinctiveness at thumbnail scale.** At 16–32px top-down scale, characters are read as silhouettes, not faces. Every character must be identifiable from other characters by outline alone — no color, no detail, silhouette only. If two characters look the same at 16px thumbnail, they must be revised before entering production.

**State readability through shape.** Character state is legible by hand prop position and body asymmetry — not color alone:
- **Working**: One or both hand props extended toward workstation. Silhouette is asymmetric.
- **Idle**: Props pulled in close. Silhouette approximates a compact shape.
- **Alert**: Props dropped or one raised. Head orientation shifts toward the problem (indicated by a 1-pixel highlight dot on the leading edge of the head).

This means state changes are shape changes first. A colorblind user at 1× zoom reads the state from asymmetry, not from the indicator light color. Color reinforces; shape carries the primary signal.

*Pillar alignment*: Readable at a Glance, Satisfying Feedback

---

### 3.2 Environment Geometry

**Primary rule: rectangular first, imperfect always.** Rooms are fundamentally rectangular — hard 90° corners, axis-aligned walls. This is the institutional rule: the bunker was built by an engineering team on a budget, not an architect.

**The imperfection rule.** Every wall run longer than 8 tiles must have at least one of: a pipe seam, a mounted bracket or panel, or a discoloration patch. These are not decorative — each one marks a seam in construction, a serviced point, a patch job. Warmth lives in texture variation, not geometry. The geometry is cold and correct; the surface variation is warm and lived-in. They do not need to be unified — that contrast is precisely what reads as bunker.

**Floor rule.** Floors use a 2×2 tile repeating base module: either a concrete slab-edge seam or industrial slip-resist striping. Never carpet, wood, or residential material. Always poured or laid industrial surface.

**Doorways.** Always rectangular, always exactly 2 tiles wide. Metal frame surround: 2px of frame each side, 1px threshold strip on the floor. No arches, no rounded tops. The door is a pressure door — it looks like it seals. Open plan is not permitted: every transition between rooms is a framed threshold. Rooms must be distinct bounded domains.

**Room border rule.** Interior wall meets floor with a 1px shadow strip (one tone darker than floor). Exterior wall has no shadow — it is the structural shell, not perceived as having depth. Interior = depth; boundary = solid.

*Pillar alignment*: Mechanical Confession, Earn Each Room, Alive by Default (patina implies habitation)

---

### 3.3 UI Shape Grammar

**Information lives in the HUD overlay, not in the rooms.** Rooms are atmospheric/aesthetic. The HUD overlay is where agent status data is displayed — separate from the in-world visual. The Commander's Room is a character space; no data boards or status walls are placed inside rooms.

**The HUD uses the same geometry as the world, different register.** HUD panels use the same 90° corners as room walls. HUD status bars use the same width as door frames. The HUD feels installed in the bunker, not overlaid on top of it. No rounded corners. No soft shadows. All HUD corners are 90°; all panel edges are 1px hard lines.

**Three-glyph state vocabulary** (used in HUD overlay for agent status rows):
- `●` **Dot** (4×4px filled circle) — agent connected and reporting. Resting baseline.
- `▬` **Rect pulse** (6×4px horizontal rectangle, extending/contracting at 0.5Hz) — task in progress. Elongated shape signals directed effort.
- `+` **Cross-plus** (3×3px, plus sign, 1px thick) — error/alert. A `+` is a flag requiring response; an `×` implies user-initiated cancellation. These are different meanings. Never use `×` for error state.

No text labels in status rows. HUD reads by shape alone. Shape + color = dual-channel accessibility: a colorblind user can still read state from shape. Design test: remove all color from the status row — can you read dot vs. rect vs. cross? If yes, the glyph set passes.

*Pillar alignment*: Readable at a Glance, Commander Always Home

---

### 3.4 Hero Shapes vs. Supporting Shapes

**In top-down view, hierarchy = mass × brightness.** Z-level compression removes "big thing in front." Hero elements have more visual mass (larger footprint) AND higher brightness than supporting elements.

**Three-tier hierarchy:**
1. **Tier 1 — Hero objects** (workstations, primary terminals): 3×3 tiles or larger footprint. Maximum brightness. Maximum contrast edges. Eye lands here first in any room.
2. **Tier 2 — Functional objects** (chairs, secondary terminals, storage): 1×2 or 2×2 tile footprint. Mid-brightness. 1px outlines.
3. **Tier 3 — Infrastructure** (pipes, cables, vents, status lights): 1×1 tile footprint or 1px runs. ≤60% of floor mid-tone luminance. No outlines — drawn in terrain rather than as discrete sprites.

**The tier rule**: tier is determined by footprint AND brightness together, not either alone. A large-footprint low-brightness table = Tier 2. A small-footprint high-brightness indicator = Tier 1. Adjust both axes when an element's tier feels wrong.

**The Commander's Room exception.** The Commander's Room is a character/aesthetic space — the hero object is the workstation. No additional hero elements compete with it. Information is delivered via HUD overlay, not in-room displays.

*Pillar alignment*: Readable at a Glance (hierarchy resolves in 5 seconds); Functional Patina (Tier 3 infrastructure recedes — "always been there")

---

## Section 4: Color System

### 4.1 Primary Palette

The palette divides into two registers: **World** (rooms, surfaces, infrastructure, characters) and **HUD** (overlay, status, interface). Semantic state colors (S1/S2/S3) are identical in both registers — state must mean the same thing regardless of which layer communicates it.

| Name | Approx Hex | Register | Role |
|------|-----------|----------|------|
| **W1 Bunker Stone** | `#2A2218` | World | Deep shadow, warm near-black. Floor in unlit rooms, deep corners, underside of workstations. |
| **W2 Institutional Grey-Warm** | `#4A4035` | World | Primary wall and floor surface. The neutral background against which all semantic colors read. Flat and non-competing. |
| **W3 Worn Metal** | `#6B5E4A` | World | Door frames, workstation chassis, conduit runs, bracket hardware. Aged brushed steel. |
| **S1 Amber Idle** | `#D4882A` | Shared | "The bunker is breathing." Baseline living color — indicator lights at rest, CRT screen glow, HUD dot glyph. |
| **S2 Active Green** | `#5BAD63` | Shared | "Signal is live." Warm-shifted oscilloscope green — task in progress, completion pulse, HUD rect glyph. |
| **S3 Alert Sienna** | `#A03520` | Shared | "Something requires a decision." Burnt sienna — error/alert state, HUD cross-plus glyph. |
| **H1 HUD Panel Ground** | `#1C1810` | HUD | Background surface of all HUD panels. Slightly darker than W1 — distinct register without cool divergence. |
| **H2 HUD Border** | `#3A3028` | HUD | 1px panel borders and rule lines. Never used as a fill. |

**Shared color rule**: S1, S2, S3 must be the same hex in world and HUD. If they diverge in tone, users will reasonably wonder if they represent different states. They do not.

---

### 4.2 Semantic Color Usage

**S1 — Amber Idle** (`#D4882A`)
Amber is the color of a machine that has been running so long it is warm to the touch — tungsten filaments, vacuum tube heaters, analogue indicator lights. Idle does not mean off; it means continuously waiting, continuously ready. When everything is amber, everything is nominal.

*Idle dim rule*: In Agent Idle state, same hue as S1 but luminance drops to ~60%. Do not shift hue toward orange or yellow — only reduce brightness. Hue constancy is what makes "dim amber" read as "same state, less energy" rather than "different state."

**S2 — Active Green** (`#5BAD63`)
Green is the working color of analogue instrumentation: oscilloscope traces, radar displays, CRT phosphors under active signal. Green means "signal is live, process is in motion" — not "task succeeded." An agent can be green on a task that hasn't completed yet. The warm shift (note the `9A` in the hex rather than a balanced `4A`) prevents the green from reading as a cool foreign object in an amber room.

*Color system reconciliation*: Section 2 references "4000K neutral-warm green" for the Task Completion pulse. This maps to S2 (`#5BAD63`) at full luminance for the completion flash, returning to S1 amber over `COMPLETION_RETURN_DURATION`. The "4000K" description refers to color temperature impression, not a literal light temperature — S2 is the specific production value.

**S3 — Alert Sienna** (`#A03520`)
Burnt sienna rather than pure red. Hue ~10–15° on standard 0–360° wheel, saturation ~65%, luminance ~35–40%. The emotional register of the bunker is "controlled operational environment" — NASA Mission Control, not a burning building. Pure reds communicate "evacuate." Sienna communicates "notice this, decide what to do." Visual reference: old rust on a steel door. If the alert color looks like a warning label or stop sign, it is too saturated.

*Contrast requirement*: All three semantic colors must achieve minimum 4.5:1 contrast ratio (WCAG AA) against W2 (`#4A4035`) in the world and H1 (`#1C1810`) in the HUD. Alert sienna is most at risk against warm grey walls — if contrast fails, raise luminance, not saturation.

---

### 4.3 Colorblind Safety

**At-risk pair**: S2 (active green) and S3 (alert sienna) — for deuteranopes (green-weak, most common form), desaturated green and red-orange can collapse to near-identical brownish tones.

**The three-glyph system provides sufficient shape backup** (confirmed by the design test in Section 3.3 — glyphs are readable in silhouette alone):
- ● Dot (compact, closed) = S1 amber idle
- ▬ Rect-pulse (elongated, animated) = S2 active green
- + Cross-plus (branching, static) = S3 alert sienna

**Animation is a third channel**: the ▬ rect-pulse is animated (0.5Hz) while the + cross-plus is static. Color + shape + motion = three independent channels. No additional accessibility backup is required provided the animation is preserved.

**Implementation requirement**: the ▬ animation is not cosmetic — it is an accessibility channel. It must not be removed as a performance optimization.

**World-layer gap (documented as intentional)**: Room-level color shifts (green flash on completion, sienna on error) have no shape glyph attached. Deuteranopes cannot distinguish rooms by color alone. The HUD overlay (glyph-backed) is the accessible ground truth; room color is an ambient supplement. The architecture that places state data in the HUD rather than room walls is correct accessibility design.

---

### 4.4 Prohibited Colors

1. **Pure saturated reds** — saturation above ~75% (hex range `#CC0000`–`#FF4444` and variants). Pure red = evacuation. The bunker uses sienna for alerts.

2. **Cool blues and cyans** — hue range ~180°–250° at saturation above 20%. These read as "modern SaaS dashboard" or "sci-fi hologram." Both break institutional warmth. Replace any blue "network/connection" metaphors with amber-pulse animation instead.

3. **Pure white and near-white** — any value above ~`#D8D8D8` (luminance above 85%). Pure white is clinical and modern. The brightest surface in the bunker (Commander's Room strip in Focus state) is warm-white, not neutral white.

4. **Saturated yellows and lime greens** — hue range ~60°–140° at saturation above 60%. Includes lemon yellow, chartreuse, lime green. These read as "generic game UI success/warning" and override the amber/green/sienna state language.

5. **Gradients and soft shadows in HUD** — HUD fills are flat. HUD edges are 1px hard lines. No drop shadows, no glow blur, no feathered edges. The only permitted glow is the pixel-art dithered halo around world-layer indicators (amber/green/sienna bloom) — not a shader blur.

6. **Pure black** — `#000000` and any value below ~`#151210`. Pure black has no warmth and reads as UI void. The deepest permitted shadow is W1 (`#2A2218`).

---

## Section 5: Character Design Direction

### 5.1 Visual Archetype Targets

**Every character has a fully custom design.** This section gives direction to a character artist — it does not prescribe specific props, headgear, or clothing. It gives constraints.

#### The Commander

The Commander is the user made visual. The design brief is: "make something that reads as the person operating this room from outside looking in."

- **Positional authority through stillness.** Agent characters are defined by work posture — props extended toward a task. The Commander's default posture implies *survey* rather than *execution*. This is a character overseeing jobs, not doing them.
- **Slightly more visual mass than any single agent.** In top-down 2D, authority reads through mass and footprint. The Commander's silhouette should feel planted — wider shoulder profile, heavier prop elements, or a shape that reads as dense rather than compact.
- **Architecturally distinct from all agent types.** When the Commander and agents appear in overview together, the Commander resolves immediately without scanning. The silhouette must be different from every agent type, not just one.

#### Agent Archetypes (General Framework)

Five starting archetypes — update per specific agent when added. Each is a brief for the character artist, not a design:

| Archetype | Function | Visual language |
|-----------|----------|----------------|
| **Research** | Scans and synthesizes | Broad, open posture; wide/flat prop; reading-toward-a-surface feel |
| **Writing/Generation** | Produces output | Directed, linear; single forward-pointing tool; energy going one way |
| **Monitoring/Watchdog** | Watches environment state | Rotational/scanning; props extend in multiple directions; peripheral awareness |
| **Integration/Connector** | Moves data between systems | Props extend in two opposing directions; conduit/relay silhouette |
| **Specialist/Execution** | Performs specific technical task | Compact, precise; single controlled prop held close |

Agents not mapping cleanly to these archetypes should get a new brief from the art director before design begins.

---

### 5.2 Silhouette Distinctiveness Rules

**The thumbnail test.** At 16px top-down, characters are silhouettes: head mass, prop direction, and overall outline. Faces, clothing details, and small props are invisible. Design for the 16px silhouette first.

**What survives at 16px**: overall mass distribution, prop extension count and direction, head/apex prominence, compactness vs. spread.

**What does not survive at any zoom**: face features (camera looks down), foot/shoe design, insignia below 4×4px, clothing textures using more than 2 tones. Do not invest character artist time in any of these.

**The five silhouette axes.** Every character must differ from every other on at least 2 of these 5 axes:

| Axis | What to vary |
|------|-------------|
| **Mass** | Footprint weight — wide, narrow, dense, or sparse? |
| **Props** | Number, direction, and general shape of extending elements |
| **Apex** | Dominant top element (head feature) — how prominent vs. body? |
| **Symmetry** | Roughly symmetric, or notable asymmetric feature? |
| **Texture edge** | Outline smooth (curves), angular (hard direction changes), or notched (deliberate cutouts)? |

**New character test** (must pass before entering production):
1. Render at 16×16px, silhouette only (solid fill, neutral background)
2. Place alongside all existing silhouettes at same scale
3. Is the new character immediately identifiable? Is no existing character confused with it?
4. If any collision — revise the new character, not the existing ones

**Anti-collision rule**: no two characters may share the same combination of mass + prop direction.

---

### 5.3 Expression and Pose Direction

**Personality is body language, not face.** Top-down view eliminates all facial expression. Character personality reads through: body lean direction, prop position, asymmetry degree, and animation cadence. Each character has idiosyncratic movement patterns — defined per character and consistent across all states.

#### Three Animation States

**Working** (4–6 frame cycle)
Directed effort. Asymmetry is the defining quality — one axis of effort, one direction of attention. Animation shows rhythmic prop oscillation or minor body rock. Not a full-body animation — stillness in most of the body, motion in one or two pixels of the prop or head region. Frame count of 4–6 allows expressiveness while maintaining readability.

**Idle** (0–1 frame variation)
Working pose at rest — props retracted, lean neutralized. Looks like "paused," not "uninstructed." Only permitted idle animation: very slow single-pixel head-region variation at 0.25Hz or slower. No prop animation in idle.

**Alert** (1-frame snap, hold)
Working pose interrupted. Props drop or rotate. Head-region gaze dot (1px highlight) shifts toward alert source. Body does not fully reorganize — looks like someone noticed something mid-task. Alert is never animated or eased. The snap is the animation; the hold communicates "awaiting instruction."

#### State Transitions

| Transition | Duration | Feel |
|-----------|----------|------|
| Working → Idle | 3–5 frames (gradual) | "Task concluded, returning to ready" |
| Idle → Working | 2–3 frames (fast) | "New task received, immediately engaged" |
| Any → Alert | 1 frame (instantaneous) | "This needs attention now" — never eased |
| Alert → Idle | 5–8 frames (controlled return) | "Acknowledged, assessing" |

---

### 5.4 LOD Philosophy

**1× zoom drives all design decisions.** The overview/playable resolution (~16–24px effective) is the primary read. 2× zoom (~32–48px) is secondary.

**Mandatory at 1×** (must drive design):
- Silhouette mass and shape
- Working/idle/alert state (prop position + body asymmetry)
- Gaze dot direction in alert state (1px head highlight)
- Character identity among all other characters (silhouette test)

**Available at 2×** (may be invested in, must not compromise 1× clarity):
- Secondary prop shape detail (joint articulation, tip shape)
- A secondary distinguishing silhouette element
- Subtle color variation (max 2 additional tones beyond base)
- Minor surface texture on props or body

**Never invest in at any zoom**: face features, back-of-head, feet, sub-4px insignia, clothing textures requiring more than 2 tones. If a character artist is working on any of these, stop and check before continuing — invisible work is wasted work.

---

## Section 6: Environment Design Language

### 6.1 Architectural Style

All rooms are rectangular with axis-aligned walls — built under budget pressure by people who expected to use them, not by architects. The geometry is institutional and correct; texture variation provides warmth.

No construction-era system. Every room uses the same surface vocabulary. Visual age is not tracked — instead, rooms are distinguished by operational state: active, idle, or unused. See Section 6.4.

---

### 6.2 Texture Philosophy

**Mandatory baseline surfaces — every room, no exceptions:**

1. **Floor**: 2×2 tile repeat module using a W1/W2 dithered 2-tone pattern. Creates the impression of poured concrete or industrial rubber grid without introducing new colors. Seams between tiles: 1px W1 line. Repeat is exact — no rotation, no flip.
2. **Wall mid-section**: W2 flat fill. No gradient. Texture variation comes from surface marks (below), not tone variation.
3. **Wall-floor shadow strip**: 1px W1 immediately above the floor tile, the full length of every interior wall including doorway reveals. Universal and never skipped.
4. **Conduit channel**: Every conduit run >3 tiles lives in a 2px W1 recessed channel. Conduit itself is a 2px run in W3. Channel is 1px wider than conduit on each side — conduit has a slot, it doesn't float.

**Texture variation techniques within the approved palette:**
- **Dithered transition**: 2×2 W1/W2 checker at wall corners and floor-wall edges. Produces an apparent mid-tone without a third color.
- **Single-pixel mark**: 1px dot or 1×2 dash in W3 on W2 wall. Reads as bolt head, rivet, or imperfection. Must be irregularly spaced.
- **Recessed panel**: 1px W1 border on a W2 surface. Defines conduit access panels and junction boxes without adding mass.
- **Stain strip**: 1×(n) run of W1 pixels at the base of a wall tile. Reads as moisture wicking or oxidation bleed. Maximum 2px tall per mark.
- **Worn edge**: Top pixel row of floor tile replaced with W3. Reads as a scuff line where equipment has been dragged. Use sparingly — maximum 2 per room.

**Prohibited texture techniques:**
- No alpha-blended overlays — all texture is solid pixel marks
- No pattern repeating at regular intervals visible at room scale — vary offsets
- No texture applied in perfectly straight horizontal or vertical bands — age is irregular

**When does a surface get worn vs. stay clean?**
- Always worn: floor tiles on the primary movement path (door-to-workstation 2-tile corridor)
- Worn by contact: surfaces directly adjacent to the Hero workstation chassis
- Worn by position: lower wall sections (bottom 2 tile rows) accumulate more stain marks than upper sections
- Clean by position: upper wall sections (top tile row), ceiling if visible
- Unused rooms: no worn marks at all — see Section 6.4

---

### 6.3 Prop Density Rules

**Density target: moderate, biased sparse.** Every prop must answer: "What task does this serve?" If the answer is "fills space" or "adds visual interest" — remove it. Visual interest is the job of surface texture and lighting.

**Mandatory — every room:**
1. One Hero workstation (Tier 1, 3×3 or larger). Determines the room's axis of attention.
2. One power conduit termination point — the conduit run must visibly connect to the workstation chassis.
3. At least one Tier 3 infrastructure element — a cable run, vent grate, pipe segment, or status indicator strip. Mechanical Confession made mandatory.

**Optional — per room type:**
- Secondary terminal (Tier 2, 2×2) — only if the agent's function warrants a second data surface
- Storage unit (Tier 2, 1×2 or 2×2, against a wall, never blocking the movement path) — for high-input-volume agent rooms
- Ambient indicator panel (Tier 3, 1×1 or 1×2, wall-mounted) — only if a second status read-point is justified by the room's function
- Paper stack or data tray (Tier 2, 1×1, on workstation) — only where "data" is a plausible physical metaphor

**Forbidden — all rooms:**
- Chairs, couches, or residential seating — the bunker is institutional in its furniture
- Plants, decorative items, personal photographs, or non-institutional objects
- Any prop that blocks the 2-tile door-to-workstation path
- Diagonally placed props — all props are axis-aligned
- Duplicate Hero-tier objects in a single room
- Props with circular or curved footprints — all props are rectangular or L-shaped
- UI screens, data boards, or status walls inside any room — information is HUD only

---

### 6.4 Environmental Storytelling — Three Room States

**Three states must be readable from the environment alone, before any HUD glyph or status indicator is consulted:**

**Active Agent Room** — "Someone just stepped away for a moment"
- CRT monitor tile: lit screen state — amber phosphor, scrolling or cursor-holding
- Cable runs: taut, straight 1px lines to workstation (no sag marks)
- Conduit termination: 2px S1 amber bloom dot (pixel-art dithered halo)
- Floor: worn-edge marks on the movement path and under workstation
- Everything at functional position; nothing displaced

**Idle Agent Room** — "Patient standby"
- CRT monitor tile: dim — W2 surface with a single 2px S1 dot at center (cursor only, no screen glow)
- Conduit bloom: 1px halo instead of 2px (half intensity)
- Floor wear: same as Active — idle does not mean unused, wear accumulated during active periods remains
- Distinction from Active: luminance only — every S1 element in the room is at 60%. Looks like Active with the lights turned down.

**Unused / New Room** — "Held breath"
Three environmental absences that individually could be explained away but together resolve as "not yet lived in":
1. **No floor wear** — movement path tiles have the same texture as surrounding floor. Crisp seams. No worn-edge marks.
2. **No conduit bloom** — conduit run reaches the workstation but no amber dot at the terminal. Connection exists; no current flowing.
3. **Reduced surface marks** — 1–2 marks per 8×8 tile section vs. 5–8 in an active room.

Do not fill unused rooms with extra props to make them feel interesting. Sparseness is the information. Trust the absence.

**Visual age accumulation** (for milestone art updates, not real-time):
Floor wear → conduit bloom brightens → stain strips appear → additional surface marks accumulate. The room stops looking like it could be emptied. It looks like it has always been there.

---

## Section 7: UI/HUD Visual Direction

### 7.1 Diegetic vs. Screen-Space Approach

**Ruling**: The HUD is diegetically grounded — presented as a control panel overlay installed in the bunker, not as a glass UI layer floating above it.

**What "installed" means in pixel art terms:**

- **Corner treatment**: Every HUD panel has an inset 2px L-shape in H2 at each of the four corners (inside face). Same 90° bracket motif as workstation chassis in the world layer. Reads as "bolted in," not "designed."
- **Panel origin mark**: 1px S1 amber dot in each panel's top-left corner bracket. Echoes the conduit bloom dots at workstation power terminations. The HUD appears powered by the same system as the rooms.
- **Panel edge construction**: 2px borders — 1px outer edge H2 (`#3A3028`), 1px inner fill H1 (`#1C1810`). Machined lip, not a painted line.
- **Physical shadow**: HUD panels sitting over the world get a 1px W1 shadow offset on bottom and right edges only — a drop-cast shadow from an opaque physical object. 1px offset, 1px thickness, W1 `#2A2218`. No blur. One pixel.
- **No translucency**: HUD panels are opaque H1 fills. Not glass — physical panels. World behind them is occluded. A physical dashboard does not apologize for existing.

**Prohibited:**
- Panels that fade in from transparency (they materialize)
- Panels with gradient fills or alpha below 100%
- Rounded corners at any radius
- HUD elements with no mechanical relationship to the view

---

### 7.2 Typography Direction

**Monospaced bitmap font only.** Text is used exclusively where a glyph cannot carry the load. No bold, no italic, no anti-aliasing.

**Character set**: Single bitmap font, 5×7px character cell, 1px column gap, 6px advance per character. Reference aesthetic: VT100 terminal or 1980s CRT status readout — not a game UI font. Every character the same width. Amber-on-dark by default: S1 `#D4882A` on H1 `#1C1810`. State-carrying text (e.g., agent name in error state) uses the relevant semantic color on the character — never the background.

**When text vs. glyph:**

The rule: **glyphs carry state; text carries identity.**
- State (idle/active/alert) → always the three-glyph vocabulary. Never text, not even "ERR" or "OK."
- Identity (which agent is which) → text required. Agent ID of maximum 8 characters. The only mandatory text category.
- Dynamic counts/quantities → text permitted if range cannot be encoded in a glyph.
- Column headers and instructional labels → prohibited. If a status column needs a label to be understood, the glyph design has failed.

**Permitted size hierarchy:**

| Tier | Character cell | Role |
|------|---------------|------|
| S — Small | 5×7px | Primary: agent IDs, task counts, status row values |
| M — Medium | 5×9px | Section headers inside a panel — use sparingly |
| L — Large | 10×14px | Commander summary values — single number, one-glance read |

No sizes outside this set. No font smoothing. Hard pixel edges throughout.

**Agent ordering rule** (UX requirement): Agents must always appear in a consistent spatial position in the HUD. Position encodes identity — the glyph-only status system depends on it. Agent order is established on first connection and never changes during a session. Reordering requires explicit user action, not automatic reflow.

---

### 7.3 Iconography Style

**The design philosophy**: Every icon must pass the three-glyph test — readable in silhouette at 5×5px with no color. If a silhouette requires color or detail to be understood, it is an illustration, not an icon.

**What makes an icon belong in the bunker:**
- Derived from physical function, not metaphor. A power icon is a switch silhouette, not a lightning bolt. An agent icon is a top-down head silhouette.
- Geometric reduction — the minimum pixels for an unambiguous shape. Complexity is failure.
- Built on the same horizontal/vertical/45° grid as the world layer. No arbitrary diagonals or curves.

**Line weight rule**: All icons use 1px stroke, outline only. Exception: the three state glyphs (●/▬/+) are filled — filled = state data; outlined = function label. This hierarchy is non-negotiable.

**Maximum dimensions by HUD tier:**

| Tier | Max dimensions | Example |
|------|---------------|---------|
| Compact row | 5×5px | State glyphs, inline row indicators |
| Standard panel | 7×7px | Function category icons, navigation markers |
| Large panel/header | 9×9px | Section type identifier, top-level state summary |

No icon exceeds 9×9px. If a concept can't read at 9×9px as an outline, simplify or use a size-S text label instead.

**Explicitly prohibited icon types**: checkmarks (completion is the solid-green hold, not a check), × marks for errors (reserved for user-initiated cancellation; errors use `+`), progress bars/spinners (the ▬ glyph handles this), shield/star/badge icons (no gamification hierarchy), notification bells or dot-badges (mobile OS patterns, not bunker patterns).

---

### 7.4 HUD Animation Philosophy

**Rule**: Animation in the HUD communicates change of state or ongoing process — never cosmetic. If an element would animate when nothing in the system has changed, remove that animation.

| HUD element | Animates? | Rationale |
|-------------|-----------|-----------|
| ▬ rect-pulse glyph | Yes — 0.5Hz extend/contract | IS the animation; accessibility channel (never remove) |
| ● dot glyph | Yes — slow 0.5Hz luminance pulse | "Alive by Default" — proves connection is live |
| + cross-plus glyph | No — static hold | Alert needs no motion; room-layer irregular pulse carries urgency |
| Agent ID text | No | Identity is fixed |
| State color changes | No easing — instant swap | Gradual color fade implies a transitional state that doesn't exist |
| Panel borders/backgrounds | No | Structural fixtures |
| Task count numbers | Instant swap on change | Data, not state — discrete updates |
| Panel origin amber dot | Yes — same 2–3 second pulse as ● | Ties HUD to world-layer "power on" rhythm |

**Timing register:**
- **Ambient/alive**: 0.5Hz (2-second cycle) — matches the world layer. HUD breathes with the bunker.
- **State-change**: 1 frame (instant). State transitions do not ease.
- **Exception — alert resolution only**: `+` → `●` uses a 2-frame transition (cross → blank → dot). The single blank frame makes "alert resolved" a legible beat. 2 frames only. Not a cross-fade.

**State transition table:**

| Transition | Duration | Behavior |
|-----------|----------|---------|
| Idle → Active (● → ▬) | 1 frame | Dot disappears; rect appears at minimum width; begins extending immediately |
| Active → Idle (▬ → ●) | 1 frame | Rect disappears; dot appears at full brightness |
| Active → Alert (▬ → +) | 1 frame | Rect disappears; cross appears static |
| Alert → Idle (+ → ●) | 2 frames | Cross → blank (1f) → dot (1f) |
| Alert → Active (+ → ▬) | 1 frame | Cross disappears; rect appears immediately |
| Any → Agent Disconnect | 1 frame | Glyph disappears; row dims to 40% luminance; no replacement glyph |

**Hard prohibitions — never animate:**
- Panel entrance/exit (panels don't slide, fade, or scale in)
- Text character animation (no typewriter effect)
- Background fill animation (no color washes)
- Icon rotation or scale
- Eased color transitions on any element

If the engine's UI framework adds any of these by default, disable them explicitly.

---

### 7.5 UX Resolutions (from accessibility check)

**Startup animation**: Full 8–12 second sequential boot plays on the first open of the day. Subsequent opens that same day resume directly to current state — no boot sequence. "First open of the day" is defined by session state, not clock time; if the tool has been closed for more than 4 hours, the next open is treated as "first."

**Error detail access**: Alert rows are tappable/clickable. Tapping an alert row expands it inline to show a short detail text (max 2 lines at size-S bitmap font). Tap again to collapse. Touch-safe — minimum tap target: 44×44px at display resolution (Godot's minimum interactive size recommendation).

**Contrast ratio (VERIFIED 2026-05-12)**: S2 Active Green over W2 Institutional Grey-Warm (`#4A4035`) was originally `#4A9A52` and computed at **2.90 : 1** — FAILED WCAG 2.1 AA's 3:1 threshold for UI/graphics. S2 has been raised to **`#5BAD63`** which computes at **3.65 : 1** ✅ PASSES. Full verdict, methodology, and remaining contrast pairs to verify are in `design/ux/accessibility-requirements.md` §1.1. Do not regress S2 to the original value.

---

## Section 8: Asset Standards

The governing principle across all asset decisions: formats, organization, and constraints must serve the pixel art constraint (exact palette adherence, no interpolation) and the two target platforms (Godot 4.6.2 + HTML5). Anything that introduces color blending, compression artifacts, or per-pixel ambiguity is rejected.

---

### 8.1 File Format Preferences

#### Sprites and Tilesets

**Delivery format**: PNG-8 (indexed color, exact palette) for all sprites and tilesets.

Not PNG-32. Not PNG-24. PNG-8 with a locked 8-color index matching the palette defined in Section 4 enforces palette adherence at the file level — it is physically impossible to introduce an off-palette color into a PNG-8 using these colors. PNG-32 allows any color to slip in during export, compositing, or re-save. Accidental anti-aliasing, layer-edge blending, and tool defaults silently corrupt palette adherence in PNG-32. PNG-8 makes those errors visible immediately.

**Exception**: HUD panels that mix world-layer and HUD-layer palette registers in one sheet may use PNG-24. Document this exception in the source file and reflect it in the filename (see 8.2). Prefer splitting sheets over invoking this exception.

**Source files**: `.aseprite` (Aseprite native) as the source of truth. Source files are version-controlled — not gitignored. The source file is the asset; the PNG export is the build artifact.

Path: `assets/source/[category]/[asset-name].aseprite`

#### Fonts

**Format**: `.fnt` + accompanying PNG sprite sheet (BMFont / AngelCode format), imported as a `FontFile` resource in Godot.

Not TrueType, not OTF scaled down. The 5×7px and 5×9px bitmap sizes specified in Section 7.2 cannot be generated correctly from a vector font at runtime — subpixel rounding corrupts character metrics at those sizes. The bitmap font sheet is authored at exact pixel dimensions. What you see in the source is exactly what renders. No engine-side scaling of font assets is permitted.

The L tier (10×14px) is a pixel-doubled 2× version of the S tier (5×7px), authored explicitly — not runtime-scaled.

#### Audio

**Ambient loops and long tracks**: `.ogg` Vorbis — streamed from disk, appropriate for files over 10 seconds.

**Short SFX and UI sounds (≤2 seconds)**: `.wav` (uncompressed PCM). HTML5 export has historically had `.ogg` decode latency on sub-2-second files that breaks the "satisfying feedback" pillar. `.wav` eliminates this overhead for UI beats and completion sounds.

**Bit depth**: 16-bit. **Sample rate**: 44.1kHz. Do not deliver 48kHz — it requires resampling in the Godot import pipeline and can introduce drift in looping audio on web targets.

#### Godot Import Settings (Sprites)

These settings must be applied to every sprite and tileset texture imported into Godot — set via a project-wide import preset applied to the `assets/sprites/` and `assets/tilesets/` directories:

| Setting | Value |
|---|---|
| **Filter** | Nearest |
| **Mipmaps** | Disabled |
| **Repeat** | Disabled (enable only for explicitly tileable assets) |
| **Compress / Mode** | Lossless |
| **Fix Alpha Border** | Disabled |
| **Premultiplied Alpha** | Disabled |
| **Normal Map** | Disabled |

**Project-level pixel-perfect settings** (required in Project Settings):

| Setting | Value |
|---|---|
| Rendering > Textures > Canvas Textures > Default Texture Filter | Nearest |
| Display > Window > Stretch > Mode | `canvas_items` |
| Display > Window > Stretch > Aspect | `keep_integer` |
| Rendering > 2D > Snap > Snap 2D Transforms to Pixel | Enabled |
| Rendering > 2D > Snap > Snap 2D Vertices to Pixel | Enabled |

> **VERIFY**: `keep_integer` and the 2D snap setting paths — confirm names and locations are unchanged in Godot 4.6.2. These are based on Godot 4.3 knowledge.

**Rendering backend**: This project must use the **Compatibility** renderer (OpenGL 3.3 / WebGL 2). The HTML5 target requires WebGL 2, which is only available through the Compatibility renderer. Godot 4.6 defaults to D3D12 on Windows — pin Compatibility explicitly in Project Settings for all export presets.

---

### 8.2 Naming Convention

**Master pattern**: `[category]_[name]_[variant]_[size].[ext]`

All four segments are required. If a segment is not meaningful for a given asset, use the canonical filler value listed in the tables below.

#### Category Prefixes

| Prefix | Applies to |
|---|---|
| `env` | Environment tiles, room furniture, props, infrastructure |
| `char` | Character sprites (Commander + all agents) |
| `ui` | HUD panels, icons, state glyphs, font sheets |
| `vfx` | Pixel-art effects (bloom dots, conduit indicator, completion pulse) |
| `audio` | All audio files |
| `src` | Source files only — lives under `assets/source/`, never imported directly |

#### Name Segment

Descriptive, snake_case, specific enough to be unambiguous without the category prefix. Agent characters use their slug, not a number: `char_researcher_sheet_16.png`, not `char_a2_sheet_16.png`. Numbers rot when agents are removed and added.

#### Variant Segment

| Value | Meaning |
|---|---|
| `sheet` | Multi-state sprite sheet (character sprites — all states in one file) |
| `idle` | Single-pose still (used for non-animated single-frame assets) |
| `active` | Active room state (environment tiles) |
| `unused` | Unused room state (environment tiles) |
| `hover` | UI interactive hover state |
| `pressed` | UI interactive pressed state |
| `disabled` | UI element unavailable state |
| `loop` | Audio: looping ambient track |
| `oneshot` | Audio: single non-looping trigger |

Animation frames are distinguished within the Aseprite source by frame tags — they do not create separate PNG files. One sheet contains all animation states for a character as rows.

#### Size Segment

| Value | Applies to |
|---|---|
| `16` | Character sprites at 16px height |
| `32` | Character sprites at 32px height |
| `8tile` | Tilesets using 8×8px tile module |
| `16tile` | Tilesets using 16×16px tile unit |
| `sm` | UI icons 5×5px to 7×7px |
| `md` | UI icons 9×9px |
| `panel` | HUD panel backgrounds (variable width) |
| `fnt` | Font sheets |
| `std` | Standard — use when size is not meaningfully variable |

#### Examples

```
char_commander_sheet_16.png
char_researcher_sheet_16.png
env_workstation_active_16tile.png
env_floor_active_8tile.png
ui_glyph_active_sm.png
ui_glyph_alert_sm.png
ui_panel_status_panel.png
ui_font_mono_fnt.png
vfx_completion_pulse_loop_sm.png
audio_ambient_running_loop.ogg
audio_completion_beat_oneshot.wav
```

---

### 8.3 Folder Structure

```
assets/
  source/              # .aseprite source files — version controlled, never imported
    characters/
    environment/
    ui/
    vfx/
  sprites/
    characters/        # char_*.png
    environment/       # env_*.png
    vfx/               # vfx_*.png
  tilesets/            # env_*_tile.png — separate from single sprites
  ui/                  # ui_*.png
  audio/
    ambient/           # audio_ambient_*.ogg
    sfx/               # audio_*_oneshot.wav
  fonts/               # ui_font_*.fnt + accompanying ui_font_*.png
```

`assets/source/` is where artists work. All other subdirectories are build outputs — generated by Aseprite export, not hand-placed. Deliver the `.aseprite` source file; run export locally and commit the PNG alongside it.

---

### 8.4 Texture Resolution Tiers

All resolutions are source pixels. Godot renders at integer scale — display size is always an integer multiple of source dimensions.

#### Character Sprites

| Asset | Source resolution | Notes |
|---|---|---|
| Standard character body | 16×16px to 24×24px | Width may be narrower; height is the fixed anchor |
| Commander body | 24×24px to 32×32px | Larger mass per Section 5.1; must not exceed 32px height |
| Combined character sheet | All states packed in rows | See 8.5 for layout; max 256px wide |

Use the smallest size that passes the silhouette test from Section 5.2. The 16px minimum is a hard floor — not a target. If a character reads clearly at 16px, there is no reason to push to 24px.

#### Environment Tilesets

| Asset | Source resolution | Notes |
|---|---|---|
| Floor / wall tile module | 8×8px | Artistic base unit — 2×2 modules = one 16×16px Godot tile cell |
| Tileset sheet | 128×128px max | All variants of one surface type on one sheet |
| Hero workstation footprint | 24×24px or 32×32px | 3×3 tile footprint at 8px/tile = 24×24px |

**Tile grid**: 8×8px is the artistic base module. All room geometry snaps to this grid. Godot's TileSet is configured with `tile_size = Vector2i(16, 16)` — each Godot tile cell contains a 16×16px graphic composed of four 8×8 modules.

#### HUD Elements

| Asset | Source resolution | Notes |
|---|---|---|
| State glyphs (●/▬/+) | 5×5px (● and +), 6×4px (▬) | From Section 3.3. No rounding, no antialiasing. |
| Standard icons | 7×7px | Maximum for inline panel icons |
| Large section icons | 9×9px | Maximum for any icon — no exceptions |
| HUD panel backgrounds | Variable width, 1px borders | Authored as 9-slice-compatible sources |
| Font sheet S tier | 5×7px per glyph, 96 characters | Sheet: ~72×56px |
| Font sheet M tier | 5×9px per glyph | Sheet: ~72×72px |
| Font sheet L tier | 10×14px per glyph | Pixel-doubled from S tier |

#### VFX

| Asset | Source resolution | Notes |
|---|---|---|
| Conduit bloom dot | 5×5px or 7×7px | 2 frames: full / half intensity |
| Completion pulse | 16×16px or 24×24px | 6–8 frame radial dithered ring |
| Status indicator blink | 3×3px | 2 frames: on / off |

---

### 8.5 Sprite Sheet Organization

**One sheet per character, all animation states packed by row.** This is the Godot-idiomatic approach — `AnimatedSprite2D` uses a `SpriteFrames` resource that references frame regions from a single texture per character, keeping texture binds minimal and the `SpriteFrames` resource maintainable.

#### Character Sheet Layout

- **Rows**: one row per animation state, fixed order: Row 0 — `idle`, Row 1 — `working`, Row 2 — `alert`. This order is consistent across all characters.
- **Columns**: frames in animation order, left to right. Row 0 (idle) = 1 frame. Row 1 (working) = 4–6 frames. Row 2 (alert) = 1 frame.
- **Frame count maximum**: 6 frames per state. If a working animation needs more than 6 frames, the animation design is over-complex for this scale.
- **Sheet width**: character width × max frame count across any row. A 16px character with 6-frame working cycle = 96px wide. A 32px Commander with 6-frame cycle = 192px wide.
- **Sheet height**: character height × 3 (one row per state).
- **Frame padding**: zero. No spacing between frames or between rows. Godot slices by `frame_width = sheet_width / frame_count`. Any padding breaks the calculation.
- **Hotspot**: character pivot at bottom-center for top-down tile placement. Document the pixel offset in the Aseprite source as a named slice or metadata comment.

#### Tileset Sheet Layout

- **Rows**: one row per variant type (active, idle, unused).
- **Columns**: one column per tile sub-type (floor, wall, corner, shadow-strip, conduit, etc.).
- **Cell size**: 8×8px per tile module.
- **Sheet size limit**: 128×128px maximum per sheet. If a category grows beyond this, split by functional group (floor tiles, wall tiles, prop tiles) before increasing sheet size.

#### HUD Glyph Sheet Layout

All three state glyphs (●/▬/+) on one sheet. The ▬ glyph has 2 animation frames — stored as a second row. Sheet dimensions: `max_glyph_width × 3` wide, 2 rows tall.

---

### 8.6 Tileset Constraints

**Use `TileMapLayer`, not `TileMap`.** As of Godot 4.3, `TileMap` is deprecated. This project must use `TileMapLayer` — one node per layer; stacked layers per room for floor, walls, and props.

> **VERIFY**: `TileMapLayer` Y-sort behavior in Godot 4.6.2 — the `y_sort_enabled` property on the base `Node2D` should control Y-sort per layer. Cross-reference with 4.6.2 docs before implementing character/prop depth sorting.

**Tile size**: `tile_size = Vector2i(16, 16)` in all TileSets. Consistent with the 8×8 module grid (two 8px modules = one 16px Godot tile).

**Tile bleeding**: bleeding (color from adjacent tiles appearing at seam edges) is mitigated in order of preference: (1) enable Snap 2D Transforms to Pixel in project settings (primary fix); (2) add 2px separation between tiles in the sheet if bleeding persists on web; (3) use integer-only camera positions.

**Layer limits**: three layers per visible room maximum — Floor, Walls, Props. Three draw calls for tile rendering, well within the ≤1000 budget.

---

### 8.7 Animation Constraints

**`AnimatedSprite2D`**: use for character sprite frame cycling. Purpose-built for sprite sheet animation; references the `SpriteFrames` resource.

**`AnimationPlayer`**: use for timed property-based animations — HUD ▬ glyph pulsing at 0.5Hz, conduit amber bloom, CRT phosphor warmup sequence. Drives property tracks (scale, modulate, visibility), not sprite frames.

Do not use `AnimationPlayer` to drive sprite frame sequences. Do not use `AnimatedSprite2D` for property animation. Use `Tween` for one-shot property transitions.

#### Playback Frame Rates

| State | Frame Count | Playback FPS |
|---|---|---|
| Working (cycle) | 4–6 | 8–10 FPS |
| Idle | 0–1 | N/A (single frame) |
| Alert (snap and hold) | 1 | N/A (single frame) |
| State transitions | 1–8 | 12 FPS |

Sprite animations play at 8–12 FPS within a 60 FPS rendering loop. The lower sample rate is intentional — it produces the chunky motion feel characteristic of pixel art.

> **VERIFY**: `AnimationMixer` is the base class for `AnimationPlayer` in Godot 4.3+, with `active` replacing deprecated `playback_active`. Confirm these APIs are unchanged in 4.6.2.

---

### 8.8 Font Import Pipeline

**Recommended approach**: generate a BMFont `.fnt` + PNG sheet pair using a bitmap font tool (BMFont, Littera, or Fony). Import the `.fnt` into Godot — it imports as a `FontFile` resource with the bitmap sheet embedded.

**Godot import settings for font `FontFile`**:

| Setting | Value |
|---|---|
| Antialiased | Disabled |
| Generate Mipmaps | Disabled |
| Oversampling | 1 |
| Subpixel Positioning | Disabled |

Apply to `Label` nodes via `Theme` overrides, setting font size to exactly 7px (the S-tier character cell height). Render at native pixel size — do not scale.

> **VERIFY**: `BitmapFont` class status in Godot 4.6.2. In Godot 4.0–4.3 it was retained as a separate resource type. It may have been deprecated or absorbed into `FontFile` between 4.4 and 4.6. Confirm before building the font pipeline.

> **VERIFY**: BMFont `.fnt` import via `FontFile` in Godot 4.6.2. This worked in Godot 4.3. Confirm the import pipeline and `FontFile` settings path are unchanged in the 4.6 editor.

**Three-tier font sizes**: S (5×7px), M (5×9px), L (10×14px). M and L require separate `FontFile` resources — M is not a clean integer scale of S. For the L tier (10×14px = 2× pixel-double of S): if the font engine renders at 2× via `font_size` without interpolation, a single S-tier `FontFile` is acceptable. Verify no blurring appears before committing to this path.

---

### 8.9 Audio Asset Constraints

| Use Case | Format | Settings |
|---|---|---|
| Ambient loops / music | OGG Vorbis | 44.1kHz, 16-bit stereo, streamed |
| SFX / UI sounds (≤2 seconds) | WAV (PCM) | 44.1kHz, 16-bit mono |

Do not use MP3 — higher decoding overhead and less efficient for looping than OGG.

**Godot import settings**:

| Setting | Music / Ambient | SFX |
|---|---|---|
| Loop | Enabled | Disabled |
| Loop Mode | Forward | N/A |
| Compression | Compressed (OGG stream) | Lossless (PCM) |

> **VERIFY**: Godot 4.4–4.6 audio import settings — no breaking changes to the audio import pipeline were identified in 4.4–4.6. OGG and WAV import behavior should match 4.3 patterns.

**Audio RAM budget**: ≤16 MB for all SFX (uncompressed PCM). Ambient loops are streamed; not counted against this limit.

---

### 8.10 Export Settings Philosophy

**Preserve in `.aseprite` source**:
- **Layer names**: every layer must be named semantically (`body`, `prop_left`, `head`, `shadow`, `highlight`). Not "Layer 1." Names are the documentation.
- **Animation tags**: Aseprite frame tags must exactly match the state row order (`idle`, `working`, `alert`). Tag names are read by the export pipeline — a tag named "anim1" breaks it.
- **Color palette**: the source file's indexed palette must be locked to the 8-color project palette before any drawing begins. If a color value is revised in the art bible, update all source files before re-exporting — do not patch the PNG directly.

**Flatten on export**:
- **All visible layers merged** into a flat composite PNG.
- **No background**: export with transparent canvas. Godot composites sprites onto the world layer; a colored background overwrites the environment tile beneath the sprite.
- **Exception — tileset sheets**: export with no transparency. All tile pixels are fully opaque. Section 4.1 rule: no transparency on tiles.

**Save discipline**: disable "Trim Cel" in Aseprite before first save on any source file. Auto-trimming cels shifts hotspot alignment and silently corrupts the pivot offset.

---

### 8.11 Web Export Constraints

**Renderer**: Compatibility (OpenGL 3.3 / WebGL 2) is required for HTML5 export. Pin Compatibility in all export presets. Godot 4.6 defaults to D3D12 on Windows for the editor — pin Compatibility for the desktop PC export preset as well for consistency.

**Texture compression for web**: set to lossless (PNG / WebP lossless) in the web export preset's Resources tab. Do not use lossy compression (WebP lossy, ETC2, BPTC) — lossy compression corrupts the strict 8-color palette.

> **VERIFY**: Exact location of the texture compression format option in Godot 4.6.2 HTML5 export presets. In Godot 4.3, it lived under the export preset's Resources tab. Confirm this is unchanged in 4.6.

**Export bundle target**: ≤50 MB total (PCK + WASM + HTML). The Godot WASM runtime is ~30–40 MB; game assets should target <10 MB. Exclude `prototypes/` and `tests/` directories via export preset include/exclude filters.

**Browser audio autoplay**: browsers require a user gesture (click or keypress) before audio can play. Start ambient audio on the first input event, not in `_ready()`. This is a browser platform constraint, not a Godot bug.

**Progressive loading**: not required for MVP. If the multi-room build grows above 30 MB of game assets, revisit with `ResourceLoader.load_threaded_request()` per room.

---

### 8.12 LOD Philosophy

**Single resolution. Integer scaling only. No LOD variants.**

LOD systems exist to degrade quality gracefully as assets move to distance or as performance budgets tighten. In a top-down 2D tool with a fixed room layout and no camera perspective, neither condition applies. Every tile and every character sprite is at the same effective distance from the virtual camera at all times. The draw call and texture budgets are set once for the target platforms.

Introducing LOD variants would mean maintaining multiple copies of every asset that diverge over time — a known cause of visual inconsistency on solo-developer projects, with no runtime benefit to offset the cost.

**Integer scaling is the quality mechanism.** Zoom is handled by Godot's integer scale multiplier on the viewport. The Nearest texture filter means zero interpolation artifacts at any integer zoom level. A 16px character at 3× zoom is a 48px rendering of the same pixel data. There are no quality decisions to make at runtime.

**Design rule**: every asset must read correctly at 1× (overview zoom) because that is the primary read. Details that only appear at 2× or 3× zoom are invisible to the primary view — per Section 5.4, that investment may not be warranted.

**When quality degrades**: sub-1× zoom means the layout has grown beyond the screen without the room geometry being rethought. The correct response is a layout review, not an LOD asset variant. No asset variant exists below 1× source resolution.

---

### 8.13 Performance Budget Summary

| Category | Budget |
|---|---|
| Total draw calls per frame | ≤1000 (project-wide ceiling) |
| Draw calls from tiles (per visible room) | ≤3 (one per TileMapLayer) |
| Draw calls from character sprites | ≤15 |
| Draw calls from HUD panels | ≤20 |
| Total VRAM for all game textures | ≤32 MB |
| Character sprite sheet (per character, worst case) | ≤0.4 MB |
| Total audio RAM (SFX, uncompressed) | ≤16 MB |
| Web export bundle (PCK + WASM + HTML) | ≤50 MB total |
| Tileset sheet max (art standard) | 128×128 px per sheet |
| Character / tile atlas max (engine limit) | 512×512 px |

*All Godot 4.4–4.6 specifics flagged with **VERIFY** must be confirmed against `docs/engine-reference/godot/` and the official 4.6.2 docs before treating as final.*

---

## Section 9: Reference Direction

### 9.1 How to Read This Section

Each reference below is a lens, not a template. The question is never "does this look like X?" — it is "did we apply the same underlying principle X uses, in service of our own visual identity statement?" When in doubt, return to the three principles: Functional Patina, Operational Color, Mechanical Confession.

---

### 9.2 Reference Catalogue

#### Reference 1: Prison Architect (Introversion Software, 2015)

**What to draw from — specifically:**

Prison Architect's top-down read of interior space is built on a single discipline: rooms are legible because *the objects inside them define the room's purpose*, not the room's label. A cell block reads as a cell block before you see any text, because beds, toilets, and doors are composed in a pattern that communicates "containment." Apply this compositional rule to the bunker — each station should be self-defining. The comms station reads as comms because cables radiate outward from a central terminal. The monitoring station reads as monitoring because multiple screens face a single operator seat. No room label should be doing work that the prop composition already does.

The second technique: Prison Architect uses a very flat ambient light with no directional shadow on environment tiles, but casts a subtle drop shadow on *objects placed within a room* to lift them off the floor plane. This creates depth hierarchy without simulating a realistic light source. The bunker applies the same separation: floor tiles are flat; furniture and mounted equipment carry a 1–2px south-facing offset shadow at all times, regardless of any in-scene lighting.

**What to avoid:**

Prison Architect's color language is neutral to the point of clinical detachment — it uses color almost exclusively for UI categorization (red rooms, yellow rooms), not for state communication. The bunker's Operational Color system (amber/green/sienna as state carriers) is the direct opposite of this. Do not let environment tile colors drift toward Prison Architect's flat tans and greys with colored room-fill overlays. In the bunker, color belongs to state, not to spatial categorization.

*Pillar connection: Mechanical Confession — rooms confess their purpose through object composition alone.*

---

#### Reference 2: Project Zomboid (The Indie Stone, ongoing)

**What to draw from — specifically:**

Project Zomboid's environment reads as *previously inhabited* — not abandoned dramatically, but vacated mid-task. A kitchen has a pot on the stove. An office has paper on the desk. The objects are mundane, slightly misaligned, and suggest a person who stepped away minutes ago. Apply this to the bunker's Functional Patina: the environment is not pristine military hardware fresh from a factory, and it is not post-apocalyptic wreckage. It is a workspace that people have been using for a long time and will return to. Terminals have coffee-ring marks rendered as a dithered ring of W2 over the desk surface. Cable runs have a single retaining clip slightly off-center.

The specific pixel technique: Project Zomboid uses **micro-clutter** — 1–4px objects that exist to break the regularity of surfaces without adding identifiable meaning. A scuff mark on a floor tile. A small pile of papers rendered as a 3×2px rectangle of W4. A cord that terminates not at the edge of a desk but 2px before it, coiled. Apply this at a density of approximately one detail element per 32×32px tile area, placed asymmetrically.

**What to avoid:**

Project Zomboid's color palette is deliberately desaturated and naturalistic — muted olive greens, washed-out browns, grey-blue shadows — to serve a world that is dying. The bunker is a world that is *running*. The Operational Color system requires state colors (amber, green, sienna) to be the most chromatic elements on screen at all times. Do not let micro-clutter pull the environment toward washed pallor. Environment tiles must stay within W1–W4 and never introduce naturalistic greens or cool blue-greys.

*Pillar connection: Functional Patina — surfaces carry evidence of continuous use, not theatrical distress.*

---

#### Reference 3: Dwarf Fortress Tilesets — CLA / Obsidian

**What to draw from — specifically:**

Not the ASCII original — the reference here is the community tileset tradition, specifically the Obsidian and CLA tilesets, which solved a hard problem: how do you make a 16×16px tile carry enough information to distinguish material, state, and function simultaneously, in a grid where every tile is adjacent to eight others? The answer those tilesets converged on is **surface language**: each material has a characteristic texture mark — a consistent pattern of 2–3px marks that appears on every tile of that material, dense enough to read as "this is different from adjacent material" but sparse enough not to dominate the tile's functional content.

Apply this directly to the three bunker surface materials: worn concrete has a specific mark pattern (a small L-shaped chip near one corner, varying by tile variant); brushed steel has horizontal 1px tick marks at irregular intervals; rubber cable conduit reads smooth by contrast — no surface marks. Once these surface languages are established, any artist can extend the tileset without inventing new vocabulary.

**What to avoid:**

Many Dwarf Fortress tilesets trend toward simulating isometric perspective on a top-down grid — tiles develop implied light angles, volumetric shadows, and highlight gradients that try to sell a 3D read. The bunker is resolutely flat top-down. No tile should carry a highlight edge that implies a light source direction. The 1–2px drop shadow beneath objects (see Reference 1) is the only depth cue permitted. Do not import the isometric shadow language.

*Pillar connection: Mechanical Confession — surface materials are visually distinguishable without labels; material tells you something about the structural logic of the space.*

---

#### Reference 4: Alien (1979) — Production Design by Ron Cobb

**What to draw from — specifically:**

The Nostromo's interior, designed primarily by Ron Cobb, established what is now called "used future" design: technology installed in layers over time, where you can see the accumulation of decisions made at different periods. Pipes run over panels instead of through them because the panels were installed first. Conduits are bolted to surfaces with visible fasteners because they were retrofitted. Labels are handwritten or stenciled onto surfaces because the automated labeling was never installed.

This is Mechanical Confession taken to its fullest expression. In the bunker, every system shows its installation history. Cable management on an early-installed station is clean and clipped. Cable management on a station added later is zip-tied and runs at an odd angle to reach the nearest junction. Power indicators on original-build panels are machined metal; power indicators on retrofitted panels are adhesive labels with handwritten state codes. This variation is not inconsistency — it is the visual record of a system that grew over time.

The specific technique: Cobb used **stenciled text** extensively — unit designations, warning labels, valve numbers — as environmental detail that implies bureaucracy without requiring the viewer to read it. Every prop in the bunker should have at least one unreadable stenciled designation in the W3/W4 range, rendered at 4–5px — legible as "there is text here" but not as specific characters unless the user zooms toward it.

**What to avoid:**

H.R. Giger's organic-mechanical aesthetic — the biomechanical texture language of the alien ship — is the other half of Alien's visual identity and must not enter the bunker. Nothing in the bunker is organic, curved in an unsettling way, or ambiguous about whether it is alive. The bunker is aggressively rectilinear and mechanical. Any surface texture that reads as biological, fleshy, or flowing is a violation of the visual identity statement.

*Pillar connection: Mechanical Confession and Functional Patina — systems visibly show their installation history; every element looks like it has been there for twenty years because some of it has been, and some hasn't, and that difference is legible.*

---

#### Reference 5: Cozy Games — Stardew Valley and Chicory — Structural Principle Only

**What to draw from — specifically:**

The user identified a "cozy aesthetic" as a felt quality of the bunker — warm and inhabitable, not cold and threatening. This reference distills that feeling into a single visual principle: **interior completeness**.

Stardew Valley and Chicory both achieve coziness not through soft colors or rounded shapes, but through the sense that a space is *finished* and *inhabited to its edges*. There are no voids. Every corner of a room has something in it. The space has been filled by someone who lives there and cares about it.

Apply this to the bunker as a compositional rule: no 32×32px area of any active room should be blank floor tile. The space must be filled to its edges with props, cable runs, mounted equipment, or surface detail. An operator's station has a mug, a binder, a secondary monitor at an angle. A junction corridor has a fire extinguisher mount, a breaker box, and a cable run along the baseboard. The bunker feels inhabited because it is complete — not cluttered, not chaotic, but full.

The second extracted principle: both games use **warm ambient light** as a baseline — not because the light source is warm, but because the environment palette itself skews warm. The bunker's W1–W4 palette already does this (Bunker Stone and Institutional Grey-Warm both carry warm undertones). Preserve this. Do not introduce cool greys, blue-blacks, or desaturated neutrals into environment tiles. The floor should feel slightly warmer than the viewer expects for a concrete bunker.

**What to avoid:**

The literal visual language of either game — Stardew Valley's pastoral textures, Chicory's painterly line work and saturated hues — must not appear in the bunker. The cozy principle is extracted from *why* those spaces feel inhabitable, not from what they look like. A bunker that looks like Stardew Valley has failed. A bunker that feels as complete and inhabited as Stardew Valley — while remaining a pixel-art underground operations center — has succeeded. The reference is structural, not aesthetic.

*Pillar connection: Functional Patina — a space that is fully inhabited reads as having been occupied for a long time. Interior completeness is the compositional mechanism that makes Functional Patina legible at room scale.*

---

### 9.3 Reference Synthesis — The Composite Standard

No single reference defines the bunker. The composite is:

| Technique | Source |
|---|---|
| Room legibility through object composition | Prison Architect |
| 1–2px south drop-shadow lifts objects off floor plane | Prison Architect |
| Micro-clutter density (~1 detail per 32×32px, asymmetric) | Project Zomboid |
| Color system stays state-driven, not desaturated | *(inverse of Project Zomboid)* |
| Per-material surface language (characteristic 2–3px marks) | Dwarf Fortress tilesets |
| Flat top-down — no implied light source direction on tiles | *(inverse of DF isometric tilesets)* |
| Visible installation history — layered systems | Alien (Ron Cobb) |
| Stenciled environmental text as implied bureaucracy | Alien (Ron Cobb) |
| No organic or biomechanical curves | *(inverse of Alien / Giger)* |
| Interior completeness — no void floor areas in active rooms | Stardew Valley / Chicory |
| Warm palette baseline in environment neutrals | Stardew Valley / Chicory |

When a new asset is in production, ask not "which reference does this look like?" — ask "which rows of this table does this asset satisfy?" An asset that satisfies zero rows is not yet finished. An asset that contradicts a row is in violation of the art bible.
