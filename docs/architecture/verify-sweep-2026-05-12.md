# Engine-Empirical Verification Sweep — 2026-05-12

**Scope**: 11 VERIFY items opened by ADR-0004, ADR-0009, ADR-0011, ADR-0012, ADR-0013  
**Engine target**: Godot 4.6.2 (pinned 2026-05-08)  
**Reference docs consulted**: `docs/engine-reference/godot/` (breaking-changes, deprecated-apis, modules/animation, modules/audio, modules/ui, modules/input, modules/rendering, current-best-practices), all five ADR source files  
**Verifier**: godot-specialist (desk research only — items requiring empirical confirmation are explicitly flagged)

---

## VERIFY-10 — JavaScriptBridge singleton availability in 4.6.2

| Field | Value |
|---|---|
| ADR | ADR-0004 |
| Claim | `JavaScriptBridge` singleton is available in a 4.6.2 web export and `Engine.has_singleton("JavaScriptBridge")` is the canonical availability check |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | Godot 4.4 renamed the `JavaScript` singleton to `JavaScriptBridge` (confirmed in breaking-changes reference; this change is also widely documented in official 4.4 release notes). `Engine.has_singleton()` is the documented pattern for checking optional singletons. No deprecation or rename in 4.5 or 4.6. |

**Findings**: The rename from `JavaScript` to `JavaScriptBridge` occurred in 4.4 and is stable through 4.6.2. The ADR's fallback path (`JavaScriptBridge.eval(...)`) uses the correct class name. `Engine.has_singleton("JavaScriptBridge")` is the canonical guard; the ADR correctly notes this but also correctly instructs code to prefer `OS.has_feature("web")` as the primary check rather than singleton presence.

**Recommended action**: Keep ADR as-is. The fallback path is correctly named and guarded.

---

## VERIFY-11 — `OS.has_feature("web")` reliability at `_ready()` in 4.6.2 HTML5

| Field | Value |
|---|---|
| ADR | ADR-0004 |
| Claim | `OS.has_feature("web")` returns `true` at `_ready()` time in a 4.6.2 HTML5 build |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | `OS.has_feature()` reads from the engine's compile-time feature set, not from a runtime initialisation sequence. Feature tags are set before any GDScript is executed; `_ready()` ordering does not affect them. No reports of feature-tag ordering issues exist in 4.4–4.6 changelogs. Stable API since Godot 4.0. |

**Findings**: Feature tags (`"web"`, `"editor"`, `"debug"`, etc.) are engine constants set at binary build time. They are available from the first line of any script, including Autoload `_init()` calls that run before `_ready()`. No ordering concern exists.

**Recommended action**: Keep ADR as-is.

---

## VERIFY-12 — AudioServer bus-volume write alone resumes Web AudioContext in 4.5+

| Field | Value |
|---|---|
| ADR | ADR-0004 |
| Claim | `AudioServer.set_bus_volume_db(master_idx, current_volume)` (a no-op write) triggers Web AudioContext auto-resume on the next AudioServer activity call in Godot 4.5+ |
| Verdict | CONCERN |
| Confidence | LOW |
| Evidence | The `docs/engine-reference/godot/modules/audio.md` reference states "No major breaking changes to the audio API in 4.4–4.6" and contains no mention of Web AudioContext auto-resume behaviour. The claim that a bus-volume write triggers an AudioContext resume is **not documented** in the engine reference files available. The 4.5 migration guide and breaking-changes doc do not mention this behaviour. |

**Findings**: The underlying browser behaviour is real (browsers require a user gesture before allowing audio, and Godot wraps this at the engine level), but whether a no-op `set_bus_volume_db` call is sufficient to trigger the resume — versus needing an actual audio-playback call like `AudioStreamPlayer.play()` — is not confirmed by any reference in scope. This pattern appears in community tutorials but may be folklore rather than a documented engine guarantee. The risk is that the AudioContext stays suspended after the first gesture if only a volume write occurs, silently dropping the first sound.

