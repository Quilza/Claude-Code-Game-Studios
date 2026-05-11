# ADR-0002: Configuration Loading + Persistence

## Status
Accepted (2026-05-11)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / FileAccess |
| **Knowledge Risk** | LOW — FileAccess stable since 4.0. One post-cutoff change: `FileAccess.store_*` returns `bool` (was `void` pre-4.4) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | `FileAccess.store_*` return `bool` (changed 4.4 — documented in `configuration-loader.md` implementation notes) |
| **Verification Required** | VERIFY: confirm `user://` IndexedDB persistence across page reloads in Godot 4.6.2 HTML5 export. VERIFY: `res://config.json` included in `.pck` via HTML5 export Resources filter (build-process check, not code) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Autoload Scene Composition) — ConfigLoader must be established as an Autoload before its load strategy is relevant |
| **Enables** | ADR-001 (Data Bridge — calls `get_agents()`, `get_poll_interval()`, `is_mock()`), ADR-008 (Mock Mode — uses `is_mock()`), ADR-014 (Test Framework — depends on test-mode fallback) |
| **Blocks** | ConfigLoader implementation; any GUT test that instantiates ConfigLoader |
| **Ordering Note** | Must be Accepted before any code calling `ConfigLoader.get_agents()` or `set_setting()` is written |

## Context

### Problem Statement

`ConfigLoader` (established by ADR-0003 as an Autoload) must load data from two sources:

1. **`config.json`** — integration config (agents, endpoints, poll interval). Lives outside the application binary on PC (developer-editable without rebuilding), but inside the export package on Web (developer bakes it at export time).
2. **`user://settings.json`** — user preferences (audio mute, volumes, HUD knobs). Must persist across app launches on both PC and Web.

The file paths, platform detection logic, schema versioning contract, settings ownership model, and test-mode fallback must all be decided before ConfigLoader can be implemented.

### Constraints

- **PC**: `config.json` must be outside the application binary and editable by the developer without rebuilding.
- **Web**: there is no writable filesystem outside the export bundle; developer edits `res://config.json` and rebuilds the web export.
- **macOS**: `.app` bundle packages the executable at `MyGame.app/Contents/MacOS/MyGame` — `get_base_dir()` alone resolves to inside the bundle, not beside it.
- **user://**: Maps to the OS user data directory on PC, and to IndexedDB in HTML5 exports (Godot handles this transparently — no code difference at the call site).
- **Settings ownership**: ConfigLoader is the sole owner of `user://settings.json`. AudioManager, HUD, and all other systems call `get_setting()` / `set_setting()` — no system writes its own prefs file.
- **GUT isolation**: tests run in the editor must boot ConfigLoader without a real `config.json` present.
- **FileAccess write returns**: `store_*` methods return `bool` in Godot 4.4+ — all write calls must check the return value.

### Requirements

- Resolve `config.json` path correctly for: Web (`res://`), in-editor (project root), macOS (beside `.app`), Windows/Linux (beside executable)
- `user://settings.json`: load once at `_ready()`, write synchronously on `set_setting()`, emit `setting_changed`, persist across launches
- `schema_version` integer field: mismatch → `CONFIG_INVALID`; absent → no mismatch (treated as pre-versioning)
- Test-mode fallback: return safe empty defaults in editor when config.json absent; do not enter `CONFIG_MISSING`
- `is_mock()` added to config.json schema as optional boolean field
- All `FileAccess.store_*` calls must check the `bool` return value

## Decision

### 1. config.json Path Resolution (four-case)

```gdscript
func _get_config_path() -> String:
    if OS.has_feature("web"):
        # Web export: config.json baked into the project at res://
        # IMPORTANT: res://config.json must be included in the HTML5 export Resources filter
        return "res://config.json"
    elif OS.has_feature("editor"):
        # In-editor: project root, globalized to a filesystem path
        return ProjectSettings.globalize_path("res://config.json")
    elif OS.has_feature("macos"):
        # macOS .app bundle: executable is at MyGame.app/Contents/MacOS/MyGame
        # Walk up 3 levels to reach the directory containing MyGame.app
        return OS.get_executable_path().get_base_dir() \
            .get_base_dir().get_base_dir() \
            .path_join("config.json")
    else:
        # Windows, Linux: config.json beside the executable binary
        return OS.get_executable_path().get_base_dir().path_join("config.json")
```

