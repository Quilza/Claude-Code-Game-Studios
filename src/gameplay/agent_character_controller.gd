class_name AgentCharacterController extends CharacterBody2D
##
## AgentCharacterController (ACC) — Presentation layer.
##
## One instance per configured agent. Owns the agent's visible character:
## position, animation state, behavioral state machine (IDLE_WANDERING /
## WORKING / COMPLETED_BEAT / ERRORED).
##
## Governing architecture:
##   • ADR-0007 (Agent State Vocabulary)        — Accepted (4 ASM states)
##   • ADR-0009 (AnimationPlayer Strategy)      — Accepted (state-driven dispatch)
##   • ADR-0006 (Signal-Based Decoupling)       — Tier 2 with .bind(agent_id)
##
## GDD: design/gdd/agent-character-controller.md (post cross-GDD reconciliation)
##
## **Scope note**: this commit implements the architecture-shaped skeleton:
## ASM dispatch, internal state machine, animation triggers, workstation
## lookup, workstation pathfinding hooks. The complex behavioral logic
## (weighted-random idle wandering, prop interaction, pathfinding details,
## red `!` ERRORED indicator) is structured but stubbed pending sprite assets
## + NavigationRegion2D authoring. See TODO markers.
##

# ─── Internal state enum (per Rule 4) ────────────────────────────────────────

enum BehavioralState {
	UNINITIALIZED,
	IDLE_WANDERING,
	WORKING,
	COMPLETED_BEAT,
	ERRORED,
}


# ─── ASM state → animation name mapping (per ADR-0009) ───────────────────────

const ASM_STATE_TO_ANIM: Dictionary = {
	"idle": &"idle",
	"working": &"working",
	"completed": &"completed",
	"errored": &"errored_freeze",
}


# ─── Tuning constants ────────────────────────────────────────────────────────

const COMPLETED_BEAT_DURATION_SEC_DEFAULT: float = 2.0
const ERROR_TIMEOUT_SEC_DEFAULT: float = 30.0
const STAGGER_BASE_SEC: float = 0.2
const STAGGER_JITTER_SEC: float = 0.1
const RESIGNED_IDLE_SPEED_MULTIPLIER: float = 0.6

# Phase 1 movement substrate — direct lerp toward a world-space target.
# Phase 2 will swap `_physics_process` to drive a NavigationAgent2D once
# a NavigationRegion2D has been baked against real wall/collision geometry.
# The public API (`_set_walk_target`, `_has_walk_target`) stays identical so
# the swap is contained to `_physics_process`.
const V_BASE_PX_PER_SEC: float = 40.0          # GDD §Tuning Knobs — v_base
const ARRIVAL_TOLERANCE_PX: float = 1.0        # within 1px of target = arrived
const DWELL_OWN_ROOM_MIN_SEC: float = 2.0      # GDD §Idle Wandering — Dwell Times
const DWELL_OWN_ROOM_MAX_SEC: float = 4.0


# ─── Per-instance config ─────────────────────────────────────────────────────

@export var agent_id: String = ""
@export var agent_index: int = 0   # for stagger calculation
@export var agent_state_machine: AgentStateMachine = null
@export var room_system: RoomSystem = null
@export var tile_map_renderer: TileMapRenderer = null
@export var animation_player: AnimationPlayer = null


# ─── Internal state ──────────────────────────────────────────────────────────

var _behavioral_state: int = BehavioralState.UNINITIALIZED
var _last_asm_state: String = AgentStateMachine.STATE_IDLE
var _completed_beat_duration_sec: float = COMPLETED_BEAT_DURATION_SEC_DEFAULT
var _error_timeout_sec: float = ERROR_TIMEOUT_SEC_DEFAULT
var _queued_working_during_beat: bool = false
var _completed_beat_timer: Timer = null
var _error_freeze_timer: Timer = null
var _resigned_idle: bool = false

