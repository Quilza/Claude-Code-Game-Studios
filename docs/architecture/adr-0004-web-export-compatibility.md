# ADR-0004: Web Export Compatibility

## Status
Accepted (2026-05-12)

## Date
2026-05-12

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | HTML5 export / Platform |
| **Knowledge Risk** | HIGH — Godot 4.5 changed Web AudioContext handling and renamed the JavaScript singleton to `JavaScriptBridge`; 4.6 made D3D12 default on Windows. LLM-trained patterns from <4.4 era likely do not apply. CORS behaviour with AI providers is empirical, not guessable. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, Godot 4.6 release notes |
| **Post-Cutoff APIs Used** | `JavaScriptBridge` (4.5+ rename); Web AudioContext auto-resume behaviour (4.5+); export preset texture compression toggle paths |
| **Verification Required** | VERIFY-4 (texture compression option location in 4.6 Export Presets); new VERIFY-10: confirm `JavaScriptBridge` singleton is available in 4.6.2 web export; new VERIFY-11: confirm `OS.has_feature("web")` is true at `_ready()` time in a 4.6.2 HTML5 build; new VERIFY-12: confirm AudioServer activity alone resumes the AudioContext on first user gesture in Chrome + Firefox + Safari |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 Config Loading + Persistence (Accepted) — `is_mock()` must be queryable at runtime and the override mutates `_config` after parse. ADR-0003 Autoload Scene Composition (Accepted) — ConfigurationLoader + AudioManager are the only Autoloads; both gain web-specific paths. |
| **Enables** | ADR-0001 Data Bridge Transport finalisation (web behaviour was the last open question); Data Bridge prototype (Section C Q6 answered); HTML5 export pipeline. |
| **Blocks** | Web export build attempts; any Data Bridge implementation story that asserts behaviour on `OS.has_feature("web")` paths. |
| **Ordering Note** | Should be Accepted before ADR-0001's `Proposed → Accepted` flip — ADR-0001 currently references "web CORS deferred to prototype"; this ADR closes that hole. |

## Context

### Problem Statement

The project ships on PC (Windows/macOS/Linux) and Web (HTML5). The Web target introduces three platform-specific constraints that no current ADR addresses:

1. **CORS blocks direct browser→AI-API calls.** Anthropic's API, OpenAI's API, and most managed AI services do not send `Access-Control-Allow-Origin: *` headers. A Godot Web export running in a browser is subject to the same-origin policy. The Data Bridge GDD (Rule 7 + Section C Q6) explicitly defers this to a prototype. Without an answer, the web build cannot reach real agents.

2. **Web AudioContext requires user-gesture unlock.** Modern browsers (Chrome, Safari, Firefox) suspend the AudioContext until a user gesture occurs. AudioManager's `_ready()` cannot play audio on web. TR-audio-006 flags this; no ADR currently addresses it. Without unlock handling, the first SFX on web is silently dropped.

3. **Web export-specific Godot settings** (VERIFY-4 — texture compression option location in 4.6 Export Presets) are post-cutoff knowledge. Wrong settings produce broken builds or massive bundle sizes.

A single ADR must establish the project-wide stance on each.

### Constraints
- Engine: Godot 4.6.2 / GDScript / Web export via HTML5 template
- This is a developer tool — primary user runs PC; web is for demos, screenshots, sharing
- We do not control the AI API providers — cannot ask Anthropic/OpenAI to add CORS headers
- We will not ship a separate user-run proxy binary for MVP (configuration burden contradicts the polished bunker-tool aesthetic)
- ConfigurationLoader already supports `mock: bool` at top level (ADR-0008)

### Requirements
- Web build must produce a working, demoable experience without manual user configuration
- Real-API access on web is **out of scope for MVP**
- AudioContext must unlock cleanly on first user gesture
- Web export settings must be pinned so a fresh checkout can build the web target

## Decision

### TL;DR
**Web build is MVP-supported as a demo-only target with mock mode forced on.** ConfigurationLoader auto-overrides `mock: false` to `mock: true` when `OS.has_feature("web")` is true. AudioManager subscribes to the first input event to unlock Web AudioContext. Web export preset settings are pinned in this ADR. No escape hatch for web→real-API in MVP.