The web path (`res://config.json`) is **read-only at runtime** — no code may attempt to write back to `res://` on any platform. Settings writes always go to `user://settings.json`.

**PC deployed build**: developer places `config.json` in the same directory as the `.exe` (Windows) or binary (Linux).

**macOS deployed build**: developer places `config.json` beside `MyGame.app` — not inside the bundle.

**Web export**: developer edits `res://config.json` in the project, then re-exports. To change agents on web, a rebuild is required. This is the accepted trade-off for a self-hosted developer tool.

### 2. Settings Persistence — `user://settings.json`

ConfigLoader is the **sole owner** of `user://settings.json`. All other systems call ConfigLoader for all preferences.

**Load**: loaded once in `_ready()`, after `config.json` processing. If `user://settings.json` is absent (first run) → use hardcoded defaults; do not create the file until the first `set_setting()` call.

**Write**: `set_setting()` writes immediately to `user://settings.json`. Checks `FileAccess.store_*` `bool` return; logs `push_warning()` on failure without crashing.

**On web (HTML5)**: `user://` maps to IndexedDB. Godot handles the mapping transparently. Data persists across page refreshes and browser sessions until the user clears browser site data.

**Initial settings schema** (not user-editable directly — managed via in-app controls):

```json
{
  "audio_master_mute": false,
  "audio_music_volume_db": -18.0,
  "audio_sfx_volume_db": -12.0
}
```

Keys are additive — future keys can be added without a versioning bump. Unrecognised keys are silently ignored. The settings schema is not versioned for MVP.

### 3. Schema Versioning

```gdscript
const CONFIG_SCHEMA_VERSION: int = 1
```

Optional `schema_version` integer field in `config.json`:

| Field state | Behaviour |
|---|---|
| **Absent** | Treated as pre-versioning. Load proceeds without a mismatch error. |
| **Present, matches** (`== CONFIG_SCHEMA_VERSION`) | Load proceeds normally. |
| **Present, mismatches** (any other value) | `CONFIG_INVALID` — message: `"schema_version mismatch: file is version X, loader expects version 1. Consult the migration guide for this version."` |

Schema version bumps require a new ADR superseding ADR-0002.

### 4. `is_mock()` — Config Schema Addition

Optional boolean field `mock` in `config.json`:

```json
{ "mock": true, "agents": [...] }
```

Absent or `false` → `is_mock()` returns `false`. Used by ADR-008 (Mock Mode Strategy) to swap the DataBridge polling driver without conditional code in any consumer.

### 5. Test-Mode Fallback

When `OS.has_feature("editor")` is true AND `config.json` is absent at the editor path → ConfigLoader enters silent test-mode:

- Does **not** enter `CONFIG_MISSING`
- Does **not** generate a template file
- Does **not** show the pre-bunker error screen
- Returns `TEST_DEFAULTS` from all getters
- Emits `config_loaded` normally (GUT tests can proceed as if config is ready)

```gdscript
const TEST_DEFAULTS: Dictionary = {
    "agents": [],
    "poll_interval_sec": 5.0,
    "protocol": "http_poll",
    "mock": false
}
```

Production exports (non-editor builds) always enter `CONFIG_MISSING` when the file is absent. The test-mode fallback is never active in shipped builds.

### Architecture Diagram

