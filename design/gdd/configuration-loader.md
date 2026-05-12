# Configuration Loader

> **Status**: Designed — pending /design-review
> **Author**: Thomas + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: Foundational — enables "Alive by Default" (Data Bridge) and "Earn Each Room" (Room System)

> **TL;DR (Claude: read this, skip the full doc unless you need detail)**
> Autoload singleton. Reads `config.json` from executable directory at startup. Parses agent list (id, display_name, endpoint_url required; auth_token, room_slot optional), poll_interval_sec (default 5.0), protocol (default "http_poll"). Six terminal states: UNINITIALIZED → LOADING → READY or CONFIG_MISSING/CONFIG_MALFORMED/CONFIG_INVALID. On first run: generates template + shows error screen. Public API: `get_agents()`, `get_agent(id)`, `get_poll_interval()`, `get_protocol()`, `get_state()`. Max 12 agents. 28 acceptance criteria.

## Overview

The Configuration Loader reads an external configuration file at application startup,
validates its structure, and makes the parsed data available as an application-wide
singleton. It is the first system to initialize and the only system that requires the
developer to act outside the application — they edit the config file in a text editor,
then the loader reads it when the tool launches.

The loader provides two classes of data to downstream systems:

- **Integration data** (consumed by Data Bridge): one or more AI agent endpoint URLs,
  authentication credentials, polling interval, and connection protocol (HTTP poll or
  WebSocket).
- **Layout data** (consumed by Room System): the agent registry — which agents exist,
  their display names, and their assigned room slots.

The tool cannot run without a valid configuration file. If the file is missing, empty,
or structurally invalid, the loader enters an explicit error state that the application
can surface to the developer before any bunker rendering begins. A missing config is
not a crash — it is a known, handled state with clear guidance.

## Player Fantasy

The Configuration Loader is pure infrastructure — the developer never opens a settings
screen, never interacts with it directly, never watches it run. They feel its effect in
a single moment: the first frame after launch, when the bunker resolves on screen already
knowing who the developer is. The team is theirs. The rooms are theirs. The agents have
real names. The tool knew them before they asked.

The fantasy is *personalized presence* — the quiet authority of a system that has already
read the manifest of the developer's operation before a single pixel is drawn. This serves
Pillar 1 (Alive by Default) by ensuring the interface is never empty or generic on launch,
and Pillar 4 (Commander Always Home) by ensuring the developer's actual team is present
and current from frame one.

**Boundary note**: The loader's contribution to this fantasy is the *data* — it knows the
names, endpoints, and room assignments. The visual expression of "this is my team" belongs
to the Room System and Agent Character Controller. The loader is the part that happens
before the room lights on.

Success looks like the developer recognizing their agent team the moment the tool opens.
Failure looks like a configuration prompt, a missing agent, or a generic "Agent 1"
placeholder where a real name should be.

## Detailed Design

### Core Rules

1. **Loading occurs once, at application startup.** The Autoload singleton initializes
   before any scene loads. There is no hot-reload in MVP; the tool must be restarted to
   apply config changes. A manual F5 reload trigger is planned for V1.

2. **The config file is `config.json` in the executable's directory.** In exported
   builds, this is the folder containing the `.exe`. During development (in-editor), a
   fallback resolves it to the project root. The path is hardcoded — there is no
   path-to-config configuration.

3. **If no config file is found, the loader generates a template and enters
   `CONFIG_MISSING` state.** The template is written to the config path with placeholder
   values and field annotations. The application displays a pre-bunker error screen (not
   a crash) showing the exact file path and instructions. The tool stays in this state
   until the developer edits the file and restarts. The template is written once only —
   it is never overwritten if it already exists.

4. **If the file exists but cannot be parsed as valid JSON, the loader enters
   `CONFIG_MALFORMED` state.** The entire file is rejected atomically — no partial data
   is extracted. The error screen instructs the developer to check for missing commas,
   unclosed braces, or invalid values.

