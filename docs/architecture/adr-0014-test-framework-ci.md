# ADR-0014: Test Framework + CI Pipeline

## Status
Accepted (2026-05-11)

## Date
2026-05-11

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.2 |
| **Domain** | Core / Tooling |
| **Knowledge Risk** | LOW — GUT 9.x (Godot 4 compatible) and GitHub Actions are stable; no engine-version-specific concerns |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `.claude/docs/coding-standards.md`, `.claude/docs/technical-preferences.md` |
| **Post-Cutoff APIs Used** | None — GUT headless runner and GitHub Actions workflow use no post-cutoff APIs |
| **Verification Required** | VERIFY: GUT addon is activated under `[editor_plugins]` in `project.godot` before first CI run — plugin must be enabled in the project file, not just present in the filesystem (headless CI silently skips tests if the plugin is not activated). |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — this ADR establishes foundational test infrastructure; no prior ADR required |
| **Enables** | ADR-0002 (Configuration Loading + Persistence) — GUT tests defined in ADR-0002's Validation Criteria require this framework; ADR-0005 (task_completed Signal Source) — GUT tests defined in its Validation Criteria; all GDDs that specify GUT test cases in their Acceptance Criteria |
| **Blocks** | No implementation test can be written until the test runner is installed; `/test-setup` scaffolding depends on this ADR being Accepted |
| **Ordering Note** | Write before any `/test-setup` or test scaffolding runs. |

## Context

### Problem Statement

The project has no configured test framework, no test directory structure, and no CI pipeline. The Pre-Production gate check requires:

- `tests/unit/` and `tests/integration/` directories to exist
- A CI workflow at `.github/workflows/tests.yml` (or equivalent)
- At least one example test file to confirm the framework is functional

Additionally, ADR-0002 and ADR-0005 each specify GUT test cases in their Validation Criteria. Those tests cannot be written or run without a configured framework.

The project has already selected GUT (Godot Unit Testing) as its test framework in `technical-preferences.md` → Allowed Libraries. This ADR formalizes that selection, establishes the runner command, defines the directory structure, and specifies the CI workflow.

**Note on coding-standards.md**: The existing CI command entry referenced `gdunit4_runner.gd` — a GDUnit4 runner format inconsistent with the GUT selection. That entry has been corrected to the GUT runner in the same commit as this ADR.

### Constraints