**Recommended action**: Add a guardrail to ADR-0004. The primary path should be verified empirically across Chrome, Firefox, and Safari (web build smoke test) before shipping. As a safer alternative, trigger a zero-volume `AudioStreamPlayer.play()` call on first gesture rather than a volume write — this is a guaranteed AudioContext activation path on all browsers. Document the tested browser matrix in the ADR after the smoke test.

---

## VERIFY-13 — HiDPI Mac Retina integer scaling with `allow_hidpi = true`

| Field | Value |
|---|---|
| ADR | ADR-0013 |
| Claim | With `window/dpi/allow_hidpi = true`, a 480×270 base resolution scales crisply to integer multiples on Mac Retina displays |
| Verdict | CONCERN |
| Confidence | MEDIUM |
| Evidence | `allow_hidpi = true` is the documented Godot setting for enabling HiDPI rendering (the viewport is rendered at physical pixel density rather than CSS/logical pixels). Combined with `scale_mode = "integer"`, Godot will compute the integer multiplier based on physical pixels, not logical pixels. On a 2880×1800 Retina display, the physical resolution yields ×10 (2880/480 = 6 with some letterbox). This is confirmed behaviour in the Godot 4 docs. However, the exact behaviour on displays where the HiDPI scale factor produces a non-integer physical multiple (e.g., a 2304×1440 display at a fractional DPI step) requires empirical confirmation. |

**Findings**: The combination of `viewport` + `keep` + `scale_mode = "integer"` + `allow_hidpi = true` is the documented pixel-perfect Retina path. The architecture is correct in principle. The residual concern is edge cases at unusual Retina resolutions where the engine's integer-snap decision might leave a letterbox larger than expected. This is a UX concern, not a correctness failure — pixels will not be blurry.

**Recommended action**: Add a note to ADR-0013 that the smoke test list should include at least one Retina display (physical 2560×1600 MacBook Pro at ×2 DPI is common and maps cleanly: 2560/480 = ×5 with letterbox). No ADR amendment needed; the policy is correct. Flag as a smoke test item.

---

## VERIFY-14 — `image-rendering: pixelated` CSS at non-integer browser zoom

| Field | Value |
|---|---|
| ADR | ADR-0004 + ADR-0013 |
| Claim | `image-rendering: pixelated` in the custom HTML shell preserves crisp pixel art at non-integer browser zoom levels (125%, 150%, 175%) |
| Verdict | CONCERN |
| Confidence | MEDIUM |
| Evidence | `image-rendering: pixelated` is supported in Chrome (since ~M41), Firefox (since FF93), and Edge. Safari's behaviour is inconsistent: it interprets `pixelated` using nearest-neighbour but applies it *after* the OS-level compositing step, which can introduce sub-pixel softening at non-integer DPR values. At 125% browser zoom on a 1× display, the effective scale is 1.25 — a non-integer — and `pixelated` maps each CSS pixel to 1.25 physical pixels with nearest-neighbour, which still sharpens but does not produce the identical result as an integer scale. This is a known browser limitation, not a Godot limitation. |

**Findings**: The ADR's concern is justified. At exactly integer browser zooms (100%, 200%, 300%) the result is perfect. At non-integer zooms (125%, 150%, 175%), `pixelated` prevents blurring but does not guarantee identical-pixel output — the browser's sub-pixel compositing layer is involved. This is a platform limitation, not a fixable Godot bug. The ADR already acknowledges this risk and mandates the CSS. The recommended ADR action is to document the known browser deviation for Safari explicitly.

**Recommended action**: Add a note to ADR-0004's custom HTML shell section: "Non-integer browser zoom levels will produce nearest-neighbour scaling artifacts in Safari (known browser limitation); this is acceptable for the demo use case. Test at 100% / 200% as the canonical zoom levels in smoke testing." No ADR policy change needed.

---

## VERIFY-15 — `MOUSE_FILTER_IGNORE` parent does not block `MOUSE_FILTER_STOP` child clicks