### Mock Mode Forced on Web (override layer)

ConfigurationLoader applies a single override **after** parsing `config.json` and **before** exposing `is_mock()` to consumers:

```gdscript
# ConfigurationLoader._ready() — after parsing config.json
if OS.has_feature("web") and not _config.get("mock", false):
    push_warning("[ConfigLoader] Web export forces mock=true (CORS); real-API config ignored")
    _config["mock"] = true
    _config["web_mock_forced"] = true   # observability flag for tests / future UI
```

Rationale:
- Eliminates CORS as a HIGH unknown for MVP (no provider testing needed)
- Web build is still demoable — mock mode produces the full bunker experience
- `web_mock_forced` flag lets a future "demo mode" badge appear on the HUD if desired
- Post-MVP, this override can be replaced with a real CORS-aware transport without breaking the override contract (set `web_mock_forced` to false when a real path is detected)

This override is **not** a soft policy. It is enforced at the ConfigurationLoader level so no consumer downstream can re-enable real polling on web. No `force_web_real_api` escape hatch ships in MVP; if a future requirement demands web→real-API access, supersede this ADR with a web-real-API ADR that establishes the contract explicitly.

### Web AudioContext Resume

AudioManager arms a one-shot `_input()` handler at `_ready()` on web only:

```gdscript
# AudioManager._ready()
if OS.has_feature("web"):
    set_process_input(true)  # arm one-shot unlock handler

func _input(event: InputEvent) -> void:
    if not OS.has_feature("web"):
        return
    var is_press: bool = (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed()
    if not is_press:
        return
    # Godot 4.5+: Web AudioContext auto-resumes on next AudioServer activity.
    # Touching the Master bus volume is a no-op write that triggers activity.
    var master_idx: int = AudioServer.get_bus_index(&"Master")
    AudioServer.set_bus_volume_db(master_idx, AudioServer.get_bus_volume_db(master_idx))
    set_process_input(false)  # one-shot
```

**Fallback path (brittle, only if VERIFY-12 fails):** explicit `JavaScriptBridge.eval("if (window._godot_audio_ctx) window._godot_audio_ctx.resume();")`. This reaches into engine internals and should only be added if the AudioServer-only path proves unreliable across target browsers. Document the failure mode + browser if this fallback is needed.

### Web Export Preset (pinned settings)

`export_presets.cfg` for the Web preset must include:

| Setting | Value | Why |
|---|---|---|
| `custom_template/debug` | unset (use default) | Default debug template |
| `custom_template/release` | unset (use default) | Default release template |
| `variant/extensions_support` | `false` | GDExtension not used by MVP |
| `vram_texture_compression/for_desktop` | `false` | Web target — no S3TC |
| `vram_texture_compression/for_mobile` | `true` | ETC2 needed for mobile browsers |
| `html/export_icon` | `true` | Cosmetic — bunker icon |
| `html/custom_html_shell` | `web/shell.html` (project-local) | Required for AudioContext unlock + canvas resize handling |
| `html/head_include` | `<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">` | Prevents iOS pinch-zoom interfering with input |
| `progressive_web_app/enabled` | `false` | Out of scope for MVP |
| `progressive_web_app/offline_page` | `""` | N/A |

VERIFY-4 closure: the `vram_texture_compression` settings live under the Web preset's **Variant** section in Godot 4.6.2 (Project → Export → Web → Variant tab). Path confirmed against 4.6 release notes; godot-specialist consultation recommended before shipping the first web build to confirm exact UI wording.

### Custom HTML Shell

A minimal custom HTML shell at `web/shell.html` is required to:
1. Provide a "click to start" overlay that guarantees a user gesture before AudioContext access
2. Set the canvas to `image-rendering: pixelated` for crisp pixel art at non-integer browser zooms
3. Handle window-resize → canvas dimension updates

