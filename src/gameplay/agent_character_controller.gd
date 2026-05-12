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


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if agent_id.is_empty():
		push_error("[ACC] agent_id must be set before _ready()")
		return
	_load_tuning()
	_subscribe_to_asm()
	_position_at_workstation()
	_enter_state(BehavioralState.IDLE_WANDERING)


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


## Tier 2 pattern: bound agent_id is the first arg; signal payload follows.
func _on_asm_state_changed(bound_id: String, fired_id: String, new_state: String, _previous: String) -> void:
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
	_behavioral_state = new_state
	# Entry hooks
	match new_state:
		BehavioralState.IDLE_WANDERING:
			# TODO: spawn _idle_wander_coroutine() for weighted-random waypoints
			# (Rule 7 + 8 — needs NavigationAgent2D + waypoint sampling).
			pass
		BehavioralState.WORKING:
			# TODO: pathfind to workstation tile (Rule 6 — needs NavigationAgent2D).
			# For now, snap to workstation.
			_position_at_workstation()
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


# ─── Public read-only accessors ──────────────────────────────────────────────

func get_behavioral_state() -> int:
	return _behavioral_state


func get_last_asm_state() -> String:
	return _last_asm_state


func is_resigned_idle() -> bool:
	return _resigned_idle


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
