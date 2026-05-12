class_name TaskCompletionBeat extends Node
##
## TaskCompletionBeat (TCB) — Feature layer.
##
## Stateless event responder to ASM.task_completed. Plays the completion
## audio beat (via AudioManager), triggers a 3-phase room modulate Tween,
## and emits beat_fired for HUD to log.
##
## Governing architecture:
##   • ADR-0005 (task_completed Signal Source) — ASM is sole emitter
##   • ADR-0010 (Tween Lifecycle Management)   — bind_node + signal-not-await
##   • ADR-0006 (Signal-Based Decoupling)      — Tier 1 subscription
##
## GDD: design/gdd/task-completion-beat.md
##
## Per Rule 1: no persistent state. Each beat is an independent one-shot
## sequence. Per-room Tweens run independently.
##

# ─── Signals ─────────────────────────────────────────────────────────────────

signal beat_fired(agent_id: String, timestamp: float)


# ─── Tween shape constants (per Rule 3) ──────────────────────────────────────

const BEAT_ATTACK_SEC: float = 0.3
const BEAT_HOLD_SEC: float = 0.5
const BEAT_DECAY_SEC: float = 0.7
const BEAT_TOTAL_SEC: float = BEAT_ATTACK_SEC + BEAT_HOLD_SEC + BEAT_DECAY_SEC   # 1.5s — matches TR-hud-004
const BEAT_PEAK_COLOR: Color = Color(1.15, 1.35, 1.15, 1.0)
const BEAT_NEUTRAL_COLOR: Color = Color(1, 1, 1, 1)

const BUNKER_ROOMS_GROUP: StringName = &"bunker_rooms"
const DEFAULT_AGENT_TYPE: String = "default"


# ─── Dependencies (scene-wired) ──────────────────────────────────────────────

@export var agent_state_machine: AgentStateMachine = null
@export var room_system: RoomSystem = null


# ─── AgentSoundRegistry (per Rule 5) ─────────────────────────────────────────

# agent_type (String) → AudioStream
var _sound_registry: Dictionary = {}

# Per-room active Tweens — keyed by room_id (StringName).
# Used by Rule 7 same-room collision (kill + restart).
var _room_tweens: Dictionary = {}


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	_subscribe_to_asm()


func _subscribe_to_asm() -> void:
	if agent_state_machine == null:
		push_warning("[TCB] agent_state_machine not wired — TCB will not respond to task_completed")
		return
	agent_state_machine.task_completed.connect(_on_task_completed)


# ─── Beat sequence (per Rule 2) ──────────────────────────────────────────────

func _on_task_completed(agent_id: String) -> void:
	# 1. Resolve agent_type
	var agent_type: String = _resolve_agent_type(agent_id)
	# 2. Resolve AudioStream + 3. Play SFX
	var stream: AudioStream = _resolve_stream(agent_type)
	if stream != null and _audio_manager_available():
		AudioManager.play_sfx(stream)
	# 4. Emit beat_fired
	beat_fired.emit(agent_id, Time.get_unix_time_from_system())
	# 5. Trigger room modulate Tween
	_trigger_room_tween(agent_id)


func _resolve_agent_type(agent_id: String) -> String:
	if not _config_loader_available():
		return DEFAULT_AGENT_TYPE
	var agent: Dictionary = ConfigurationLoader.get_agent(agent_id)
	if agent.is_empty():
		return DEFAULT_AGENT_TYPE
	return String(agent.get("agent_type", DEFAULT_AGENT_TYPE))


func _resolve_stream(agent_type: String) -> AudioStream:
	if _sound_registry.has(agent_type):
		return _sound_registry[agent_type] as AudioStream
	if _sound_registry.has(DEFAULT_AGENT_TYPE):
		return _sound_registry[DEFAULT_AGENT_TYPE] as AudioStream
	push_warning("[TCB] no stream for agent_type '%s' and no default registered" % agent_type)
	return null


# ─── Room modulate Tween (per Rules 3, 6, 7 + ADR-0010) ──────────────────────

func _trigger_room_tween(agent_id: String) -> void:
	if room_system == null:
		push_warning("[TCB] room_system not wired — modulate Tween skipped")
		return
	var room_id: StringName = room_system.get_room_for_agent(agent_id)
	if room_id == &"":
		push_warning("[TCB] agent '%s' has no assigned room — modulate Tween skipped" % agent_id)
		return
	var room_node: Node2D = _find_room_node(room_id)
	if room_node == null:
		push_warning("[TCB] no Node2D in group '%s' with room_id '%s' — modulate Tween skipped" % [BUNKER_ROOMS_GROUP, room_id])
		return
	# Rule 7: same-room collision — kill existing Tween + restart from current modulate.
	if _room_tweens.has(room_id):
		var prev: Tween = _room_tweens[room_id]
		if prev != null and prev.is_valid():
			prev.kill()
	# ADR-0010 mandatory pattern: bind_node + signal-cleanup + sequential phases on one Tween.
	var t: Tween = create_tween()
	t.bind_node(room_node)
	t.tween_property(room_node, "modulate", BEAT_PEAK_COLOR, BEAT_ATTACK_SEC) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_property(room_node, "modulate", BEAT_PEAK_COLOR, BEAT_HOLD_SEC) \
		.set_trans(Tween.TRANS_LINEAR)
	t.tween_property(room_node, "modulate", BEAT_NEUTRAL_COLOR, BEAT_DECAY_SEC) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.finished.connect(_on_room_tween_finished.bind(room_id))
	_room_tweens[room_id] = t


func _find_room_node(room_id: StringName) -> Node2D:
	# Scene-tree group lookup per Rule 10. Each room scene must add_to_group(BUNKER_ROOMS_GROUP)
	# and expose a `room_id` property of type StringName.
	if get_tree() == null:
		return null
	for node: Node in get_tree().get_nodes_in_group(BUNKER_ROOMS_GROUP):
		if node is Node2D and "room_id" in node:
			if StringName(node.get("room_id")) == room_id:
				return node as Node2D
	return null


func _on_room_tween_finished(room_id: StringName) -> void:
	# Clean up our reference; Godot's Tween auto-frees.
	_room_tweens.erase(room_id)


# ─── AgentSoundRegistry public API (per Rule 5) ──────────────────────────────

## Registers an AudioStream for a given agent_type. Called at scene setup
## (Main Scene Bootstrap or an asset-loading helper).
## A "default" entry is required before any task_completed signal can be
## processed without producing a push_warning per Rule 5.
func register_sound(agent_type: String, stream: AudioStream) -> void:
	_sound_registry[agent_type] = stream


## True iff the registry has a stream for the given agent_type
## (or "default" as fallback per Rule 5).
func has_sound(agent_type: String) -> bool:
	return _sound_registry.has(agent_type) or _sound_registry.has(DEFAULT_AGENT_TYPE)


# ─── Helpers ────────────────────────────────────────────────────────────────

func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)


func _audio_manager_available() -> bool:
	return Engine.has_singleton("AudioManager") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("AudioManager")
	)