# Phase 1 movement state.
var _walk_target: Vector2 = Vector2.ZERO
var _has_walk_target: bool = false
var _dwell_timer: Timer = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if agent_id.is_empty():
		push_error("[ACC] agent_id must be set before _ready()")
		return
	_rng.randomize()
	_load_tuning()
	_subscribe_to_asm()
	_position_at_workstation()
	_enter_state(BehavioralState.IDLE_WANDERING)


# ─── Physics movement (Phase 1 direct lerp) ──────────────────────────────────

## Drives the character toward `_walk_target` at the current effective speed.
## When the character arrives within ARRIVAL_TOLERANCE_PX, snaps to target,
## clears the flag, and dispatches `_on_walk_arrived()` for per-state
## follow-up (next wander target, etc.).
##
## Phase 2: replace the lerp body with `nav_agent.set_target_position()` +
## `nav_agent.get_next_path_position()`. The arrival callback unchanged.
func _physics_process(delta: float) -> void:
	if not _has_walk_target:
		return
	var to_target: Vector2 = _walk_target - position
	var distance: float = to_target.length()
	if distance <= ARRIVAL_TOLERANCE_PX:
		position = _walk_target
		_has_walk_target = false
		_on_walk_arrived()
		return
	var step: float = _current_speed_px_per_sec() * delta
	if step >= distance:
		position = _walk_target
		_has_walk_target = false
		_on_walk_arrived()
	else:
		position += to_target / distance * step


# ─── Tuning ──────────────────────────────────────────────────────────────────

func _load_tuning() -> void:
	if _config_loader_available():
		_completed_beat_duration_sec = float(ConfigurationLoader.get_setting(
			"acc.completed_beat_duration_sec", COMPLETED_BEAT_DURATION_SEC_DEFAULT))
		_error_timeout_sec = float(ConfigurationLoader.get_setting(
			"acc.error_timeout_sec", ERROR_TIMEOUT_SEC_DEFAULT))


# ─── ASM subscription (Tier 2 per ADR-0006) ──────────────────────────────────

func _subscribe_to_asm() -> void:
	if agent_state_machine == null:
		push_warning("[ACC:%s] agent_state_machine not wired — ACC will not respond to ASM" % agent_id)
		return
	agent_state_machine.agent_state_changed.connect(_on_asm_state_changed.bind(agent_id))


## Tier 2 pattern (per ADR-0006): signal payload comes first, bound agent_id
## last. Godot 4 `Callable.bind()` semantics: bound arguments are passed
## AFTER the arguments supplied by the caller (signal emitter), not before.
## Verified against https://docs.godotengine.org/en/4.3/classes/class_callable.html#class-callable-method-bind
func _on_asm_state_changed(fired_id: String, new_state: String, _previous: String, bound_id: String) -> void:
	if bound_id != fired_id:
		return   # filter — only respond to our own agent's state
	_last_asm_state = new_state
	# Drive AnimationPlayer per ADR-0009
	_play_animation_for_state(new_state)
	# Drive behavioral state machine per GDD Rule 5
	match new_state:
		AgentStateMachine.STATE_WORKING:
			# Immediate interrupt per Rule 5 — unless in COMPLETED_BEAT (Rule queued)
			if _behavioral_state == BehavioralState.COMPLETED_BEAT:
				_queued_working_during_beat = true
			else:
				_enter_state(BehavioralState.WORKING)
		AgentStateMachine.STATE_COMPLETED:
			_enter_state(BehavioralState.COMPLETED_BEAT)
		AgentStateMachine.STATE_ERRORED:
			_enter_state(BehavioralState.ERRORED)
		AgentStateMachine.STATE_IDLE:
			# Returning to idle (e.g., completed → decay → idle) — enter wandering.
			_enter_state(BehavioralState.IDLE_WANDERING)


# ─── Behavioral state machine (per Rule 4) ───────────────────────────────────