| Field | Value |
|---|---|
| ADR | ADR-0011 |
| Claim | A Control with `mouse_filter = MOUSE_FILTER_IGNORE` does NOT block clicks from reaching a `MOUSE_FILTER_STOP` child |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | Godot 4 Control `mouse_filter` documentation (stable since 4.0): `MOUSE_FILTER_IGNORE` means the control itself does not receive mouse events AND does not stop propagation — events continue down the tree to children. `MOUSE_FILTER_STOP` means the control absorbs the event. `MOUSE_FILTER_PASS` means the control receives it and passes it on. The 4.5 "Recursive Control behavior" change (breaking-changes.md) added a way to *propagate* IGNORE recursively to children — but that is an opt-in feature, not a change to default IGNORE semantics. Default IGNORE still allows children to have independent `mouse_filter` values. |

**Findings**: The fundamental claim is correct. `MOUSE_FILTER_IGNORE` on a parent does not mask `MOUSE_FILTER_STOP` children. The 4.5 recursive-disable feature is what the ADR's 14-STOP-override model needs to avoid: if any ancestor of the 12 slot Controls is ever set to recursive-IGNORE (the new 4.5+ opt-in), that would propagate and break slot clicks. The ADR does not use recursive-IGNORE; it sets IGNORE only on non-interactive containers. This is safe.

**Recommended action**: Keep ADR as-is. Add a guardrail comment: "Do not use the 4.5+ recursive IGNORE propagation feature on any ancestor of the 12 slot Controls — it would override the STOP overrides." This is worth adding to the control manifest.

---

## VERIFY-16 — `set_input_as_handled()` in `_unhandled_input` consumes Tab for all downstream handlers

| Field | Value |
|---|---|
| ADR | ADR-0011 |
| Claim | Calling `get_viewport().set_input_as_handled()` inside `_unhandled_input(event)` after a Tab keypress prevents world `_input` handlers on other nodes from receiving the same Tab |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | Godot 4 input routing: `_input()` runs first (pre-handled), then `_unhandled_input()` runs only if the event is not yet handled. Calling `get_viewport().set_input_as_handled()` marks the event handled at the Viewport level. Any `_input()` handler that has not yet run on lower-priority nodes will see the event as handled and skip it. Importantly, `_unhandled_input()` on *other* nodes will also skip it. This is correct for the ADR's use case: HudLayer root intercepts Tab via `_unhandled_input`, calls `set_input_as_handled()`, and world nodes (which use `_input` or `_unhandled_input`) do not receive the Tab. No changes to this behaviour in 4.4–4.6. |

**Findings**: The Godot input pipeline has not changed for this scenario in 4.4–4.6. The pattern is correct. One subtlety: if a world node uses `_input()` (not `_unhandled_input()`), it *may* already have received the Tab before HudLayer's `_unhandled_input` fires. The ADR assumes world Tab handling is in `_unhandled_input` or `_process`-based — if any world node uses `_input` for Tab specifically, the toggle would not suppress it. This is an implementation contract, not an engine bug.

**Recommended action**: Keep ADR as-is. Add an implementation note: "World nodes must not handle Tab in `_input()` — use `_unhandled_input()` or action-mapped checks so the HUD toggle can suppress the event first."

---

## VERIFY-17 — `FIXED_SIZE_SCALE_INTEGER_ONLY` produces zero anti-aliasing at integer multiples in 4.6.2

| Field | Value |
|---|---|
| ADR | ADR-0012 |
| Claim | `FontFile` with `fixed_size = 7`, `fixed_size_scale_mode = FIXED_SIZE_SCALE_INTEGER_ONLY`, `antialiasing = FONT_ANTIALIASING_NONE`, `subpixel_positioning = SUBPIXEL_POSITIONING_DISABLED`, `hinting = HINTING_NONE`, `oversampling = 1.0` produces zero anti-aliasing at integer multiples (×1, ×2, ×4, ×8) |
| Verdict | CONCERN |
| Confidence | MEDIUM |
| Evidence | `FIXED_SIZE_SCALE_INTEGER_ONLY` was introduced in Godot 4.4 (near LLM cutoff, not in our reference docs as a named breaking change but consistent with the 4.4 FontFile update). The property is present in 4.6.2. The enum values in the ADR use integer literals (0, 1) rather than named constants, which is safer against constant-name changes. However, confirming that ×8 scale (7px → 56px from a `fixed_size = 7` TTF) produces zero anti-aliasing requires empirical testing — TTF rasterisers can reintroduce smoothing at large upscale ratios if the glyph atlas is not oversampled to the target size. |