5. **If the file is valid JSON but required fields are missing or invalid, the loader
   enters `CONFIG_INVALID` state.** Validation collects all errors before reporting —
   the developer sees every problem in one launch, not one per relaunch. The error screen
   names every missing or invalid field.

6. **Optional fields with defined defaults do not cause errors.** Defaults are applied
   silently and logged; `get_applied_defaults()` returns the list for diagnostics.

7. **Agents without an explicit `room_slot` are auto-assigned slots sequentially.**
   Explicit slots are honored first; remaining agents fill unoccupied slots in the order
   they appear in the config. Slot conflicts (two agents claiming the same slot number)
   are a `CONFIG_INVALID` error.

8. **The loader's data is read-only after initialization.** All public methods are
   getters. There is no public setter API. Callers must not cache and mutate the returned
   arrays — call getters each time fresh data is needed.

9. **If `config_loaded` was emitted, all returned data is valid and complete.** Callers
   do not need to re-validate data from this system. The contract: if the signal fired,
   trust the data.

---

### States and Transitions

| State | Description | Enters When | Exits To |
|---|---|---|---|
| `UNINITIALIZED` | Autoload constructed, `_ready()` not yet called | Object construction | `LOADING` |
| `LOADING` | Reading file, parsing JSON, validating fields | `_ready()` begins | `CONFIG_MISSING`, `CONFIG_MALFORMED`, `CONFIG_INVALID`, or `READY` |
| `CONFIG_MISSING` | No config file found; template was generated | File absent at config path | Terminal — emits `config_load_failed` |
| `CONFIG_MALFORMED` | File found but JSON parse returned null | `JSON.parse_string()` fails | Terminal — emits `config_load_failed` |
| `CONFIG_INVALID` | JSON valid but required fields missing or in conflict | Field validation finds errors | Terminal — emits `config_load_failed` |
| `READY` | All data validated and available | Validation passes | Terminal — emits `config_loaded` |

All error states are terminal. The application must be restarted to retry.

---

### Interactions with Other Systems

**Signals (emitted once, at `_ready()` completion):**

| Signal | Arguments | When |
|---|---|---|
| `config_loaded` | — | Validation passed; data is available |
| `config_load_failed` | `state: String, message: String` | Any error state reached |

**Public getter API:**

| Method | Return Type | Consumers |
|---|---|---|
| `get_agents() -> Array[Dictionary]` | All agent dicts | Data Bridge, Room System, HUD |
| `get_agent(id: String) -> Dictionary` | One agent dict, or `{}` if not found | Data Bridge, TCB |
| `get_poll_interval() -> float` | Float | Data Bridge |
| `get_protocol() -> String` | `"http_poll"` or `"websocket"` | Data Bridge |
| `get_applied_defaults() -> Array[String]` | List of defaulted field names | Main Scene Bootstrap (diagnostics) |
| `get_setting(key: String, default: Variant = null) -> Variant` | Looked-up value or default | ASM (entities.yaml tuning + persisted stats), Audio Manager (settings), future systems |
| `set_setting(key: String, value: Variant) -> void` | — | ASM (persisted stats writes), Audio Manager (mute/volume preferences) |
| `is_mock() -> bool` | True iff config.json's `mock: true` OR ADR-0004 web override fired | Data Bridge, mock-aware systems |
| `is_web_mock_forced() -> bool` | True iff the ADR-0004 web override applied | HUD demo-mode badge (post-MVP) |

**Arbitrary-key access (added 2026-05-12 per C-9 of cross-GDD review)**

`get_setting` / `set_setting` provide an arbitrary-key key/value surface backed by two files:
- **Read precedence (top to bottom)**: `user://settings.json` ← `design/registry/entities.yaml` ← `default` argument
- **Writes always go to `user://settings.json`.** `entities.yaml` is read-only (design-time authoring; ships with the build).
- Keys are dotted strings, e.g. `"asm.completed_decay_sec"`, `"asm_stats_claude_dev"`, `"audio.master_volume_db"`.
- `setting_changed(key: String, value: Variant)` signal fires on every successful `set_setting` (per ADR-0002).
- Schema versioning + corrupt-blob handling: on read, if the value at `key` is incompatible with the consumer's expected schema, the consumer is responsible for falling back to default + `push_warning` (ASM does this for corrupt stats blobs per its §5 E-14).

