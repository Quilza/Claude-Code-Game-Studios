# Technical Preferences

## Engine & Language

- **Engine**: Godot 4.6.2
- **Language**: GDScript
- **Rendering**: Godot 2D Renderer (CanvasItem API)
- **Physics**: Jolt Physics (default in Godot 4.6)

## Input & Platform

- **Target Platforms**: PC (Windows/macOS/Linux), Web (HTML5)
- **Input Methods**: Keyboard/Mouse
- **Primary Input**: Mouse
- **Gamepad Support**: None (developer tool — not needed)
- **Touch Support**: Partial (web deployment may receive tablet touch input)
- **Platform Notes**: Web export via HTML5 template. All UI must function
  without hover-only states to ensure web/tablet compatibility.

## Naming Conventions

- **Classes**: PascalCase (e.g., `BunkerRoom`)
- **Variables**: snake_case (e.g., `agent_status`)
- **Signals/Events**: snake_case past tense (e.g., `task_completed`)
- **Files**: snake_case matching class (e.g., `bunker_room.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `BunkerRoom.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_AGENTS`)

## Performance Budgets

- **Target Framerate**: 60fps
- **Frame Budget**: 16.6ms
- **Draw Calls**: ≤1000
- **Memory Ceiling**: ≤512MB

## Testing

- **Framework**: GUT (Godot Unit Testing)
- **Minimum Coverage**: 80% for gameplay logic
- **Required Tests**: Balance formulas, gameplay systems

## Forbidden Patterns

- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

- **GUT** (Godot Unit Testing) — approved for test automation

## Architecture Decisions Log

- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and
  cross-cutting code review. Invoke GDScript specialist for code quality, signal
  architecture, static typing enforcement, and GDScript idioms. Invoke shader
  specialist for material design and shader code. Invoke GDExtension specialist
  only when native extensions are involved.

### File Extension Routing

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
