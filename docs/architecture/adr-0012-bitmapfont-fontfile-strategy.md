# ADR-0012: BitmapFont / FontFile Strategy

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Fonts / Text rendering / Theme |
| **Knowledge Risk** | MEDIUM — `BitmapFont` class status is post-cutoff (folded into `FontFile` in Godot 4); `TextServer` constants stable since 4.0 but the canonical workflow for pixel fonts shifted from BMFont .fnt to TTF-via-FontFile in 4.4–4.5. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, Godot 4.6 FontFile + TextServer docs, art-bible.md (5×7 font spec), ADR-0013 (integer scaling) |
| **Post-Cutoff APIs Used** | `FontFile.fixed_size_scale_mode = FIXED_SIZE_SCALE_INTEGER_ONLY` (4.4+); `TextServer.SUBPIXEL_POSITIONING_DISABLED` (stable); FontFile multi-format import (TTF + .fnt both via the same resource type, 4.4+) |
| **Verification Required** | VERIFY-2 (BitmapFont class status — deprecated or first-class in 4.6?) — closed by this ADR; VERIFY-5 (BMFont `.fnt` import via FontFile) — closed by this ADR; new VERIFY-17: confirm `FIXED_SIZE_SCALE_INTEGER_ONLY` produces zero anti-aliasing at integer multiples in 4.6.2; new VERIFY-18: confirm Theme `default_font` propagation to nested Control subtrees |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0013 Stretch Mode + Pixel-Perfect (Proposed) — needs integer scaling so glyphs render at exact multiples. ADR-0003 Autoload Scene Composition (Accepted) — Theme resource loaded at scene scope, not Autoload. |
| **Enables** | ADR-0011 HUD Rendering Strategy (HUD labels need this font); all HUD implementation stories that render text; future system-message overlays. |
| **Blocks** | Any HUD story that touches Label / RichTextLabel until Accepted. |
| **Ordering Note** | Should be Accepted after ADR-0013 (depends on integer scaling) and alongside or after ADR-0011 (HUD topology that uses this font). |

## Context

### Problem Statement

The HUD renders text at 5×7 px per the art bible. Without an explicit font strategy:

1. **Anti-aliasing creep**: Godot's default font import settings produce sub-pixel anti-aliasing, which smudges 5×7 glyphs into illegible blur at small sizes.
2. **`BitmapFont` class confusion**: LLM training data references `BitmapFont` as a first-class type; in Godot 4 it was folded into `FontFile`. Developers cargo-culting from old tutorials will write code that doesn't compile in 4.6.2.
3. **Scale instability**: Without `fixed_size_scale_mode = INTEGER_ONLY`, the font may render at sub-pixel sizes at certain window dimensions, producing inconsistent glyph widths across an integer-scale display.
4. **Font hierarchy sprawl**: If the HUD allows multiple sizes (10px header, 7px body, 5px metadata), the art bible's "one font" intent dilutes; every Label needs explicit font assignment.
5. **VERIFY-2 + VERIFY-5 unanswered**: BMFont `.fnt` workflow status in 4.6.2 is unclear from pre-cutoff knowledge.

TR-hud-008 explicitly requires "BitmapFont 5×7 px rendering via FontFile" — this ADR resolves the apparent contradiction (BitmapFont vs FontFile) and pins the workflow.

### Constraints
- Engine: Godot 4.6.2 / GDScript / Theme + Control + FontFile
- Base resolution: 480×270 (per ADR-0013) — at this scale, 7px text is at its readability floor
- Pixel art aesthetic: zero anti-aliasing, zero subpixel positioning, integer scaling only
- Font asset: 5×7 px glyph cell, Latin alphanumeric + basic punctuation + 3 special glyphs (●, ▬, +)
- Theme-driven: HUD does not assign fonts per-Label; Theme propagates

### Requirements
- One canonical font resource for all HUD text
- Pixel-perfect rendering at all integer scales (×1, ×2, ×3, ×4, …)
- Modern Godot 4.6.2 workflow (no deprecated `BitmapFont` class usage)
- Asset path stable and committed to repo
- Theme applies font globally to HUD subtree

## Decision

### TL;DR
Use **`FontFile`** resource with a **TTF source** rendered at `fixed_size = 7`, `subpixel_positioning = DISABLED`, `antialiasing = NONE`, `hinting = NONE`, `fixed_size_scale_mode = INTEGER_ONLY`. NOT BMFont `.fnt` authoring (deprecated workflow despite still being importable). One font resource, one size, applied via a project-wide Theme.

### FontFile Resource Configuration (pinned)

`res://assets/fonts/pixel_font_5x7.tres`:

```gdscript
[gd_resource type="FontFile" load_steps=2 format=3]

[ext_resource type="FontDataFile" path="res://assets/fonts/pixel_5x7.ttf" id="1"]

[resource]
font_data = ExtResource("1")
fixed_size = 7
fixed_size_scale_mode = 1                    # FIXED_SIZE_SCALE_INTEGER_ONLY
antialiasing = 0                              # TextServer.FONT_ANTIALIASING_NONE
subpixel_positioning = 0                      # TextServer.SUBPIXEL_POSITIONING_DISABLED
hinting = 0                                   # TextServer.HINTING_NONE
generate_mipmaps = false
oversampling = 1.0
```

Each property does specific work:

| Property | Why this value |
|---|---|
| `fixed_size = 7` | The font has exactly one size — 5×7 glyph cell + descender room |
| `fixed_size_scale_mode = INTEGER_ONLY` | At ×2/×3/etc. scales, snaps to integer multiples — no sub-pixel glyph widths |
| `antialiasing = NONE` | Hard pixel edges — no grey smudge halos |
| `subpixel_positioning = DISABLED` | Glyphs snap to pixel grid — no fractional X offsets |
| `hinting = NONE` | TrueType hinting would re-shape glyphs at small sizes; we want the source pixels verbatim |
| `generate_mipmaps = false` | Mipmaps would soften the texture atlas; we want the raw atlas |
| `oversampling = 1.0` | No oversample render-then-downscale (which is anti-aliasing by another name) |

This config produces identical visual output to a hand-authored BMFont `.fnt` *and* preserves the ability to scale to ×2 (14px), ×3 (21px), etc. for future emphasis — though MVP uses only ×1 (7px).

### Why TTF, Not BMFont .fnt

VERIFY-2 closure: `BitmapFont` class was **folded into `FontFile`** in Godot 4. It is not deprecated per se — `FontFile.import` accepts `.fnt` files and behaves identically — but the recommended modern workflow is TTF-via-FontFile with the properties above.

VERIFY-5 closure: BMFont `.fnt` import via FontFile still works in 4.6.2 (the FontFile importer detects format). But we are not using it because:
- TTF authoring tools are easier (FontForge, BitFontMaker2, commission)
- TTF is one file (BMFont is `.fnt` + 1+ texture atlases)
- TTF kerning lives in the font file; BMFont kerning is a manual rebuild
- Identical pixel-perfect output when FontFile properties are set as above

If a future requirement demands BMFont specifically (e.g., a bought asset only ships as `.fnt`), FontFile imports it without changing this ADR.

### Single Canonical Font for MVP

Exactly **one** font resource. Exactly **one** size (7px). No size hierarchy.

For emphasis, use:
- `modulate` color shift (amber for active, sienna for alert, white for default — per art-bible)
- Bold variant later via a second font resource if needed (not in MVP)

Rationale: at 480×270, there is no room for a font-size hierarchy. The 3×4 slot grid + 88×80 status panel + completions strip cannot afford a 10px header anywhere. One size is also the cleanest theme contract.

If post-MVP playtest shows the detail overlay agent-name is unreadable at 7px, that future ADR can add a ×2 size (14px) — `FontFile.fixed_size_scale_mode = INTEGER_ONLY` already supports this without a new resource.

### Theme-Driven Font Assignment

`res://assets/themes/pixel.tres`:

```gdscript
[gd_resource type="Theme" load_steps=2 format=3]

[ext_resource type="FontFile" path="res://assets/fonts/pixel_font_5x7.tres" id="1"]

[resource]
default_font = ExtResource("1")
default_font_size = 7
```

Applied at HUD root:

```gdscript
# hud.gd
@export var pixel_theme: Theme = preload("res://assets/themes/pixel.tres")

func _ready() -> void:
    theme = pixel_theme
    # All Label / RichTextLabel children inherit
```

No per-Label `add_theme_font_override()` calls anywhere. If a Label needs a non-default font, the Theme is the wrong abstraction — escalate via ADR.

### Asset Inventory + Pipeline

| Asset | Path | Source | Committed |
|---|---|---|---|
| TTF source | `res://assets/fonts/pixel_5x7.ttf` | Authored in FontForge / BitFontMaker2 / commissioned | Yes (5–15 KB) |
| FontFile resource | `res://assets/fonts/pixel_font_5x7.tres` | Imported from TTF with locked properties | Yes |
| Theme resource | `res://assets/themes/pixel.tres` | References FontFile | Yes |

Glyph coverage required for MVP:
- Latin uppercase: `A-Z`
- Latin lowercase: `a-z`
- Digits: `0-9`
- Basic punctuation: `. , : ; / - _ ( ) [ ] ! ? ' "`
- Three special glyphs: `●` (U+25CF), `▬` (U+25AC), `+` (U+002B)
- Whitespace: space, tab (rendered as 4×space)