```
ConfigLoader._ready()
        │
        ├── _get_config_path()
        │       ├── web?      → "res://config.json"  (read-only, baked in export)
        │       ├── editor?   → ProjectSettings.globalize_path("res://config.json")
        │       ├── macos?    → get_base_dir()×3 + "/config.json"
        │       └── else      → get_base_dir() + "/config.json"
        │
        ├── FileAccess.open(path, READ)
        │       ├── null + editor? → test-mode fallback → emit config_loaded
        │       ├── null + prod    → CONFIG_MISSING (generate template, error screen)
        │       └── ok            → JSON.parse_string()
        │                               ├── parse fail → CONFIG_MALFORMED
        │                               └── ok → validate schema → READY / CONFIG_INVALID
        │                                         │
        │                                    emit config_loaded
        │
        └── FileAccess.open("user://settings.json", READ)
                ├── null → use hardcoded defaults, no file created yet
                └── ok  → load prefs dict → available via get_setting()
```

### Key Interfaces

```gdscript
class_name ConfigurationLoader extends Node

const CONFIG_SCHEMA_VERSION: int = 1

signal config_loaded
signal config_load_failed(state: String, message: String)
signal setting_changed(key: StringName, value: Variant)

# Config data (valid after config_loaded fires; returns safe defaults before)
func get_agents() -> Array[Dictionary]
func get_agent(id: String) -> Dictionary
func get_poll_interval() -> float
func get_protocol() -> String
func get_state() -> String           # UNINITIALIZED | LOADING | READY | CONFIG_*
func get_applied_defaults() -> Array[String]
func is_mock() -> bool               # reads "mock": true from config.json

# Settings persistence (always available; returns defaults if settings file absent)
func get_setting(key: StringName, default: Variant = null) -> Variant
func set_setting(key: StringName, value: Variant) -> void
```

## Alternatives Considered

### Alternative B: `user://config.json` on all platforms

- **Pros**: Single code path; writable everywhere.
- **Cons**: Violates GDD requirement for "next to executable" UX on PC. On web, `user://` = IndexedDB — not a human-readable text file the developer can edit externally.
- **Rejection Reason**: GDD explicitly requires the PC path to be the executable directory. IndexedDB isn't an external-editor target.

### Alternative C: HTTP fetch for web config

- **Pros**: Config can change on a live web server without rebuilding the export.
- **Cons**: Requires a server; adds async complexity to boot (all Phase 2 systems must wait for an HTTP round-trip); out of scope for a personal developer tool.
- **Rejection Reason**: Self-hosting a config-serving server for personal use is unnecessary overhead for MVP.

### Alternative D: Per-system settings files

- **Pros**: Each system self-contained.
- **Cons**: Multiple files; no unified migration point; key collision risk.
- **Rejection Reason**: ConfigLoader is already the Foundation-layer data service. Central settings is consistent and testable.

## Consequences

### Positive

- Single code path for config loading (branched only at path resolution).
- `user://` settings work identically on PC and web — no code difference at the call site.
- Schema versioning enables future breaking changes to be surfaced clearly to developers.
- Test-mode fallback enables GUT suite to run without infrastructure setup.
- `is_mock()` is schema-native — no out-of-band mechanism needed for Mock Mode.

### Negative

- Web config changes require a rebuild (accepted for a self-hosted developer tool).
- Four-case path resolution adds complexity to `_ready()` — isolated to one function.
- `user://settings.json` on web is IndexedDB — clearing browser site data loses settings. Acceptable for a developer tool.

### Risks

