# Accessibility Requirements — The Situation Room

> **Status**: Baseline (MVP-scoped)
> **Last Updated**: 2026-05-12
> **WCAG Target Tier**: AA (per pre-production gate criterion)
> **Owner**: UX / Accessibility (no dedicated agent yet — co-owned by creative-director + ux-designer)

---

## Scope statement

This document defines the **MVP accessibility floor**. Post-MVP, expand toward WCAG AAA where feasible. This is a baseline for the gate-check, not the ceiling.

The Situation Room is a developer tool with game aesthetics. The user is presumed to be a software developer monitoring real AI agents. That informs (but does not exempt) accessibility decisions.

---

## 1. Visual

### 1.1 Color contrast (WCAG 2.1 AA) — VERIFIED 2026-05-12

| Pair | Computed ratio | Threshold | Result |
|---|---|---|---|
| S2 `#4A9A52` over W2 `#4A4035` (original palette) | **2.90 : 1** | 3:1 (UI / graphics) | ❌ **FAILS** |
| S2 `#4A9A52` over W2 `#4A4035` | 2.90 : 1 | 4.5:1 (normal text) | ❌ FAILS |
| **S2 `#5BAD63` over W2 `#4A4035` (LOCKED corrected)** | **3.65 : 1** | 3:1 | ✅ **PASSES** |
| S2 `#5BAD63` over W2 `#4A4035` | 3.65 : 1 | 4.5:1 (normal text) | ❌ FAILS — only S2 over background is graphic, never text |

**Decision (2026-05-12)**: Shift S2 Active Green from `#4A9A52` → **`#5BAD63`** (Option A from the gate-check verdict).

Rationale:
- Lower rework footprint than darkening W2 (W2 is the dominant wall colour everywhere; S2 only appears as agent state tints + HUD slot tints)
- Preserves the "warm-amber + cool-green" palette intent
- Lands a comfortable 3.65:1 margin above the 3:1 floor
- Computed relative luminances: L(S2 new) = 0.3293, L(W2) = 0.0538

**Required follow-ups**:
- Update `art-bible.md` colour palette table — replace `#4A9A52` with `#5BAD63`
- Update `design/registry/entities.yaml` if it references the colour literal anywhere
- All TCB / ACC / HUD sprites and tints that use S2 — apply the new hex when art production starts (none have been authored yet, so zero retrofit)

**Other pairs still to verify** (do before sprite production starts, not blocking gate):
- S3 Sienna `#A03520` over W2 — alert state contrast
- HUD bitmap font color (TBD) over status panel background (TBD)
- HUD bitmap font color over slot interior background

Methodology: WCAG 2.1 relative luminance formula. Per-channel: c → c/255 → if <0.04045 then linear=c/12.92 else linear=((c+0.055)/1.055)^2.4. L = 0.2126·R + 0.7152·G + 0.0722·B. Contrast = (L₁+0.05)/(L₂+0.05).

### 1.2 Color independence

**No information may be conveyed by color alone.** Every state must also be encoded redundantly:

| ASM state | Color | Redundant channel |
|---|---|---|
| Idle | Amber `#D4882A` | Idle animation loop (sprite breathing) |
| Working | Amber `#D4882A` | Working animation loop (sprite typing motion) + slot glyph ● |
| Completed | Green `#4A9A52` | One-shot completed animation + `+` slot glyph (1.5s) + audio beat |
| Errored | Sienna `#A03520` | Slow-pulse errored animation + slot glyph ▬ + connection alpha shift |
| Connection STALE | n/a | Slot modulate.a = 0.5 |
| Connection DISCONNECTED | n/a | Slot modulate.a = 0.25 |
| Connection ERROR | Red tint | Slot modulate.a = 0.25 + red modulate.rgb |

### 1.3 Motion sensitivity / reduced motion

**MVP**: A `reduced_motion: bool` setting must exist in `user://settings.json` (per ConfigurationLoader). When true:
- Tween durations clamp to ≤ 0.1s (effectively becoming step-cuts)
- AnimationPlayer ambient loops freeze on first frame
- Connection-quality alpha changes still happen (information-bearing) but without easing
- TCB room flash retains color change but not animation phases