**File layout** for arbitrary-key access:
```
user://settings.json    ← writable, gitignored, per-user runtime state
                        (audio settings, hud_visible, asm_stats_<id>, etc.)

res://design/registry/entities.yaml
                        ← read-only, shipped with build, design-time tuning
                        (asm.completed_decay_sec, audio bus volumes, etc.)
```

This consolidation keeps ConfigurationLoader as the single autoload responsible for persistent configuration — preserving ADR-0003's two-autoload limit (no new `EntityRegistry` needed). Added per `design/reviews/gdd-cross-review-2026-05-12.md` C-9 with user-selected resolution "Extend ConfigLoader."

**Config file schema — global fields:**

| Field | Type | Required | Default | Range | Description |
|---|---|---|---|---|---|
| `agents` | array | **Yes** | — | 1–12 entries | List of agent definition objects |
| `poll_interval_sec` | float | No | `5.0` | 1.0–60.0 | Data Bridge polling interval in seconds |
| `protocol` | string | No | `"http_poll"` | `"http_poll"` \| `"websocket"` | Connection protocol for Data Bridge |

**Config file schema — per-agent fields (each object in `agents` array):**

| Field | Type | Required | Default | Valid Range | Description |
|---|---|---|---|---|---|
| `id` | string | **Yes** | — | Alphanumeric + `_`, 1–32 chars, unique | Machine identifier |
| `display_name` | string | **Yes** | — | 1–48 chars | Name shown in bunker HUD |
| `endpoint_url` | string | **Yes** | — | Valid URL | API endpoint for Data Bridge |
| `auth_token` | string | No | `""` | Any string | Bearer token; `""` = unauthenticated. Stored in plaintext — explicitly accepted for a personal tool on a private machine. |
| `agent_type` | string | No | `"default"` | Alphanumeric + `_`, 1–32 chars | Lookup key for type-specific assets (e.g. completion sound via `AgentSoundRegistry` in Task Completion Beat). Falls back to `"default"` if absent. |
| `room_slot` | int | No | Auto-assigned | 0–11 | Room slot index in Room System |

**Minimal valid config (5-minute setup):**

```json
{
  "agents": [
    {
      "id": "researcher",
      "display_name": "Researcher",
      "endpoint_url": "http://localhost:8080/status"
    }
  ]
}
```

**Implementation notes for programmer** (Godot 4.6 specifics from feasibility check):
- `FileAccess.open()` returns `null` on failure — call `FileAccess.get_open_error()` immediately after for the `Error` enum value
- `store_*` methods return `bool` in Godot 4.6 (changed from `void` in 4.4) — always check the return value when writing the template
- In-editor path: `OS.has_feature("editor")` → use `ProjectSettings.globalize_path("res://config.json")` instead of the executable-relative path
- `OS.shell_open(dir_path)` opens the config directory in the OS file manager on first-run template generation

## Formulas

This system contains no mathematical formulas. The Configuration Loader reads, validates,
and distributes data — it does not compute values or transform inputs into outputs
mathematically.

The auto-slot assignment algorithm (Core Rule 7) is a sequential gap-fill: iterate agent
entries in order, assign each unslotted agent to the lowest unoccupied slot index (0–11).
This is an ordering rule, not a formula requiring variables, ranges, or example
calculations.

Any numeric values produced by this system (`poll_interval_sec`, `room_slot`) are
directly read from the config file or defaulted from the constants defined in Core Rule 6.
They are not derived computations.

## Edge Cases

### File Access

- **If the config file does not exist**: loader enters `CONFIG_MISSING`, generates a
  template, and shows the pre-bunker error screen. The template is never overwritten if
  already present from a prior first-run.
