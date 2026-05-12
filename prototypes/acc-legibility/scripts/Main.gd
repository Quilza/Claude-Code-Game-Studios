# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can users identify 4 agent behavioral states in under 3 seconds?
# Date: 2026-05-09

extends Node2D

# --- Layout constants ---
const TILE_SIZE        := 32      # 16px logical tiles × 2 for readability
const GRID_COLS        := 20
const GRID_ROWS        := 15
const WINDOW_W         := 640
const WINDOW_H         := 480

# --- Colors (bunker palette) ---
const COLOR_FLOOR      := Color("#2A2520")
const COLOR_WALL       := Color("#3A3530")
const COLOR_GRID_LINE  := Color("#1A1510")
const COLOR_DESK       := Color("#3D3828")  # slightly lighter tile for desk spots
const COLOR_UI_TEXT    := Color("#AAAAAA")

# --- Agent starting positions (grid coords → pixel center) ---
# Spread across four quadrants so all are visible simultaneously
const AGENT_STARTS := [
	Vector2(5, 4),    # IDLE — top-left area
	Vector2(14, 4),   # WORKING — top-right area
	Vector2(5, 10),   # COMPLETED — bottom-left area
	Vector2(14, 10),  # ERRORED — bottom-right area
]

# Desk positions for the WORKING agent (where it walks to)
const DESK_POSITIONS := [
	Vector2(5, 4),
	Vector2(14, 4),   # WORKING agent's desk
	Vector2(5, 10),
	Vector2(14, 10),
]

# --- Agent labels ---
const AGENT_LABELS := ["IDLE", "WORKING", "COMPLETED", "ERRORED"]

# --- Starting states (var not const — enum refs from another class can't be const in GDScript 4) ---
var AGENT_STATES: Array = []

# --- Runtime ---
var agents: Array[AgentPreview] = []
var labels_visible: bool = true
var auto_cycle_timer: float = 0.0
const AUTO_CYCLE_INTERVAL: float = 4.0

# COMPLETED = index 2, ERRORED = index 3
const IDX_COMPLETED := 2
const IDX_ERRORED   := 3

var _floor_canvas: Node2D   # separate node so we draw under agents


func _ready() -> void:
	# Initialize state array here so enum refs resolve after AgentPreview is loaded
	AGENT_STATES = [
		AgentPreview.State.IDLE_WANDERING,
		AgentPreview.State.WORKING,
		AgentPreview.State.COMPLETED_BEAT,
		AgentPreview.State.ERRORED,
	]
	_build_room()
	_build_agents()
	_build_ui()


# ---------------------------------------------------------------------------
# Room geometry
# ---------------------------------------------------------------------------

func _build_room() -> void:
	# Use a CanvasItem subclass to draw the floor — we use a plain Node2D
	# and override _draw on a child DrawNode
	var draw_node := _DrawNode.new()
	draw_node.draw_callback = _draw_room
	add_child(draw_node)