Coverage check is a pipeline gate (asset story responsibility, not architecture). Missing glyphs at runtime render as the FontFile's tofu fallback — visually obvious in QA.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Asset Pipeline                                              │
│                                                              │
│  pixel_5x7.ttf  ──import──►  pixel_font_5x7.tres            │
│    (source)                    (FontFile, locked properties) │
│                                       │                      │
│                                       ▼                      │
│                                 pixel.tres                   │
│                                  (Theme, default_font set)   │
│                                       │                      │
│                                       ▼                      │
│                                 HUD root.theme               │
│                                       │                      │
│                                       ▼                      │
│                       All Labels inherit pixel_font_5x7      │
│                       at fixed_size = 7, INTEGER_ONLY scale  │
└─────────────────────────────────────────────────────────────┘
```

### Key Interfaces

This ADR does not introduce new public APIs. It pins resource paths and FontFile property values.

Registry updates when Accepted:
- `font_via_fontfile_resource` api_decision: all fonts loaded as FontFile, not direct TTF
- `font_subpixel_disabled` api_decision: subpixel_positioning + antialiasing + hinting all disabled
- `font_integer_only_scale` api_decision: `fixed_size_scale_mode = INTEGER_ONLY`
- `bitmap_font_class_usage` forbidden_pattern: never reference `BitmapFont` class (it's `FontFile`)
- `per_label_font_override` forbidden_pattern: fonts assigned via Theme, never via `add_theme_font_override`
- `multiple_hud_font_sizes_mvp` forbidden_pattern: one font size for MVP

## Alternatives Considered

### Alternative A — BMFont `.fnt` workflow

- **Description**: Author the font in BMFont, export `.fnt` + texture atlas, import as FontFile.
- **Pros**: Maximum pixel fidelity (atlas is literal pixels); a known retro-pixel workflow.
- **Cons**: Two-file artifact; manual kerning maintenance; deprecated authoring path in 4.5+; identical visual output to TTF-via-FontFile when properties locked.
- **Rejection Reason**: TTF workflow is simpler and produces identical pixels. BMFont retained as a future option if a purchased asset only ships as `.fnt`.

### Alternative B — `Label3D` for HUD text

- **Description**: Use Godot's 3D Label node for HUD.
- **Pros**: SDF rendering; scales smoothly.
- **Cons**: 3D node in a 2D project; SDF defeats pixel-art aesthetic; CanvasLayer hierarchy doesn't compose with 3D nodes.
- **Rejection Reason**: Wrong tool entirely.

### Alternative C — `RichTextLabel` with BBCode

- **Description**: Use RichTextLabel everywhere instead of Label.
- **Pros**: Supports inline color/bold/italic via BBCode.
- **Cons**: Adds parsing cost for static text; BBCode is overkill for the HUD's static labels; harder to test (output depends on parse).
- **Rejection Reason**: Use plain Label; if a future need demands inline formatting, scope it to that one widget.

### Alternative D — Multiple font sizes for hierarchy

- **Description**: Three sizes: 5px metadata, 7px body, 14px headers.
- **Pros**: Visual hierarchy.
- **Cons**: 5px is illegible at integer scales below ×3; 14px occupies vertical room the HUD doesn't have; aesthetic violation per art-bible's "one font" intent.
- **Rejection Reason**: No room for hierarchy at 480×270. Reconsider post-MVP for detail overlay only.

### Alternative E — Custom shader-rendered text

- **Description**: SDF atlas + custom shader for crisp text at any scale.
- **Pros**: Theoretically pixel-perfect at non-integer scales too.
- **Cons**: Massive over-engineering; FontFile + INTEGER_ONLY already covers our case.
- **Rejection Reason**: Yagni.

### Alternative F — Godot's built-in default font

- **Description**: Skip font customisation; use the engine default.
- **Pros**: Zero asset work.
- **Cons**: Default is a sans-serif outline at the wrong size; aesthetic catastrophe.
- **Rejection Reason**: Aesthetic violation.

### Alternative G — Continue calling it `BitmapFont` for clarity

- **Description**: GDD says "BitmapFont"; rename or keep terminology.
- **Pros**: GDD doesn't need an edit.
- **Cons**: `BitmapFont` is not a class in Godot 4; using the name invites cargo-cult code that won't compile.
- **Rejection Reason**: Resolve the terminology contradiction here: the resource type is `FontFile`; the *workflow* style is "bitmap font" (raster glyphs, integer scaling). Document explicitly.

## Consequences

### Positive
- Closes VERIFY-2 (BitmapFont class — it's FontFile in Godot 4)
- Closes VERIFY-5 (BMFont `.fnt` import — supported but not used)
- Pixel-perfect at every integer scale
- One font resource, one Theme assignment — clean dependency
- Asset pipeline is standard TTF workflow (procurable, scriptable)
- Theme propagation eliminates per-Label font assignment surface

### Negative
- Need to procure/author a TTF source for the 5×7 font (one-time)
- TTF + FontFile + Theme is three layers — onboarding hazard for "where does the font come from?"
- Single-size constraint may bite if detail overlay text is unreadable in playtest

### Risks

| Risk | Mitigation |
|---|---|
| `antialiasing` flag accidentally flips on during a Theme refactor | `font_subpixel_disabled` forbidden_pattern in registry; GUT test asserts FontFile property values |
| Theme not applied at HUD root; Labels fall back to engine default | GUT test asserts `HudRoot.theme != null` and font resource matches; visual smoke catches the default-font glyphs immediately |
| FontFile properties drift on re-import | Property values pinned in this ADR; re-import diff caught in code review; `pixel_font_5x7.tres` committed to repo |
| Missing glyph in TTF source renders tofu in production | Asset pipeline glyph-coverage gate; QA smoke catches |
| `FIXED_SIZE_SCALE_INTEGER_ONLY` doesn't behave at ×8 (3840×2160) (VERIFY-17) | Manual smoke at 4K resolution; godot-specialist consultation if anomaly found |
| Theme `default_font` doesn't propagate to deep Control descendants (VERIFY-18) | GUT test instantiates HUD, descends three levels, asserts effective font matches pixel_font_5x7 |
| Developer adds `add_theme_font_override` on a Label | `per_label_font_override` forbidden_pattern; lint check; code review |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `commanders-room-hud.md` | TR-hud-008 (BitmapFont 5×7 px rendering via FontFile) | Resolved: the resource is FontFile; the source is TTF; properties pinned for pixel-perfect output |
| `art-bible.md` | Single 5×7 px pixel font with three special glyphs (●, ▬, +) | TTF includes specified glyph coverage; FontFile preserves pixel integrity |
| Cross-cutting | All HUD text uses the same font | Theme-driven; per-Label override forbidden |

## Performance Implications
- **CPU**: Text rendering cost is dominated by TextServer layout — sub-µs per label per frame
- **Memory**: TTF source ~10KB; FontFile atlas at fixed_size=7 ~~~20KB; Theme negligible
- **Load Time**: TTF parse + atlas generation at first use (~5ms); cached for session
- **Network**: N/A
- **Draw Calls**: Each Label = 1 draw call; ~20 HUD labels total = ~20 calls (within 1000 budget)

## Migration Plan
No existing code to migrate (pre-production). Asset procurement is a precondition:

1. **Procure TTF source** (commission, FontForge author, or BitFontMaker2 export) covering the glyph inventory above
2. Commit `pixel_5x7.ttf` to `res://assets/fonts/`
3. Create `pixel_font_5x7.tres` FontFile resource with the locked property values
4. Create `pixel.tres` Theme resource referencing the FontFile
5. Apply theme at HUD root via `@export var pixel_theme`
6. Validate via GUT tests + visual smoke at ×1/×2/×4 scales