Default: `false` (full motion). Toggle via Settings panel (HUD-accessible).

### 1.4 Text size

**MVP constraint**: One font size (7px per ADR-0012). Cannot scale up without breaking the 480×270 base resolution layout.

**Post-MVP option**: Add a `ui_scale: 1.0 | 2.0` setting that doubles the integer scale factor (so 480×270 renders at ×8 on 1080p — letterboxed but readable). Defer.

---

## 2. Input

### 2.1 Keyboard alternatives for every mouse action

Per technical-preferences: primary input is mouse; gamepad none; touch partial. **Every mouse interaction must have a keyboard alternative**:

| Mouse action | Keyboard equivalent |
|---|---|
| Click slot to open detail | Tab to slot focus + Enter |
| Click backdrop to close overlay | Esc |
| Click computer prop | (TBD — proximity + E to interact?) — flag for Room System story |
| Click settings widget | Tab focus + Space/Enter |

### 2.2 No timing-dependent input

No input must require fast reflex. The only timed element is the 1.5s completed-beat slot glyph; it is observation-only, not interaction.

### 2.3 Remappable input

**MVP**: At least the toggle_hud action (Tab) should be remappable. Other actions: post-MVP.
**Mechanism**: Godot InputMap + a Settings panel input-rebind UI (post-MVP) or hand-edit `user://settings.json` (MVP fallback).

---

## 3. Audio

### 3.1 Audio is never the only information channel

Every audio event must have a visual counterpart:
- Task completion beat audio → room flash + slot `+` glyph
- Alert sound (future) → red modulate + slot ▬ glyph
- UI click sound → visual button press state

### 3.2 Mute controls

Per Audio Manager GDD:
- Global mute toggle (M key)
- Per-bus mute (Music / SFX) via Settings panel

These satisfy WCAG 1.4.2 (audio control).

---

## 4. Cognitive / Onboarding

### 4.1 Discoverability

- The HUD must be visible by default on first launch (so the user knows what's there)
- The `hud_visible` toggle persists per ADR-0011, but first launch always starts with HUD on

### 4.2 No surprise modal blocking

- Detail overlay is non-modal-by-default (TR-hud-010); user can dismiss with click-anywhere-on-backdrop or Esc
- No popup window dialogs (ADR-0011 rejected this)

### 4.3 Error states are recoverable

- Connection DISCONNECTED state never bricks the app; user can fix config and the app auto-heals (per ADR-0001 backoff strategy)
- CONFIG_INVALID state shows what's wrong; does not silently fail

---

## 5. Testing protocol

For MVP, accessibility is verified by:

1. **WCAG contrast checker** run against the locked palette before sprite production (action item §1.1)
2. **Manual smoke**: navigate the bunker using keyboard only — every action reachable
3. **Reduced-motion smoke**: enable `reduced_motion: true` in settings; verify visual feedback still readable
4. **Screen reader smoke**: out of scope for MVP (pixel-art tool; no DOM); document as a Post-MVP concern

Post-MVP: invite at least one accessibility-focused playtester before any public release.

---

## Open items

- **WCAG contrast verification** on S2/W2 (carried from 2026-05-11 gate-check)
- **Keyboard navigation** for slot grid + detail overlay (Tab order, focus indicator) — owned by HUD implementation story
- **Computer prop interaction** keyboard alternative — owned by Room System story
- **Reduced motion** integration with Tween (ADR-0010) + AnimationPlayer (ADR-0009) — needs implementation story
- **Settings UI** for remappable input — Post-MVP

## References

- WCAG 2.1 AA: https://www.w3.org/TR/WCAG21/
- ADR-0011 (HUD Rendering Strategy) — toggle, non-modal contracts
- ADR-0009 (AnimationPlayer) — reduced-motion implications
- ADR-0010 (Tween Lifecycle) — reduced-motion implications
- art-bible.md — locked palette source
- 2026-05-11 gate-check Art Director CONCERNS