- **If the config file exists but cannot be read** (OS permission denied): loader enters
  `CONFIG_MISSING`. `CONFIG_MISSING` covers both "absent" and "inaccessible." Error
  screen includes the OS error code.
- **If the template itself cannot be written** (write permission denied): loader still
  enters `CONFIG_MISSING` and shows the error screen, with an additional note that
  template generation failed. The developer must create the file manually.
- **If the file contains only whitespace** (spaces, newlines, tabs): treated identically
  to an empty file — `CONFIG_MALFORMED`.
- **If the file begins with a UTF-8 BOM** (common from Windows text editors):
  `CONFIG_MALFORMED`. Error screen suggests saving as BOM-free UTF-8.
- **If the file is not UTF-8 encoded**: `JSON.parse_string()` will fail —
  `CONFIG_MALFORMED`.

### Parse Errors

- **If the file cannot be parsed as valid JSON**: `CONFIG_MALFORMED`. No partial data is
  extracted.
- **If the JSON root is an array instead of an object** (e.g., `[{...}]`): the JSON
  parsed successfully, so this is `CONFIG_INVALID` — not `CONFIG_MALFORMED`. Error:
  "Root must be a JSON object."

### Schema Type Errors

- **If `agents` is present but not an array** (e.g., `"agents": {}`): `CONFIG_INVALID`.
  Error names the field and expected type.
- **If an entry in the `agents` array is not a dictionary** (e.g., `"agents": [1, 2]`):
  `CONFIG_INVALID`. Error names the array index of the malformed entry.
- **If `auth_token` is JSON `null`**: treated as `""` (unauthenticated). No error.
- **If `auth_token` is a non-string type** (integer, boolean, object): `CONFIG_INVALID`.
  Type coercion is not applied.
- **If `protocol` contains an unrecognized string** (not `"http_poll"` or
  `"websocket"`): `CONFIG_INVALID`. Error lists valid options.
- **If `room_slot` is a whole-number float** (e.g., `0.0`, `3.0`): cast to int and
  accepted. No error.
- **If `room_slot` is a non-whole float** (e.g., `1.5`): `CONFIG_INVALID`. `1.5` is
  not cast to `1`.

### Schema Value Errors

- **If the `agents` array is empty**: `CONFIG_INVALID`. Error: "agents must contain at
  least 1 entry."
- **If the `agents` array has more than 12 entries**: `CONFIG_INVALID`. Error names the
  excess count.
- **If two agents share the same `id`**: `CONFIG_INVALID`. Error names both agent ids
  and their array indices (e.g., "id 'researcher' appears at index 0 and index 3").
- **If two agents claim the same explicit `room_slot`**: `CONFIG_INVALID`. Error names
  the conflicting agents and the slot number.
- **If all 12 slots are taken by explicit assignments but additional agents have no
  `room_slot`**: `CONFIG_INVALID`. Error names the overflow agents that could not be
  placed.
- **If `room_slot` is outside 0–11**: `CONFIG_INVALID`.
- **If `poll_interval_sec` is outside 1.0–60.0**: `CONFIG_INVALID`. Bounds are
  inclusive — `1.0` and `60.0` are valid.
- **If `display_name` is an empty string**: `CONFIG_INVALID`.
- **If `endpoint_url` is not a valid URL**: `CONFIG_INVALID`.

### Validation Behavior

- **If multiple fields are invalid**: validation is exhaustive — all errors are collected
  before reporting, at both the file level (all agents checked) and the agent level (all
  fields within one agent checked). The developer sees every problem in one launch.
- **Auto-slot assignment runs in JSON parse order** (array index order). Implementation
  must not sort agents before gap-filling — ordering must be stable and predictable.

### Runtime Getter Safety

- **If a getter is called before `config_loaded` fires**: returns safe empty defaults —
  `get_agents() → []`, `get_agent(id) → {}`, `get_poll_interval() → 5.0`,
  `get_protocol() → "http_poll"`. No crash, no null return.