The shell itself is authored under a separate implementation story. This ADR pins its existence, location, and the three requirements above. Pin shell to a Godot major version; review on every Godot upgrade.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Bootstrap — OS.has_feature("web") branch                    │
│                                                              │
│  ConfigurationLoader._ready()                                │
│   ├─ parse config.json                                       │
│   ├─ if web AND not mock: force mock=true + push_warning     │
│   │   └─ set web_mock_forced=true (observability)            │
│   └─ expose is_mock() == true                                │
│                                                              │
│  AudioManager._ready()                                       │
│   ├─ create bus topology (Master → Music + SFX)              │
│   ├─ pre-instantiate 8 AudioStreamPlayer pool                │
│   └─ if web: arm _input() one-shot for AudioContext resume   │
│                                                              │
│  DataBridge._ready()                                         │
│   └─ ConfigLoader.is_mock() == true → MockBridge driver      │
│       (no HTTPRequest nodes created on web)                  │
│                                                              │
│ Result: web demo runs mock-only, audio unlocks on first      │
│ click/key, no CORS failures possible.                        │
└─────────────────────────────────────────────────────────────┘
```

### Key Interfaces

This ADR does not add new public APIs. It adds:
- Optional config field `web_mock_forced: bool` (observability only — never user-set, never read by consumers other than tests / future demo-badge UI)
- Implicit contract: `OS.has_feature("web")` is the canonical web-detection check; do not use `JavaScriptBridge` availability or `Engine.has_singleton("JavaScriptBridge")` as a proxy

Registry updates when Accepted:
- `web_mock_force_pattern` api_decision in `docs/registry/architecture.yaml`
- `web_real_api_polling` forbidden_pattern (any code path that would call HTTPRequest on web for AI APIs is banned)
- `os_has_feature_web` canonical_check entry

## Alternatives Considered

### Alternative A — User-run local CORS proxy

- **Description**: Ship a tiny Python/Node proxy binary. User runs it; web build points at `http://localhost:PORT` instead of `https://api.anthropic.com`. Proxy adds CORS headers.
- **Pros**: Real-API access from web; matches some dev tools' approach.
- **Cons**: User must install Python/Node + run separate binary; contradicts the polished aesthetic; doubles support burden; proxy binary needs its own update channel; localhost-only proxy still fails for users on iPads/phones.
- **Rejection Reason**: Out of scope for MVP. Adds a configuration step that breaks "open it up, it works." Reconsider post-MVP if web becomes a primary path.

### Alternative B — Skip web export entirely for MVP

- **Description**: Configure project for PC-only. Drop the Web target from `export_presets.cfg`.
- **Pros**: Smallest scope; zero CORS/AudioContext work needed.
- **Cons**: Loses the ability to share screenshots/demos via browser; `technical-preferences.md` lists web as a target — would require updating multiple docs and the project identity.
- **Rejection Reason**: Web demo has high "showability" value for a dev tool. Forcing mock-mode preserves the showability without the CORS engineering.

### Alternative C — Hosted relay service we operate

- **Description**: Host a relay service (`api.thesituationroom.app`) that the web build hits; relay proxies to user's chosen AI API using a token they paste into the bunker.
- **Pros**: Full real-API web experience; no user-side setup.
- **Cons**: Now we're operating server infrastructure; security/privacy implications (we'd see all agent payloads); breaks the "local tool" identity; ongoing hosting cost.
- **Rejection Reason**: Out of scope by a wide margin. The project is "tool with game aesthetic", not SaaS.

### Alternative D — Provider-by-provider CORS audit at runtime

- **Description**: Some smaller AI providers do send CORS headers. Have ConfigLoader test each agent's endpoint at startup; if CORS works, allow; if not, force mock.
- **Pros**: Best-case: some users get real data on web.
- **Cons**: Probe traffic is wasteful; user expectations get confused (why does Provider X work but Provider Y not?); empirical behaviour belongs in a prototype, not production.
- **Rejection Reason**: Wrong place to make a per-provider call. If a future provider ships CORS-friendly endpoints, supersede this ADR with a web-real-API ADR.

### Alternative E — Add `force_web_real_api: true` escape hatch