Until the TTF asset exists, HUD implementation stories that render text are blocked. Mock FontFile (using a placeholder TTF) is acceptable for early implementation work; mark the story Blocked-on-asset and unblock when TTF lands.

## Validation Criteria
- GUT test: `test_fontfile_properties_locked` — load `pixel_font_5x7.tres`; assert `antialiasing == 0`, `subpixel_positioning == 0`, `hinting == 0`, `fixed_size == 7`, `fixed_size_scale_mode == 1`, `oversampling == 1.0`
- GUT test: `test_theme_default_font_set` — load `pixel.tres`; assert `default_font` resource path == FontFile path; assert `default_font_size == 7`
- GUT test: `test_hud_root_theme_applied` — instantiate HUD; assert `HudRoot.theme.default_font` resolves to the pixel font
- GUT test: `test_label_inherits_pixel_font` — find a Label deep in HUD subtree; call `get_theme_font(&"font")`; assert it matches the pixel font
- Visual smoke at ×1 (480×270 in editor), ×2 (960×540), ×4 (1920×1080), ×8 (3840×2160): glyphs are pixel-perfect, no smudge, no inconsistent widths
- Manual review: every HUD glyph appears in the asset; no tofu

## Related Decisions
- ADR-0013 Stretch Mode + Pixel-Perfect — provides the integer scaling substrate this font depends on
- ADR-0011 HUD Rendering Strategy — applies the Theme to HudRoot
- ADR-0003 Autoload Scene Composition — Theme is scene-scoped, not Autoload
- VERIFY-2, VERIFY-5 — closed by this ADR
- New VERIFY-17, VERIFY-18 — opened by this ADR
- TR-hud-008 — covered by this ADR
