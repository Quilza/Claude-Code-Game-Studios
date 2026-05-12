# Tests — The Situation Room

Per **ADR-0014: Test Framework + CI Pipeline** (Accepted 2026-05-11).

## Framework: GUT 9.x

GUT (Godot Unit Testing) is the only approved test addon for this project.

## Directory Layout

```
tests/
├── unit/                  # Unit tests — isolated, deterministic, fast
│   └── example_test.gd    # Placeholder smoke test
├── integration/           # Integration tests — multi-system interactions
└── helpers/               # (Future) shared test utilities, mocks, factories
```

## Running tests locally

After installing GUT to `addons/gut/`:

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

## CI

`.github/workflows/tests.yml` runs this command on every push to `main` and every PR.
Failing tests **block merge** (CI is a hard gate per ADR-0014).

## Install GUT (one-time)

GUT is not currently checked into the repo. To install:

1. Download GUT 9.x from https://github.com/bitwes/Gut/releases (Godot 4 compatible)
2. Extract `addons/gut/` to the project root
3. Open the project in Godot editor → `Project → Project Settings → Plugins → enable GUT`
4. Commit the activated plugin entry in `project.godot` (NOT the `addons/gut/` source if you prefer a submodule approach)

Alternative: add GUT as a git submodule at `addons/gut/` for clean version pinning.

## Naming conventions (per coding-standards.md)

- Files: `test_[system]_[feature].gd`
- Functions: `test_[scenario]_[expected]()`
- Determinism: no `randf()`, no `OS.get_ticks_msec()` in assertions
- Isolation: each test sets up + tears down its own state
- No hardcoded magic data (use constant files or factory functions)

## Test types (per coding-standards.md)

| Type | Required for | Gate |
|---|---|---|
| Unit | Logic stories (formulas, AI, state machines) | BLOCKING |
| Integration | Multi-system stories | BLOCKING |
| Visual evidence | Animation, VFX, feel | ADVISORY |
| Walkthrough doc | UI menus, HUD | ADVISORY |
| Smoke pass | Config/data balance tuning | ADVISORY |