- **If a system misses the `config_loaded` signal** (connected after `_ready()`
  completed): use `get_state() -> String` synchronously. If `get_state() == "READY"`,
  data is available immediately without needing the signal.

### Developer Restarts Without Editing the Template

- The loader reads the template, validates its structure, and enters `READY` (placeholder
  URLs are syntactically valid). The Data Bridge will then fail to connect to the
  placeholder endpoint. This is the Data Bridge's responsibility — the config loader has
  done its job correctly. This is expected behavior, not a bug.

## Dependencies

### Upstream Dependencies (systems this GDD depends on)

**None.** The Configuration Loader is a Foundation-layer system with zero dependencies
on other game systems. It depends only on the operating system's file API and Godot's
built-in `JSON` class.

---

### Downstream Dependents (systems that depend on this GDD)

**Data Bridge** — *Hard dependency.*
The Data Bridge cannot initialize without valid config. It calls `get_agents()` to build
its connection list, `get_poll_interval()` for its polling timer, and `get_protocol()` to
select HTTP or WebSocket mode. It must connect to `config_loaded` before calling any
getter. If `config_load_failed` fires, the Data Bridge must propagate the failure to the
bootstrap system.
*Bidirectionality: Data Bridge GDD must list Configuration Loader as a hard upstream
dependency.*

**Room System** — *Hard dependency.*
The Room System cannot build its room registry without the agent list. It calls
`get_agents()` to extract `id`, `display_name`, and `room_slot` for each agent. It must
connect to `config_loaded` before querying.
*Bidirectionality: Room System GDD must list Configuration Loader as a hard upstream
dependency.*

**Main Scene Bootstrap** — *Soft dependency.*
The Bootstrap listens to both `config_loaded` and `config_load_failed` to decide whether
to proceed to bunker rendering or surface the pre-bunker error screen. It calls
`get_applied_defaults()` for diagnostic display. The Bootstrap can operate without a
`READY` state — its error-screen mode is specifically designed for config failures.
*Bidirectionality: Main Scene Bootstrap (produced by `/create-architecture`) must
reference this GDD as a dependency.*

## Tuning Knobs

| Knob | Current Value | Safe Range | What Breaks If Too High | What Breaks If Too Low |
|---|---|---|---|---|
| `DEFAULT_POLL_INTERVAL_SEC` | `5.0` sec | 1.0–60.0 | Agent status feels stale; updates lag real task durations | API rate limits exceeded; tool hammers endpoints constantly |
| `MIN_POLL_INTERVAL_SEC` | `1.0` sec | 0.5–5.0 | Shifts the floor up; no behavioral impact | Allows configs that overwhelm agent APIs |
| `MAX_POLL_INTERVAL_SEC` | `60.0` sec | 30.0–300.0 | Allows configs where status feels frozen | Shifts the ceiling down; no behavioral impact |
| `MAX_AGENTS` | `12` | 1–24 | Room System must support more slots; art budget scales with count | Power users with more agents are blocked |
| `MAX_DISPLAY_NAME_LENGTH` | `48` chars | 16–96 | HUD may overflow or require truncation at render width | Meaningful agent names get cut short |
| `MAX_AGENT_ID_LENGTH` | `32` chars | 8–64 | Longer IDs are unwieldy in logs and debug output | Short IDs increase collision probability |

**Knob interactions**: `DEFAULT_POLL_INTERVAL_SEC` must always fall within
`[MIN_POLL_INTERVAL_SEC, MAX_POLL_INTERVAL_SEC]`. Changing either bound without updating
the default may produce a configuration that fails its own validation at launch.

**Note**: These are code-level constants in the Configuration Loader Autoload, not
exposed in `config.json`. The developer-editable equivalent is `poll_interval_sec` in the
config file, which is bounded and defaulted by these constants.

## Visual/Audio Requirements

Not applicable. The Configuration Loader is a data-reading infrastructure system with
no visual or audio output. Its only user-facing surface is the pre-bunker error screen,
which is specified in UI Requirements above.

## UI Requirements