- **GDScript-only project** — no C# / .NET; test framework must not require .NET SDK
- **Godot 4.x required** — test framework must run against Godot 4.6.2 headlessly on Linux CI runners
- **No runtime allocation** — test suite must not spin up Autoloads that require a real `config.json` (ConfigLoader's test-mode fallback, established by ADR-0002, handles this)
- **CI blocks merges** — failing tests must prevent merging to `main`; CI is not advisory
- **Headless runner** — no display server available in CI environment
- **.github/ already exists** — issue templates and PR template are present; workflows subdirectory will be added

### Requirements

- Install GUT as a Godot addon (`addons/gut/`)
- Test directories: `tests/unit/` for unit tests, `tests/integration/` for integration tests
- Minimum one placeholder test file to validate the runner works
- GitHub Actions workflow runs on push to `main` and all pull requests
- Failing tests block merge — CI is a hard gate
- Test naming convention matches coding-standards.md: files `test_[system]_[feature].gd`, functions `test_[scenario]_[expected]()`
- GUT plugin must be activated in `project.godot` under `[editor_plugins]`

## Decision

### Test Framework: GUT 9.x (Godot Unit Testing)

GUT is installed as a Godot addon at `addons/gut/`. It is the only approved test addon for this project.

**GUT is NOT a production dependency** — the `addons/gut/` directory ships with the project for CI but must be excluded from export presets. Add `addons/gut/` to the export preset's exclude list to prevent the test framework from being bundled into shipped builds.

### Headless Runner Command

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

| Flag | Purpose |
|------|---------|
| `--headless` | No display server — required for CI (Linux runners have no GPU/display) |
| `-s res://addons/gut/gut_cmdln.gd` | GUT 9.x entry point for command-line execution |
| `-gdir=res://tests` | Scan `tests/` recursively for test files matching GUT's naming convention |
| `-gexit` | Exit Godot after the test run completes (required for CI; without this, Godot stays open) |

Optional flags for finer control (not required for CI):
- `-gprefix=test_` — only run files with this prefix
- `-glog=1` — verbose output level (0=minimal, 3=full)

### Directory Structure

```
tests/
├── unit/                    # Unit tests — single-system, no I/O, no scene tree
│   ├── configuration_loader/
│   │   └── test_config_path_resolution.gd
│   ├── agent_state_machine/
│   └── ...
├── integration/             # Integration tests — multi-system or scene-tree-required
│   └── ...
└── gut_config.json          # GUT configuration file (optional but recommended)
```

**Test file naming**: `test_[system]_[feature].gd`
**Test function naming**: `func test_[scenario]_[expected]() -> void:`

Example:
```gdscript
# tests/unit/configuration_loader/test_config_path_resolution.gd
extends GutTest

func test_editor_path_resolves_to_project_root() -> void:
    # Given: running in editor context
    # When: _get_config_path() is called
    # Then: path starts with the project root (not inside .app)
    pass  # placeholder — implementation goes here
```

### GUT Plugin Activation (Critical)

GUT must be activated in `project.godot` under `[editor_plugins]`:

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

**If this section is absent or the plugin is not listed, Godot's headless runner will silently skip all tests with no error.** This is the most common GUT CI failure mode. Verify by checking `project.godot` after installation.

### GitHub Actions CI Workflow

File: `.github/workflows/tests.yml`

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  gut-tests:
    name: GUT Test Suite
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Godot 4.6.2
        uses: chickensoft-games/setup-godot@v1
        with:
          version: 4.6.2
          use-dotnet: false       # GDScript-only project — no .NET SDK needed

      - name: Import Godot project
        run: godot --headless --import || true
        # The import step generates .godot/ cache. The `|| true` prevents failure
        # if import produces non-zero exit on a headless run with no display.

      - name: Run GUT tests
        run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

**Merge gate**: GitHub branch protection rules on `main` must require the `gut-tests` job to pass before merging. Configure this in the repository settings after the workflow is committed.

### `.gitignore` additions

```gitignore
# Godot import cache (generated per-machine)
.godot/

# GUT test results (generated at runtime, not committed)
tests/.gut_results/
```

### Architecture Diagram

```
Developer push / PR
        │
        ▼
GitHub Actions (.github/workflows/tests.yml)
        │
        ├─ actions/checkout@v4
        ├─ chickensoft-games/setup-godot@v1 (installs Godot 4.6.2)
        ├─ godot --headless --import  (builds .godot/ cache)
        └─ godot --headless -s res://addons/gut/gut_cmdln.gd ...
                │
                ├─ tests/unit/**/*.gd      (unit tests)
                └─ tests/integration/**/*.gd  (integration tests)
                         │
                         ▼
                    PASS → merge allowed
                    FAIL → merge blocked
```

## Alternatives Considered

### Alternative B: GDUnit4

- **Description**: GDUnit4 is an alternative Godot test framework with a different runner (`gdunit4_runner.gd`) and a richer assertion API.
- **Pros**: More assertion types, built-in test report HTML generation.
- **Cons**: Not in the project's Allowed Libraries list; switching would require updating `technical-preferences.md` and all GDD Acceptance Criteria that reference GUT by name.
- **Rejection Reason**: GUT is already selected in `technical-preferences.md`. GDUnit4's reference in the template `coding-standards.md` was a template artifact that has been corrected to GUT.

### Alternative C: No CI — manual test runs only

- **Description**: Tests are run locally by developers before committing; no automated CI.
- **Pros**: No GitHub Actions setup required; no runner costs.
- **Cons**: Pre-Production gate check requires CI to exist. Manual-only testing breaks down with multiple contributors. Forgotten test runs before push are a common failure mode.
- **Rejection Reason**: Gate check is a hard requirement. Even for a solo developer, CI catches issues on OS/environment differences between development machine and deployment targets.

### Alternative D: GitLab CI / other providers

- **Description**: Use GitLab CI (`.gitlab-ci.yml`) or CircleCI instead of GitHub Actions.
- **Pros**: Other providers have different pricing or feature models.
- **Cons**: `.github/` directory already exists (issue templates, PR template), indicating the project is hosted on GitHub. Switching CI providers would require migrating all existing GitHub-specific infrastructure.
- **Rejection Reason**: Project is on GitHub; GitHub Actions is the zero-friction choice.

## Consequences

### Positive

- Gate check passes for "CI workflow exists" and "test directories exist" items as soon as this ADR is implemented.
- All GDDs with Validation Criteria GUT test cases now have a target to write into.
- ConfigLoader's test-mode fallback (ADR-0002) is exercisable in CI without a real `config.json` — GUT boots ConfigLoader which detects `OS.has_feature("editor")` and returns `TEST_DEFAULTS`.
- Incorrect commits are caught before they reach `main`.

### Negative

- `addons/gut/` adds ~300 KB to the repository. Acceptable overhead.
- CI workflow adds ~2–3 minutes per push/PR for Godot download + import + test run. Acceptable for this project.
- GUT addon must be excluded from export presets manually — this is a one-time setup step.

### Risks

- **GUT plugin not activated** (HIGH likelihood if missed): headless runner silently skips all tests. Mitigation: the VERIFY item in Engine Compatibility; `/test-setup` scaffolding script should check `project.godot` for the plugin entry.
- **Import step fails in headless mode**: `godot --headless --import` may return non-zero on some Godot versions even when successful. The `|| true` in the workflow prevents a false CI failure from this step.
- **Test isolation failures**: unit tests that accidentally access the real scene tree or real file system will fail in CI (no config.json, no display). Mitigation: coding-standards.md already requires dependency injection over singletons. ConfigLoader's test-mode fallback handles the config.json case.
- **Godot 4.6 defaults D3D12 on Windows**: developers running GUT locally on Windows use D3D12; the Linux CI runner uses the default renderer. For a GDScript-logic test suite this has no practical effect — GUT unit tests do not exercise rendering.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `configuration-loader.md` | GUT tests: `test_config_path_editor()`, `test_settings_roundtrip()`, etc. (from ADR-0002 Validation Criteria) | These tests are written to `tests/unit/configuration_loader/` using the runner established here |
| `data-bridge.md` | GUT tests for mock mode, HTTPRequest lifecycle, backoff behavior | Written to `tests/unit/data_bridge/` and `tests/integration/data_bridge/` |
| All MVP GDDs | Acceptance Criteria that specify GUT tests | All GUT-specified ACs now have a target directory and runner to execute against |

## Performance Implications

- **CPU**: CI adds ~2–3 minutes per push. Not a development-cycle concern.
- **Memory**: `addons/gut/` ~300 KB. Negligible.
- **Load Time**: No impact on game runtime — GUT is excluded from exports.
- **Network**: GitHub Actions runner downloads Godot 4.6.2 on each run. Chickensoft's action caches the binary via GitHub Actions cache; subsequent runs are faster.

## Migration Plan

N/A — establishes from scratch. Implementation steps (for `/test-setup` to follow):

1. Install GUT 9.x: download from https://github.com/bitwes/Gut/releases and place in `addons/gut/`
2. Activate plugin: open project in Godot editor → Project → Project Settings → Plugins → GUT → Enable
3. Verify `project.godot` contains the `[editor_plugins]` entry for GUT
4. Create `tests/unit/` and `tests/integration/` directories with a `.gitkeep` placeholder
5. Write a placeholder smoke test to `tests/unit/test_smoke.gd` that verifies GUT runs
6. Create `.github/workflows/tests.yml` with the workflow defined in this ADR
7. Configure branch protection on `main` to require `gut-tests` to pass

## Validation Criteria

- CI: GitHub Actions workflow file exists at `.github/workflows/tests.yml`
- CI: Workflow runs on push to `main` and on PRs — verify by pushing a test commit
- CI: Workflow reaches the GUT run step without error
- Manual: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` returns exit code 0 when all tests pass and non-zero when a test fails
- Manual: A deliberately failing test (`assert_eq(1, 2)`) causes the CI job to fail and blocks merge
- File: `tests/unit/` exists and contains at least one `.gd` test file
- File: `tests/integration/` exists
- File: `project.godot` contains `[editor_plugins]` entry for GUT
- File: Export preset excludes `addons/gut/`

## Related Decisions

- ADR-0002: Configuration Loading + Persistence — defines 8 GUT test cases that target `tests/unit/configuration_loader/`
- ADR-0003: Autoload Scene Composition — defines 3 GUT validation tests requiring GUT to boot ConfigLoader and AudioManager
- ADR-0005: task_completed Signal Source — defines 6 GUT test cases targeting `tests/unit/agent_state_machine/`