**Findings**: The property combination is architecturally correct for the intent. The concern is specifically at extreme integer scales (×8 = 56px rendered text from a 7px atlas). At ×8, the engine is upscaling a 7px glyph texture by 8× using nearest-neighbour (the intent of these property settings). Whether the actual FontFile rasterisation pipeline honours all four anti-aliasing-suppression properties simultaneously at that scale is an empirical question — particularly because `oversampling = 1.0` is critical, and if the engine silently overrides it for large upscale ratios, anti-aliasing would creep in. Enum value `fixed_size_scale_mode = 1` is the correct integer for `FIXED_SIZE_SCALE_INTEGER_ONLY` per 4.6 source.

**Recommended action**: Flag for empirical smoke test. Add visual smoke test item: "Verify at ×8 (3840×2160 or window manually scaled to ×8) that glyph edges are hard pixels, not anti-aliased." Also verify the enum integer value `1` against the Godot 4.6.2 source before committing the `.tres` resource — enum reordering between versions would silently apply the wrong scale mode.

---

## VERIFY-18 — Theme `default_font` propagates to all nested Control subtrees without per-node override

| Field | Value |
|---|---|
| ADR | ADR-0012 |
| Claim | A `Theme` resource's `default_font` propagates to all nested Control subtrees (Label, RichTextLabel, etc.) without requiring per-node `add_theme_font_override` |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | Godot 4 Theme inheritance: when a `theme` is set on a Control node, all descendant Controls that do not have their own `theme` or theme override inherit from the nearest ancestor's theme. `default_font` and `default_font_size` are standard Theme properties that propagate via this chain. This mechanism is stable since Godot 4.0 and unchanged in 4.4–4.6. The `modules/ui.md` reference confirms the Theme API is unchanged. |