The Configuration Loader drives one UI surface: the **pre-bunker error screen**,
displayed instead of the bunker when any error state is reached. This is the only
visual output this system owns.

- **Appears before any bunker scene renders.** The error screen is the first thing the
  developer sees — no flash of bunker content before the error display.
- **Displays the config file path.** Shows the full resolved path to `config.json`
  (e.g., `C:\Users\...\config.json` on Windows) so the developer can open it directly.
- **Displays the error state.** Human-readable label: "Configuration missing",
  "Configuration malformed", or "Configuration invalid."
- **Displays the error message.** The `message` string from `config_load_failed` is
  shown verbatim. For `CONFIG_INVALID`, this is the list of missing or invalid fields.
- **For `CONFIG_MISSING`: shows the template note.** If a template was generated, adds:
  "A template has been written to the path above. Edit it with your agent details and
  restart."
- **Passive display — no interactive elements required.** The developer closes the tool,
  edits the config, and relaunches. No retry button, no in-app editor. Informational only.
- **Styled consistently with the bunker aesthetic.** Uses the same pixel art palette and
  bitmap font as the rest of the tool. The error screen is not a generic OS dialog.

## Acceptance Criteria

All criteria use **GIVEN / WHEN / THEN** format. Criteria marked `[unit test]` require
a unit test; others can be verified manually or via integration test.

### Happy Path

1. **GIVEN** a valid `config.json` with 1 agent (required fields only), **WHEN** the
   tool starts, **THEN** `config_loaded` fires, `get_state()` returns `"READY"`, and
   `get_agents()` returns an Array of 1 Dictionary with keys `id`, `display_name`,
   `endpoint_url`, `auth_token`, `agent_type`, `room_slot`.

2. **GIVEN** a valid config with no `poll_interval_sec` or `protocol` fields, **WHEN**
   the tool starts, **THEN** `get_poll_interval()` returns `5.0`, `get_protocol()`
   returns `"http_poll"`, and `get_applied_defaults()` returns an Array that includes
   both `"poll_interval_sec"` and `"protocol"`.

3. **GIVEN** 3 agents with no `room_slot` fields, **WHEN** the tool starts, **THEN** the
   agents in `get_agents()` have `room_slot` values `0`, `1`, `2` respectively, in
   array order.

4. **GIVEN** a valid config with `protocol: "websocket"`, **WHEN** the tool starts,
   **THEN** `get_protocol()` returns `"websocket"`.

### File Access Errors

5. **GIVEN** no `config.json` exists at the config path, **WHEN** the tool starts,
   **THEN** a template file is written to the config path AND the pre-bunker error screen
   is visible AND the main bunker scene is not rendered AND `config_load_failed` fires
   with `state == "CONFIG_MISSING"`.

6. **GIVEN** the template was generated on first run and the developer restarts without
   editing it, **WHEN** the tool starts again, **THEN** the existing template file is not
   overwritten (its content is unchanged after restart).

7. **GIVEN** `config.json` exists but OS read permissions are denied, **WHEN** the tool
   starts, **THEN** `config_load_failed` fires with `state == "CONFIG_MISSING"` AND the
   error screen includes the OS error code.

### Parse Errors

8. **GIVEN** `config.json` contains invalid JSON (e.g., a missing closing brace),
   **WHEN** the tool starts, **THEN** `config_load_failed` fires with
   `state == "CONFIG_MALFORMED"` AND the pre-bunker error screen is visible AND the
   bunker does not render.

9. **GIVEN** `config.json` is a UTF-8 file with a leading BOM (`EF BB BF`), **WHEN**
   the tool starts, **THEN** `config_load_failed` fires with `state == "CONFIG_MALFORMED"`
   AND the error `message` string contains `"BOM"` or `"UTF-8"`.

10. **GIVEN** `config.json` contains a valid JSON array as the root value (e.g.,
    `[{...}]`), **WHEN** the tool starts, **THEN** `config_load_failed` fires with
    `state == "CONFIG_INVALID"` (not `"CONFIG_MALFORMED"`).