- **Description**: Power-user opt-in field that bypasses the override (e.g. for a user running their own CORS proxy at localhost).
- **Pros**: Allows advanced users to point the bunker at a custom proxy.
- **Cons**: Surfaces an unsupported configuration path in MVP; doubles the test matrix; complicates the "web = always mock" mental model that downstream consumers depend on.
- **Rejection Reason**: Easier to relax later than to retract. Defer until a real demand exists.

## Consequences

### Positive
- Closes Data Bridge Section C Q6 (CORS strategy) without a prototype dependency
- Closes VERIFY-4 (export preset menu locations documented)
- Web build is demoable from day one
- AudioContext unlock is solved project-wide, not per-screen
- HIGH-risk engine unknown removed from the pre-production gate's punch list
- Downstream consumers can rely on `is_mock() == true` on web as an invariant

### Negative
- Web build cannot show real agent data — only the mock cycle
- Custom HTML shell adds a maintenance surface (~50 lines of HTML/JS)
- Override logic in ConfigLoader breaks the "config.json is the source of truth" purity slightly — must be documented as the only sanctioned post-parse mutation

### Risks

| Risk | Mitigation |
|---|---|
| Future provider ships CORS-friendly endpoints, override blocks them | Documented escape hatch: supersede this ADR with web-real-API ADR. `web_mock_forced` observability flag makes the override visible. |
| AudioContext resume doesn't work reliably across browsers (VERIFY-12) | Fallback explicit `JavaScriptBridge.eval()` documented above; manual smoke test on Chrome + Firefox + Safari before each release |
| Custom HTML shell drifts from Godot's default | Pin shell to a Godot major version; review shell on every Godot upgrade; treat shell.html as a versioned artifact in `web/` |
| User confused why web build doesn't show real data | "Demo mode" HUD badge (post-MVP); README note for web target; `web_mock_forced` flag available for HUD wiring |
| `OS.has_feature("web")` returns false in some 4.6.2 path (VERIFY-11) | If unreliable, fall back to `Engine.has_singleton("JavaScriptBridge")` — but document the regression and file an engine issue |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `data-bridge.md` | Rule 7 / Section C Q6 (web CORS strategy) | Mock-forced override; no HTTPRequest nodes created on web |
| `data-bridge.md` | TR-data-bridge-008 (Web export CORS strategy) | Decided: PC-only real-API; web = mock-forced |
| `audio-manager.md` | TR-audio-006 (Web AudioContext requires user-gesture unlock) | One-shot `_input()` handler in AudioManager |
| Cross-cutting | All systems must respect `OS.has_feature("web")` consistently | Canonical web-detection check codified |

## Performance Implications
- **CPU**: Zero added cost on PC. On web, the one-shot `_input()` handler runs until first gesture (sub-µs cost per event)
- **Memory**: Zero — no new persistent objects; the input handler de-arms after first use
- **Load Time**: Mock-mode skips HTTPRequest instantiation on web — slightly faster startup
- **Network**: Zero web-build outbound traffic to AI APIs by design

## Migration Plan
No existing code to migrate (pre-production). ConfigurationLoader override + AudioManager input-listener apply at first implementation. Web export preset to be created from this ADR as a checklist when the first web build is attempted.

## Validation Criteria
- GUT test (headless, simulating `OS.has_feature("web")` via test injection): `test_configloader_web_forces_mock` — confirm `is_mock()` returns true when web feature is present even if `mock: false` in config
- GUT test: `test_configloader_web_emits_warning` — confirm `push_warning` fires when override engages
- GUT test: `test_configloader_web_sets_observability_flag` — confirm `web_mock_forced` flag is set to true
- Manual smoke test (web build): Audio plays after first click; no AudioContext warnings in browser console
- Manual smoke test (web build): No outbound HTTP requests to AI APIs visible in browser DevTools Network tab
- Visual smoke test: Web build renders identical to PC mock-mode build at the same browser zoom