func _enter_state(new_state: int) -> void:
	if _behavioral_state == new_state:
		return
	# Exit hooks
	if _behavioral_state == BehavioralState.COMPLETED_BEAT and _completed_beat_timer != null:
		_completed_beat_timer.stop()
		_completed_beat_timer.queue_free()
		_completed_beat_timer = null
	if _behavioral_state == BehavioralState.ERRORED and _error_freeze_timer != null:
		_error_freeze_timer.stop()
		_error_freeze_timer.queue_free()
		_error_freeze_timer = null
		_resigned_idle = false
	# Cancel any in-flight dwell when leaving IDLE_WANDERING (Rule 5: immediate interrupt).
	if _dwell_timer != null and is_instance_valid(_dwell_timer):
		_dwell_timer.stop()
		_dwell_timer.queue_free()
		_dwell_timer = null
	_behavioral_state = new_state
	# Entry hooks
	match new_state:
		BehavioralState.IDLE_WANDERING:
			# Phase 1: single-category own-room wandering with dwell.
			# Phase 2 (TODO): weighted sampling across the 5 GDD categories
			# (social / prop / other_room / corridor / own_room) with C_recency
			# cooldown — Rules 7 + 8.
			_has_walk_target = false   # cancel any prior leg
			_pick_idle_wander_target()
		BehavioralState.WORKING:
			# Rule 5: immediate redirect — walk to the workstation tile
			# rather than teleporting. Phase 2: NavigationAgent2D for
			# obstacle-aware routing. For now, direct lerp.
			_walk_to_workstation()
		BehavioralState.COMPLETED_BEAT:
			_completed_beat_timer = Timer.new()
			_completed_beat_timer.one_shot = true
			_completed_beat_timer.wait_time = _completed_beat_duration_sec
			add_child(_completed_beat_timer)
			_completed_beat_timer.timeout.connect(_on_completed_beat_finished)
			_completed_beat_timer.start()
		BehavioralState.ERRORED:
			_error_freeze_timer = Timer.new()
			_error_freeze_timer.one_shot = true
			_error_freeze_timer.wait_time = _error_timeout_sec
			add_child(_error_freeze_timer)
			_error_freeze_timer.timeout.connect(_on_error_freeze_finished)
			_error_freeze_timer.start()


func _on_completed_beat_finished() -> void:
	# Per Rule 4: WORKING signal during COMPLETED_BEAT is queued.
	if _queued_working_during_beat:
		_queued_working_during_beat = false
		_enter_state(BehavioralState.WORKING)
	else:
		_enter_state(BehavioralState.IDLE_WANDERING)


func _on_error_freeze_finished() -> void:
	# Per Rule 10: 30s freeze → resigned idle (0.6× speed + red `!`).
	_resigned_idle = true
	# Stay in ERRORED state but allow movement at reduced speed.
	# Red `!` indicator: TODO when sprite assets land.
	_enter_state(BehavioralState.IDLE_WANDERING)


# ─── Animation (per ADR-0009) ────────────────────────────────────────────────

func _play_animation_for_state(asm_state: String) -> void:
	if animation_player == null:
		return
	var anim_name: StringName = ASM_STATE_TO_ANIM.get(asm_state, &"idle")
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)


# ─── Position helpers ────────────────────────────────────────────────────────

func _position_at_workstation() -> void:
	if room_system == null or tile_map_renderer == null:
		return
	var tile: Vector2i = room_system.get_workstation_for_agent(agent_id)
	if tile == Vector2i(-1, -1):
		return
	position = tile_map_renderer.tile_to_world(tile)


# ─── Movement API + Phase 1 helpers ──────────────────────────────────────────

## Sets the lerp target. `_physics_process` advances toward it each frame.
## Public-but-underscored: state machines call this; external code should not.
## Safe to call repeatedly — overwrites prior target.
func _set_walk_target(world_pos: Vector2) -> void:
	_walk_target = world_pos
	_has_walk_target = true