### Schema Validation — Exhaustive Collection

11. **GIVEN** one agent entry is missing both `display_name` and `endpoint_url`,
    **WHEN** the tool starts, **THEN** `config_load_failed` fires with
    `state == "CONFIG_INVALID"` AND the `message` argument contains both field names
    in a single string.

12. **GIVEN** the `agents` array is empty (`[]`), **WHEN** the tool starts, **THEN**
    `CONFIG_INVALID` AND message references `"agents"`.

13. **GIVEN** the `agents` field is a JSON object (e.g., `"agents": {}`), **WHEN** the
    tool starts, **THEN** `CONFIG_INVALID`.

14. **GIVEN** the `agents` array contains a non-dictionary entry (e.g.,
    `"agents": [1, 2]`), **WHEN** the tool starts, **THEN** `CONFIG_INVALID` AND message
    identifies the array index of the malformed entry.

15. **GIVEN** two agents share the same `id`, **WHEN** the tool starts, **THEN**
    `CONFIG_INVALID` AND message names both agent ids and their array indices.

16. **GIVEN** two agents declare the same explicit `room_slot` value, **WHEN** the tool
    starts, **THEN** `CONFIG_INVALID` AND message names both agents and the conflicting
    slot number.

17. **GIVEN** `poll_interval_sec: 0.5` (below minimum), **WHEN** the tool starts,
    **THEN** `CONFIG_INVALID`. **GIVEN** `poll_interval_sec: 1.0` (at minimum bound),
    **THEN** `READY`.

18. **GIVEN** `room_slot: 1.5` (non-whole float), **WHEN** the tool starts, **THEN**
    `CONFIG_INVALID`. **GIVEN** `room_slot: 3.0` (whole float), **WHEN** the tool starts,
    **THEN** `READY` with `room_slot` stored as integer `3`.

19. **GIVEN** `auth_token: 42` (integer, not string), **WHEN** the tool starts, **THEN**
    `CONFIG_INVALID`.

20. **GIVEN** `protocol: "grpc"` (unrecognized value), **WHEN** the tool starts, **THEN**
    `CONFIG_INVALID`.

### Runtime and Signal Contracts

21. **GIVEN** the loader is in `READY` state, **WHEN** `get_state()` is called, **THEN**
    returns `"READY"`.

22. **GIVEN** the loader is in any error state, **WHEN** `get_state()` is called, **THEN**
    returns the matching error state string (`"CONFIG_MISSING"`, `"CONFIG_MALFORMED"`, or
    `"CONFIG_INVALID"`).

23. **GIVEN** `config_load_failed` fires, **THEN** the `state` argument is one of
    `"CONFIG_MISSING"`, `"CONFIG_MALFORMED"`, `"CONFIG_INVALID"` AND `message` is a
    non-empty String.

24. **GIVEN** `get_state()` returns any value other than `"READY"`, **WHEN** `get_agents()`
    is called, **THEN** returns `[]` without crashing. `get_poll_interval()` returns `5.0`.
    `get_protocol()` returns `"http_poll"`. `[unit test]`

25. **GIVEN** `config_loaded` has fired, **WHEN** the caller appends an element to the
    Array returned by `get_agents()` and calls `get_agents()` again, **THEN** the second
    call returns the original unmodified array. `[unit test]`

26. **GIVEN** a valid config with `poll_interval_sec: 30.0`, **WHEN** `get_poll_interval()`
    is called a second time without restarting, **THEN** returns `30.0` (same result — no
    re-read). `[unit test]`

27. **GIVEN** `get_agent("nonexistent_id")` is called in `READY` state, **THEN** returns
    an empty Dictionary `{}`.

### Path Resolution `[unit test]`

28. **GIVEN** the tool is running in the Godot editor (`OS.has_feature("editor")` is
    true), **WHEN** the loader resolves the config path, **THEN** the path points to the
    project root, not the Godot executable directory.

## Open Questions

*None captured at time of authoring. Open questions can be added here as they arise
during implementation or review.*
