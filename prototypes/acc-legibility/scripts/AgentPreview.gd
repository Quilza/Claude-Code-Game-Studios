# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can users identify 4 agent behavioral states in under 3 seconds?
# Date: 2026-05-09

class_name AgentPreview
extends Node2D

enum State { IDLE_WANDERING, WORKING, COMPLETED_BEAT, ERRORED }

signal beat_finished

# --- Exported ---
@export var agent_label: String = "AGENT"

# --- Colors ---
const COLOR_IDLE     := Color("#D4882A")
const COLOR_WORKING  := Color("#4A9A52")
const COLOR_ERRORED  := Color("#A03520")
const COLOR_WHITE    := Color("#FFFFFF")
const SPRITE_SIZE    := Vector2(16, 16)

# --- State ---
var current_state: State = State.IDLE_WANDERING
var labels_visible: bool = true

# --- Movement (IDLE) ---
var wander_target: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var room_bounds: Rect2 = Rect2(32, 32, 576, 416)  # safe area inside walls

# --- Working bob ---
var bob_time: float = 0.0
var desk_position: Vector2 = Vector2.ZERO

# --- Completed beat ---
var beat_time: float = 0.0
const BEAT_DURATION: float = 0.5

# --- Base visual ---
var base_color: Color = COLOR_IDLE
var current_color: Color = COLOR_IDLE
var current_scale: Vector2 = Vector2.ONE
var y_offset: float = 0.0

# --- Child nodes ---
var _sprite: ColorRect
var _name_label: Label
var _error_label: Label  # the "!" above errored agent


func _ready() -> void:
	_build_visuals()
	_pick_wander_target()


func _build_visuals() -> void:
	# Main sprite — 16x16 ColorRect, offset so position is the center
	_sprite = ColorRect.new()
	_sprite.size = SPRITE_SIZE
	_sprite.position = -SPRITE_SIZE / 2.0
	add_child(_sprite)

	# State name label (above sprite)
	_name_label = Label.new()
	_name_label.text = agent_label
	_name_label.add_theme_font_size_override("font_size", 9)
	_name_label.add_theme_color_override("font_color", Color("#CCCCCC"))
	_name_label.position = Vector2(-20, -SPRITE_SIZE.y - 14)
	_name_label.size = Vector2(56, 14)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)

	# Error "!" label — only shown in ERRORED state
	_error_label = Label.new()
	_error_label.text = "!"
	_error_label.add_theme_font_size_override("font_size", 14)
	_error_label.add_theme_color_override("font_color", Color("#FF4444"))
	_error_label.position = Vector2(-4, -SPRITE_SIZE.y - 22)
	_error_label.visible = false
	add_child(_error_label)

	_apply_visuals()


func set_state(new_state: State) -> void:
	current_state = new_state
	beat_time = 0.0
	bob_time = 0.0
	y_offset = 0.0
	current_scale = Vector2.ONE

	match new_state:
		State.IDLE_WANDERING:
			base_color = COLOR_IDLE
			current_color = COLOR_IDLE
			_pick_wander_target()
		State.WORKING:
			base_color = COLOR_WORKING
			current_color = COLOR_WORKING
		State.COMPLETED_BEAT:
			base_color = COLOR_IDLE
			current_color = COLOR_WHITE
			beat_time = 0.0
		State.ERRORED:
			base_color = COLOR_ERRORED
			current_color = COLOR_ERRORED

	_apply_visuals()


func set_desk_position(pos: Vector2) -> void:
	desk_position = pos


func set_labels_visible(vis: bool) -> void:
	labels_visible = vis
	_name_label.visible = vis
	# error label visibility is state-driven, but still respects the toggle
	if current_state == State.ERRORED:
		_error_label.visible = vis


func set_room_bounds(bounds: Rect2) -> void:
	room_bounds = bounds


func _process(delta: float) -> void:
	match current_state:
		State.IDLE_WANDERING:
			_process_idle(delta)
		State.WORKING:
			_process_working(delta)
		State.COMPLETED_BEAT:
			_process_completed(delta)
		State.ERRORED:
			pass  # frozen — nothing to update

	_apply_visuals()


func _process_idle(delta: float) -> void:
	# Move toward wander target
	var dist := position.distance_to(wander_target)
	if dist > 2.0:
		position = position.move_toward(wander_target, 30.0 * delta)
	else:
		# Arrived — schedule next wander
		wander_timer -= delta
		if wander_timer <= 0.0:
			_pick_wander_target()


func _process_working(delta: float) -> void:
	# Gently move toward desk position
	position = position.move_toward(desk_position, 60.0 * delta)
	# Sinusoidal Y bob: ±2px at 1Hz
	bob_time += delta
	y_offset = sin(bob_time * TAU) * 2.0


func _process_completed(delta: float) -> void:
	beat_time += delta
	var t := beat_time / BEAT_DURATION  # 0 → 1

	if t >= 1.0:
		# Animation done — auto-transition to idle
		y_offset = 0.0
		current_scale = Vector2.ONE
		current_color = base_color
		beat_finished.emit()
		set_state(State.IDLE_WANDERING)
		return

	# Scale pop: 1.0 → 1.4 → 1.0 using a sine arch
	var scale_factor := 1.0 + 0.4 * sin(t * PI)
	current_scale = Vector2(scale_factor, scale_factor)

	# Color flash: white → amber over the duration
	current_color = COLOR_WHITE.lerp(COLOR_IDLE, t)


func _apply_visuals() -> void:
	_sprite.color = current_color
	_sprite.position = Vector2(-SPRITE_SIZE.x / 2.0, -SPRITE_SIZE.y / 2.0 + y_offset)
	scale = current_scale

	# Error label
	var show_error := (current_state == State.ERRORED) and labels_visible
	_error_label.visible = show_error

	# Name label
	_name_label.visible = labels_visible


func _pick_wander_target() -> void:
	# Pick a random point within room_bounds, snapped to 16px grid feel
	var margin := 24.0
	var x := randf_range(room_bounds.position.x + margin, room_bounds.end.x - margin)
	var y := randf_range(room_bounds.position.y + margin, room_bounds.end.y - margin)
	wander_target = Vector2(x, y)
	wander_timer = randf_range(2.0, 3.5)