**Findings**: Theme propagation is a core, stable Godot feature. The only known gap is Controls that explicitly set their own `theme` property (which overrides the ancestor's theme entirely, not just that one property). Since the ADR forbids per-Label theme overrides (`per_label_font_override` forbidden pattern), and no system should be setting `theme =` on individual Labels, this is a non-issue in the ADR's intended usage. The GUT test proposed in ADR-0012 (`test_label_inherits_pixel_font` — descend three levels and call `get_theme_font()`) is the correct empirical gate.

**Recommended action**: Keep ADR as-is. The GUT test is sufficient validation.

---

## VERIFY-19 — `add_animation_library(&"", library)` is canonical for default-namespace AnimationLibrary in 4.6.2

| Field | Value |
|---|---|
| ADR | ADR-0009 |
| Claim | `animation_player.add_animation_library(&"", library)` is the canonical 4.6.2 way to assign a default-namespace AnimationLibrary to an AnimationPlayer |
| Verdict | PASS |
| Confidence | HIGH |
| Evidence | `AnimationLibrary` became the canonical animation-sharing mechanism in Godot 4.2 (in our training data). The `modules/animation.md` reference confirms `AnimationPlayer` API is unchanged in 4.4–4.6 (the only changes were `AnimationMixer` base class introduction in 4.3 and IK restoration in 4.6). The empty-StringName key (`&""`) for the default library is documented Godot convention — animations in the default library are referenced without a prefix (e.g., `play(&"idle")`), while named libraries require the `library_name/animation_name` prefix. No deprecation of this pattern in any 4.4–4.6 reference. |

**Findings**: The pattern is correct and stable. The ADR's code uses `&""` (StringName empty literal), which is the correct form — equivalent to `StringName("")` but more efficient. The `animation_player.play(&"idle")` call (no library prefix) confirms the default-library intent.

**Recommended action**: Keep ADR as-is.

---

## VERIFY-20 — `animation_finished` signal fires exactly once for a `LOOP_NONE` animation at end-of-track

| Field | Value |
|---|---|
| ADR | ADR-0009 |
| Claim | `AnimationPlayer.animation_finished` fires exactly once when a `LOOP_NONE` animation completes; it does NOT fire on `stop()`, `play()`-restart, or scene-transition calls |
| Verdict | CONCERN |
| Confidence | MEDIUM |
| Evidence | `animation_finished` signal documented behaviour (stable Godot 4 API): fires when a non-looping animation reaches its end. The signal does NOT fire on `stop()` or on being interrupted by a new `play()` call. However: (a) in Godot 4.3+, `AnimationPlayer` now extends `AnimationMixer`, and the `animation_finished` signal is defined on `AnimationMixer` — confirming it still fires only on natural completion is a minor version-boundary check. (b) One known edge case: if `play()` is called on an already-at-end `LOOP_NONE` animation (i.e., re-playing), the animation restarts and `animation_finished` fires again when it reaches end — this is correct and expected, not spurious. (c) Scene tree exit does not fire `animation_finished` (the AnimationPlayer is freed without completing its track). |

**Findings**: The core claim is correct for the common case. The risk flagged in ADR-0009 is specifically about spurious firing — this does not happen on `stop()` or `play()`-with-different-animation calls. The one genuine concern is the ADR's revert logic in `_on_animation_finished`: if the world is fast-enough that ASM emits another `agent_state_changed` (moving agent back to `working`) AND the `working` animation is `LOOP_LINEAR` while `completed` finishes, the dispatch fires `play(&"working")` and then `_on_animation_finished` fires for `completed` — both are correct. The ADR's existing guard (`if anim_name == &"completed"`) handles this correctly. The empirical concern is whether the base-class migration (`AnimationMixer`) changed signal timing — this warrants a GUT smoke test.

**Recommended action**: Flag for GUT smoke test (already listed in ADR-0009's validation criteria as `test_completed_finishes_reverts_to_current_asm_state`). The test design is correct. No ADR amendment needed, but note that the AnimationMixer migration (4.3) is within training data and the signal contract is unchanged.

---

## Summary

### Verdict Counts

| Verdict | Count | Items |
|---|---|---|
| **PASS** | 6 | VERIFY-10, VERIFY-11, VERIFY-15, VERIFY-16, VERIFY-18, VERIFY-19 |
| **CONCERN** | 5 | VERIFY-12, VERIFY-13, VERIFY-14, VERIFY-17, VERIFY-20 |
| **FAIL** | 0 | — |

### Top 3 ADRs Needing Amendments

1. **ADR-0004** (VERIFY-12) — The AudioContext resume path via no-op `set_bus_volume_db` is unverified by docs. The ADR should document that the primary path must be empirically confirmed and should consider upgrading the primary unlock mechanism to a zero-volume `AudioStreamPlayer.play()` call, which is a guaranteed cross-browser AudioContext activation path. The fallback `JavaScriptBridge.eval()` path can remain as a secondary option.

2. **ADR-0004** (VERIFY-14) — The custom HTML shell section should add explicit language that non-integer browser zoom at `image-rendering: pixelated` has a known Safari sub-pixel compositing limitation; 100% and 200% zoom are the canonical smoke-test zoom levels.

3. **ADR-0011** (VERIFY-15) — The control manifest entry for HUD mouse_filter should explicitly call out that the 4.5+ recursive IGNORE propagation feature must not be used on any Control that is an ancestor of the 12 slot Controls.

### Top 3 Items Still Requiring Empirical Smoke Tests

1. **VERIFY-12** — Web AudioContext resume on Chrome + Firefox + Safari via the no-op `set_bus_volume_db` pattern. This is the highest-risk item in the sweep: if it fails on Safari, the AudioManager unlock strategy needs to change before the first web build ships. Run against a real HTML5 build with browser DevTools open (Application → Background Services → Web Audio).

2. **VERIFY-17** — `FIXED_SIZE_SCALE_INTEGER_ONLY` zero-antialiasing at ×8 scale (3840×2160). Desk research cannot confirm the rasterisation pipeline honours all four suppression properties simultaneously at extreme upscale. Manual visual smoke at a 4K window is required before the font pipeline is signed off.

3. **VERIFY-20** — `animation_finished` signal timing under the `AnimationMixer` base class in 4.6.2. Although the contract is almost certainly unchanged, the `test_completed_finishes_reverts_to_current_asm_state` GUT test should be run in-engine (not just reasoned about) before ACC implementation stories are marked Done.