## Related Decisions
- ADR-0001 Data Bridge Transport Strategy — referenced "CORS deferred to prototype"; this ADR closes that
- ADR-0002 Config Loading + Persistence — sanctions the web override as the only post-parse mutation
- ADR-0003 Autoload Scene Composition — ConfigLoader + AudioManager are the only Autoloads; both gain web-specific paths
- ADR-0008 Mock Mode Strategy — the override sets `is_mock()` to true, hooking into the existing mock pipeline
- VERIFY-4 — closed by this ADR
- New VERIFY-10, VERIFY-11, VERIFY-12 — opened by this ADR
- TR-data-bridge-008, TR-audio-006 — covered by this ADR

---

## Amendment 2026-05-12 (post-engine-verify-sweep)

Source: `docs/architecture/verify-sweep-2026-05-12.md` (godot-specialist consultation)

### A1 — AudioContext unlock primary path upgraded

**VERIFY-12 verdict**: CONCERN (LOW confidence). The original primary path (no-op `set_bus_volume_db` write to trigger AudioContext resume) is **undocumented engine behaviour** — it appears in community tutorials but is not in official Godot 4.4–4.6 docs. Risk: on Safari, the first SFX after user gesture may still be silently dropped if `set_bus_volume_db` alone does not wake the AudioContext.

**Amended pattern**: prefer a **zero-volume one-shot `AudioStreamPlayer.play()`** as the canonical activation path. This is a guaranteed cross-browser AudioContext-wake mechanism (the browser unlocks on any actual audio playback, not on volume metadata writes).

```gdscript
# AudioManager._ready()  — AMENDED
var _audio_unlock_player: AudioStreamPlayer
if OS.has_feature("web"):
    _audio_unlock_player = AudioStreamPlayer.new()
    _audio_unlock_player.bus = &"Master"
    _audio_unlock_player.volume_db = -80.0   # effectively silent
    _audio_unlock_player.stream = preload("res://assets/audio/silence_50ms.ogg")
    add_child(_audio_unlock_player)
    set_process_input(true)

func _input(event: InputEvent) -> void:
    if not OS.has_feature("web"):
        return
    var is_press: bool = (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed()
    if not is_press:
        return
    _audio_unlock_player.play()         # guaranteed AudioContext wake
    set_process_input(false)            # one-shot
```

The original `set_bus_volume_db` pattern remains documented as the **fallback fallback** if the silence asset can't ship. The `JavaScriptBridge.eval()` path documented above remains the brittle-but-explicit last resort.

**Required asset addition**: `res://assets/audio/silence_50ms.ogg` — a 50ms silent OGG. Trivially generated via `ffmpeg -f lavfi -i anullsrc=channel_layout=mono:sample_rate=44100 -t 0.05 silence_50ms.ogg`. Roughly 1KB.

**Smoke test mandate**: Before any web build ships, run the full path on Chrome + Firefox + Safari with browser DevTools open (Application → Background Services → Web Audio) and confirm AudioContext transitions from "suspended" → "running" within one frame of first user gesture. Document the tested browser/version matrix.

### A2 — Safari non-integer browser zoom limitation documented

**VERIFY-14 verdict**: CONCERN (MEDIUM confidence). `image-rendering: pixelated` is supported in all target browsers but Safari applies it AFTER the OS-level compositing step, which introduces sub-pixel softening at non-integer device-pixel-ratios (browser zoom 125%, 150%, 175%).

**Stance**: this is a platform limitation, not a Godot bug. We accept it.

**Required documentation in `web/shell.html`**: a comment in the HTML shell that 100% and 200% browser zoom are the canonical pixel-perfect zoom levels. Smoke testing focuses on those two.

### A3 — JavaScriptBridge availability confirmed

**VERIFY-10 verdict**: PASS (HIGH confidence). `JavaScriptBridge` singleton (renamed from `JavaScript` in 4.4) is stable through 4.6.2. The fallback path in this ADR uses the correct class name. No change required.

### A4 — `OS.has_feature("web")` reliability at `_ready()` confirmed

**VERIFY-11 verdict**: PASS (HIGH confidence). Feature tags are compile-time engine constants; available from the first line of any script. No ordering concerns. No change required.