func _draw_room(ci: CanvasItem) -> void:
	# Fill entire window with wall color first (border)
	ci.draw_rect(Rect2(0, 0, WINDOW_W, WINDOW_H), COLOR_WALL)

	# Draw floor tiles (inner grid, 1 tile border of wall)
	for row in range(1, GRID_ROWS - 1):
		for col in range(1, GRID_COLS - 1):
			var rect := Rect2(col * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			ci.draw_rect(rect, COLOR_FLOOR)

	# Draw desk tiles at WORKING agent's spot (and hint at others)
	var desk_tiles := [
		Vector2i(14, 4),
		Vector2i(15, 4),
		Vector2i(14, 3),
	]
	for dt in desk_tiles:
		var rect := Rect2(dt.x * TILE_SIZE, dt.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		ci.draw_rect(rect, COLOR_DESK)

	# Subtle grid lines over floor
	for row in range(1, GRID_ROWS):
		var y := float(row * TILE_SIZE)
		ci.draw_line(Vector2(TILE_SIZE, y), Vector2((GRID_COLS - 1) * TILE_SIZE, y), COLOR_GRID_LINE, 1.0)
	for col in range(1, GRID_COLS):
		var x := float(col * TILE_SIZE)
		ci.draw_line(Vector2(x, TILE_SIZE), Vector2(x, (GRID_ROWS - 1) * TILE_SIZE), COLOR_GRID_LINE, 1.0)

	# Wall border — draw a 1-tile-wide outline to make the room feel enclosed
	# Top and bottom walls
	for col in range(GRID_COLS):
		ci.draw_rect(Rect2(col * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE), COLOR_WALL)
		ci.draw_rect(Rect2(col * TILE_SIZE, (GRID_ROWS - 1) * TILE_SIZE, TILE_SIZE, TILE_SIZE), COLOR_WALL)
	# Left and right walls
	for row in range(GRID_ROWS):
		ci.draw_rect(Rect2(0, row * TILE_SIZE, TILE_SIZE, TILE_SIZE), COLOR_WALL)
		ci.draw_rect(Rect2((GRID_COLS - 1) * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE), COLOR_WALL)


# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------

func _build_agents() -> void:
	# Room bounds in pixels (inside 1-tile wall border)
	var room_bounds := Rect2(
		TILE_SIZE, TILE_SIZE,
		(GRID_COLS - 2) * TILE_SIZE,
		(GRID_ROWS - 2) * TILE_SIZE
	)

	for i in range(4):
		var agent := AgentPreview.new()
		agent.agent_label = AGENT_LABELS[i]

		# Convert grid coords to pixel center
		var grid_pos: Vector2 = AGENT_STARTS[i]
		agent.position = Vector2(
			(grid_pos.x + 0.5) * TILE_SIZE,
			(grid_pos.y + 0.5) * TILE_SIZE
		)

		# Desk position for WORKING agent
		var desk_grid: Vector2 = DESK_POSITIONS[i]
		agent.set_desk_position(Vector2(
			(desk_grid.x + 0.5) * TILE_SIZE,
			(desk_grid.y + 0.5) * TILE_SIZE
		))

		agent.set_room_bounds(room_bounds)
		add_child(agent)
		agents.append(agent)

		# Connect beat_finished signal for COMPLETED agent
		if i == IDX_COMPLETED:
			agent.beat_finished.connect(_on_completed_beat_finished)

		# Set initial state AFTER adding to scene (so _ready has run)
		agent.set_state(AGENT_STATES[i])


func _on_completed_beat_finished() -> void:
	# Agent auto-transitions to IDLE inside AgentPreview.
	# We schedule another COMPLETED_BEAT after a short delay so the
	# auto-cycle demo keeps looping.
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func(): _trigger_completed_beat())


func _trigger_completed_beat() -> void:
	if agents[IDX_COMPLETED].current_state == AgentPreview.State.IDLE_WANDERING:
		agents[IDX_COMPLETED].set_state(AgentPreview.State.COMPLETED_BEAT)


# ---------------------------------------------------------------------------
# UI overlay
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Instructions label — bottom-left corner
	var instructions := Label.new()
	instructions.text = "H = toggle labels | R = reset | SPACE = trigger completed"
	instructions.add_theme_font_size_override("font_size", 10)
	instructions.add_theme_color_override("font_color", COLOR_UI_TEXT)
	instructions.position = Vector2(8, WINDOW_H - 20)
	add_child(instructions)

	# Prototype watermark
	var watermark := Label.new()
	watermark.text = "PROTOTYPE — acc-legibility"
	watermark.add_theme_font_size_override("font_size", 9)
	watermark.add_theme_color_override("font_color", Color("#555555"))
	watermark.position = Vector2(WINDOW_W - 180, WINDOW_H - 20)
	add_child(watermark)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_H:
				labels_visible = not labels_visible
				for agent in agents:
					agent.set_labels_visible(labels_visible)

			KEY_R:
				_reset_all()

			KEY_SPACE:
				_cycle_special_agents()


func _reset_all() -> void:
	for i in range(agents.size()):
		var grid_pos: Vector2 = AGENT_STARTS[i]
		agents[i].position = Vector2(
			(grid_pos.x + 0.5) * TILE_SIZE,
			(grid_pos.y + 0.5) * TILE_SIZE
		)
		agents[i].set_state(AGENT_STATES[i])


func _cycle_special_agents() -> void:
	# Manually trigger the COMPLETED beat animation
	agents[IDX_COMPLETED].set_state(AgentPreview.State.COMPLETED_BEAT)
	# Cycle ERRORED between ERRORED and IDLE so user can see the transition
	var errored := agents[IDX_ERRORED]
	if errored.current_state == AgentPreview.State.ERRORED:
		errored.set_state(AgentPreview.State.IDLE_WANDERING)
	else:
		errored.set_state(AgentPreview.State.ERRORED)


# ---------------------------------------------------------------------------
# Auto-cycle timer
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	auto_cycle_timer += delta
	if auto_cycle_timer >= AUTO_CYCLE_INTERVAL:
		auto_cycle_timer = 0.0
		# Only auto-trigger completed if it's currently idle (not mid-animation)
		if agents[IDX_COMPLETED].current_state == AgentPreview.State.IDLE_WANDERING:
			agents[IDX_COMPLETED].set_state(AgentPreview.State.COMPLETED_BEAT)


# ---------------------------------------------------------------------------
# Inner class: a Node2D that exposes _draw via a callback
# (avoids needing a separate .gd file just for drawing)
# ---------------------------------------------------------------------------

class _DrawNode extends Node2D:
	var draw_callback: Callable

	func _draw() -> void:
		if draw_callback.is_valid():
			draw_callback.call(self)