- **macOS path regression**: if the four-case logic is simplified during implementation, macOS exports will silently look inside the bundle. The macOS branch must be covered by a GUT test (mock `has_feature("macos")`) and tested against an actual macOS export before release.
- **`res://config.json` not bundled on web**: if the developer omits `*.json` from the HTML5 export Resources filter, `FileAccess.open("res://config.json")` returns `null` silently — CONFIG_MISSING occurs with no meaningful differentiation from "file truly absent". The error screen must include a web-specific note: "Check that config.json is included in your export preset's Resources filter."
- **IndexedDB write-then-close race on web**: `user://` writes are flushed to IndexedDB at end-of-frame (Godot's Emscripten `idbfs` sync). A hard browser close before that flush may lose the last `set_setting()` call. Low severity for a developer tool; acknowledged but no mitigation required.
- **Null FileAccess guard**: `FileAccess.open()` returns `null` on failure (file absent, permissions, not bundled on web). Every call site must check for `null` before calling any method on the result. Missing this check causes a null method call crash, not a graceful error state. This is a load-bearing implementation requirement.
- **`FileAccess.store_*` return type** (4.4+ change): all write calls must check the `bool` return. A `false` return not caught will silently fail to persist settings. Implementation must treat `false` returns as `push_warning()` events.

### Deployment Notes (web export)

`res://config.json` must be included in the HTML5 export preset's "Resources" filter. Add `*.json` to the non-resource include list, or add the specific filename. Without this, the file is not bundled in the `.pck` and CONFIG_MISSING occurs — with no obvious indication that it's a build configuration issue rather than a missing file.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `configuration-loader.md` | `config.json` in executable's directory (PC) | `get_base_dir().path_join("config.json")` for Windows/Linux; dedicated macOS branch walks up 3 levels |
| `configuration-loader.md` | In-editor fallback resolves to project root | `OS.has_feature("editor")` → `ProjectSettings.globalize_path("res://config.json")` |
| `configuration-loader.md` | Template generated on first run (CONFIG_MISSING) | Template write uses `FileAccess.store_*` with `bool` return check |
| `configuration-loader.md` | Getter safety before `config_loaded` | Test-mode fallback returns `TEST_DEFAULTS` without entering CONFIG_MISSING; getters always return safe types |
| `configuration-loader.md` | `FileAccess.store_*` returns `bool` in 4.4+ | Explicitly required: all write calls check return value; log `push_warning()` on `false` |
| `audio-manager.md` | "Settings persist to user://settings.json" | ConfigLoader owns `user://settings.json`; AudioManager calls `set_setting()` / `get_setting()` via signal chain |

## Performance Implications

- **CPU**: File reads once at boot. JSON parsing of a small config file (<2 KB) is negligible.
- **Memory**: Parsed config dict + settings dict held for application lifetime. <10 KB.
- **Load Time**: Synchronous file reads add <5 ms on all target platforms. Acceptable for a developer tool.
- **Network**: None.

## Migration Plan

N/A — establishes pattern before first implementation.

## Validation Criteria

- GUT: `test_config_path_editor()` — path resolves to project root via `globalize_path()`
- GUT: `test_config_path_macos()` — path escapes `.app` bundle (mock `has_feature("macos")`)
- GUT: `test_config_path_windows_linux()` — path resolves to `get_base_dir()` (mock non-editor, non-web, non-macos)
- GUT: `test_settings_roundtrip()` — `set_setting("k", 42)` → `get_setting("k")` == 42; `user://settings.json` created with correct content
- GUT: `test_schema_version_mismatch()` — config.json with `schema_version: 99` → CONFIG_INVALID
- GUT: `test_schema_version_absent()` — config.json without `schema_version` → loads normally
- GUT: `test_test_mode_fallback()` — editor + no config.json → `config_loaded` fires, `get_agents()` == `[]`, state ≠ CONFIG_MISSING
- GUT: `test_fileaccess_null_guard()` — mock `FileAccess.open()` returning `null` → CONFIG_MISSING without null method call crash
- Manual: macOS export — `config.json` beside `.app` (not inside) → reads correctly
- Manual: web export — change setting, reload page → setting persists (IndexedDB working)

## Related Decisions

- ADR-0003: Autoload Scene Composition — establishes ConfigLoader as an Autoload (prerequisite)
- ADR-001: Data Bridge Transport — consumes `get_agents()`, `get_poll_interval()`, `is_mock()`
- ADR-008: Mock Mode Strategy — uses `is_mock()` to swap the DataBridge polling driver
- ADR-014: Test Framework + CI — depends on test-mode fallback to boot GUT without infrastructure