## Returns the current effective walk speed in px/sec. Applies the resigned-
## idle multiplier (Rule 10) when the agent has timed out of an ERRORED freeze.
func _current_speed_px_per_sec() -> float:
	if _resigned_idle:
		return V_BASE_PX_PER_SEC * RESIGNED_IDLE_SPEED_MULTIPLIER
	return V_BASE_PX_PER_SEC


## Called after `_physics_process` snaps the character to its target. Dispatches
## state-specific follow-up. Phase 2 will add prop-interaction triggers and
## ambient-prop animation hooks here.
func _on_walk_arrived() -> void:
	match _behavioral_state:
		BehavioralState.IDLE_WANDERING:
			_start_dwell()
		BehavioralState.WORKING:
			# Arrived at workstation — stay put; ASM keeps us in WORKING.
			pass
		_:
			pass


## Sends the character toward its assigned workstation tile. Called on
## WORKING entry (Rule 5). No-op if the agent has no workstation (e.g. the
## Commander).
func _walk_to_workstation() -> void:
	if room_system == null or tile_map_renderer == null:
		return
	var tile: Vector2i = room_system.get_workstation_for_agent(agent_id)
	if tile == Vector2i(-1, -1):
		return
	_set_walk_target(tile_map_renderer.tile_to_world(tile))


## Phase 1 idle-wander: picks one random tile inside the agent's own room
## bounds and walks to it. No social / prop / cross-room sampling — that's
## Phase 2.
##
## No-op if room_system or tile_map_renderer is missing (test paths) or if
## the agent has no assigned room (returns silently).
func _pick_idle_wander_target() -> void:
	if room_system == null or tile_map_renderer == null:
		return
	var room_id: StringName = room_system.get_room_for_agent(agent_id)
	if room_id == &"":
		return
	var room_data = room_system.get_room(room_id)
	if room_data == null:
		return
	var bounds: Rect2i = room_data.bounds
	# Inset by 1 tile to avoid wall-adjacent picks once collision geometry exists.
	var min_x: int = bounds.position.x + 1
	var max_x: int = bounds.position.x + bounds.size.x - 2
	var min_y: int = bounds.position.y + 1
	var max_y: int = bounds.position.y + bounds.size.y - 2
	if max_x < min_x or max_y < min_y:
		return   # bounds too small to inset; bail rather than pick a wall
	var tile_x: int = _rng.randi_range(min_x, max_x)
	var tile_y: int = _rng.randi_range(min_y, max_y)
	_set_walk_target(tile_map_renderer.tile_to_world(Vector2i(tile_x, tile_y)))


## Starts a uniform-random dwell timer per GDD §Idle Wandering — Dwell Times
## (own_room: 2.0–4.0s). On timeout, picks the next wander target.
func _start_dwell() -> void:
	var dwell_sec: float = _rng.randf_range(DWELL_OWN_ROOM_MIN_SEC, DWELL_OWN_ROOM_MAX_SEC)
	_dwell_timer = Timer.new()
	_dwell_timer.one_shot = true
	_dwell_timer.wait_time = dwell_sec
	add_child(_dwell_timer)
	_dwell_timer.timeout.connect(_on_dwell_finished)
	_dwell_timer.start()


func _on_dwell_finished() -> void:
	if _dwell_timer != null and is_instance_valid(_dwell_timer):
		_dwell_timer.queue_free()
		_dwell_timer = null
	# Only pick a new target if we're still wandering — defensive against
	# concurrent state transitions (e.g. WORKING fired during dwell).
	if _behavioral_state == BehavioralState.IDLE_WANDERING:
		_pick_idle_wander_target()


# ─── Public read-only accessors ──────────────────────────────────────────────

func get_behavioral_state() -> int:
	return _behavioral_state


func get_last_asm_state() -> String:
	return _last_asm_state


func is_resigned_idle() -> bool:
	return _resigned_idle


func has_walk_target() -> bool:
	return _has_walk_target


func get_walk_target() -> Vector2:
	return _walk_target


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)


# ─── Test-only seam ─────────────────────────────────────────────────────────

func _test_force_state(state: int) -> void:
	_enter_state(state)
