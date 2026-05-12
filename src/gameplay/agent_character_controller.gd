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


# ─── Preloaded helpers ───────────────────────────────────────────────────────

## Preloaded (rather than class_name'd) so the Godot 4.3 global-class index
## doesn't need a project reimport before this file compiles. Equivalent to
## the class_name lookup at runtime.
const AnimFactory = preload("res://src/gameplay/agent_default_animation_factory.gd")


# ─── ASM state → animation name mapping (per ADR-0009) ───────────────────────

## Names must match the AnimationLibrary keys in
## AnimFactory.ANIM_*. The `errored_freeze` /
## `errored_resigned` distinction in the GDD §Sprite & Animation table is a
## Phase 2 concern (separate sprite rows); the placeholder library uses a
## single `errored` anim for both freeze and resigned phases.
const ASM_STATE_TO_ANIM: Dictionary = {
	"idle": &"idle",
	"working": &"working",
	"completed": &"completed",
	"errored": &"errored",
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

# ─── Phase 2 weighted wandering (GDD Rules 7 + 8) ────────────────────────────

## Category identifiers — string keys used by recency dict + dwell lookups.
const CAT_SOCIAL: String = "social"
const CAT_PROP: String = "prop"
const CAT_OTHER_ROOM: String = "other_room"
const CAT_CORRIDOR: String = "corridor"
const CAT_OWN_ROOM: String = "own_room"

## Base waypoint weights — GDD §Tuning Knobs → Idle Wandering — Waypoint Weights.
## prop/corridor are 0 in Phase 2 because (a) no ambient_prop scene nodes exist
## yet and (b) "corridor" is a GDD Open Question — the 2-tile gap between
## rooms isn't currently owned by any system. Flip back to GDD defaults when
## those dependencies land (no architectural rework needed).
const W_SOCIAL_BASE: float = 35.0
const W_PROP_BASE: float = 0.0                  # GDD default 25; deferred (no props)
const W_OTHER_ROOM_BASE: float = 20.0
const W_CORRIDOR_BASE: float = 0.0              # GDD default 15; deferred (no corridor)
const W_OWN_ROOM_BASE: float = 5.0

## Recency cooldown — after visiting a category, its weight multiplier drops
## to C_RECENCY_FLOOR (0.2). The multiplier decays back toward 1.0 at
## RECENCY_DECAY_PER_SEC each second of process time.
const C_RECENCY_FLOOR: float = 0.2
const RECENCY_DECAY_PER_SEC: float = 0.1

## Per-category dwell ranges — GDD §Idle Wandering — Dwell Times.
const DWELL_SOCIAL_MIN_SEC: float = 5.0
const DWELL_SOCIAL_MAX_SEC: float = 10.0
const DWELL_PROP_MIN_SEC: float = 4.0
const DWELL_PROP_MAX_SEC: float = 8.0
const DWELL_OTHER_ROOM_MIN_SEC: float = 3.0
const DWELL_OTHER_ROOM_MAX_SEC: float = 6.0
const DWELL_CORRIDOR_MIN_SEC: float = 0.0
const DWELL_CORRIDOR_MAX_SEC: float = 0.5
const DWELL_OWN_ROOM_MIN_SEC: float = 2.0
const DWELL_OWN_ROOM_MAX_SEC: float = 4.0

## How close to a peer the social picker samples (in tile units). 2 tiles
## ~= 32px which is "next to" without overlapping.
const SOCIAL_PEER_RADIUS_TILES: int = 2

## Scene-tree group every ACC joins so peers can find each other for the
## social waypoint category.
const AGENT_CHARACTERS_GROUP: StringName = &"agent_characters"


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

# Phase 2 wandering state.
## Per-category recency multiplier ∈ [C_RECENCY_FLOOR, 1.0]. Drops to floor on
## category visit; decays back toward 1.0 at RECENCY_DECAY_PER_SEC.
var _recency: Dictionary = {
	CAT_SOCIAL: 1.0,
	CAT_PROP: 1.0,
	CAT_OTHER_ROOM: 1.0,
	CAT_CORRIDOR: 1.0,
	CAT_OWN_ROOM: 1.0,
}
## The category of the wander target currently being walked toward (or just
## arrived at). Drives `_start_dwell()` dwell-range lookup.
var _current_category: String = ""


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if agent_id.is_empty():
		push_error("[ACC] agent_id must be set before _ready()")
		return
	_rng.randomize()
	# Phase 2: join the peer-discovery group so other ACCs can pick us as a
	# social waypoint target. Must happen before any wander pick fires.
	add_to_group(AGENT_CHARACTERS_GROUP)
	_load_tuning()
	_ensure_placeholder_visual_and_animation()
	_subscribe_to_asm()
	_position_at_workstation()
	_enter_state(BehavioralState.IDLE_WANDERING)
	# Start the idle animation immediately so resting agents have visible motion.
	if animation_player != null:
		animation_player.play(&"idle")


# ─── Recency decay (Phase 2, GDD Rule 8) ─────────────────────────────────────

## Decays per-category recency multipliers toward 1.0 each frame. Only runs
## while wandering — other behavioral states don't pick targets so recency
## state is frozen.
func _process(delta: float) -> void:
	if _behavioral_state != BehavioralState.IDLE_WANDERING:
		return
	if _recency.is_empty():
		return
	var step: float = RECENCY_DECAY_PER_SEC * delta
	for cat: String in _recency.keys():
		var cur: float = float(_recency[cat])
		if cur < 1.0:
			_recency[cat] = minf(1.0, cur + step)


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
			# Immediate interrupt per Rule 5 — unless in COMPLETED_BEAT
			# (Rule 5b: queue until beat finishes) or ERRORED (Rule 10:
			# freeze stays intact for the full error_timeout_seconds — a
			# rapid working/errored cycle from upstream must not starve
			# the freeze. The frozen visual is the legibility signal the
			# GDD's Pillar 1 + Pillar 3 depend on.)
			if _behavioral_state == BehavioralState.COMPLETED_BEAT:
				_queued_working_during_beat = true
			elif _behavioral_state == BehavioralState.ERRORED:
				pass   # ignore — freeze runs to completion
			else:
				_enter_state(BehavioralState.WORKING)
		AgentStateMachine.STATE_COMPLETED:
			_enter_state(BehavioralState.COMPLETED_BEAT)
		AgentStateMachine.STATE_ERRORED:
			_enter_state(BehavioralState.ERRORED)
		AgentStateMachine.STATE_IDLE:
			# Returning to idle (e.g., completed → decay → idle) — enter wandering.
			# Same reasoning as WORKING-during-ERRORED above: if we're frozen,
			# stay frozen until the timer fires.
			if _behavioral_state == BehavioralState.ERRORED:
				pass
			else:
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
			# GDD Rule 10: "character freezes at its current position".
			# Cancel any in-flight walk so _physics_process doesn't keep
			# lerping toward the previous target while the freeze visual is
			# meant to be showing.
			_has_walk_target = false
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

## Ensures the placeholder Body ColorRect + AnimationPlayer exist as children
## of this ACC. Idempotent: if either is already wired at scene-author time
## (via @export), this method preserves them. Otherwise it constructs the
## minimum viable substrate per ADR-0009 §345 (placeholder library acceptable).
##
## Replace with real authored .tscn templates when sprite assets land.
func _ensure_placeholder_visual_and_animation() -> void:
	# 1. Body (ColorRect placeholder) — child of ACC, 16x16 px, centered on
	#    the character's origin via -8,-8 offset. Color picked from agent_type.
	if get_node_or_null(^"Body") == null:
		var body: ColorRect = ColorRect.new()
		body.name = "Body"
		body.size = Vector2(16, 16)
		body.position = Vector2(-8, -8)
		body.color = AnimFactory.body_color_for_agent_type(_resolve_agent_type())
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(body)
	# 2. AnimationPlayer — if scene author didn't wire one, build one now and
	#    attach the placeholder library.
	if animation_player == null:
		var ap: AnimationPlayer = AnimationPlayer.new()
		ap.name = "AnimationPlayerStub"
		add_child(ap)
		animation_player = ap
	# 3. Attach the placeholder library and activate the mixer (VERIFY-6).
	var lib: AnimationLibrary = AnimFactory.build_placeholder_library()
	# add_animation_library returns OK or ERR_ALREADY_EXISTS; latter only
	# fires if a real .tres lib was pre-attached at scene-author time.
	if not animation_player.has_animation_library(&""):
		animation_player.add_animation_library(&"", lib)
	animation_player.active = true
	# 4. Wire the one-shot revert for `completed` per ADR-0009 §Rule.
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)


## Reads agent_type from ConfigurationLoader for body-color selection.
## Falls back to "default" when ConfigLoader is unavailable (test paths).
func _resolve_agent_type() -> String:
	if not _config_loader_available():
		return "default"
	var agent: Dictionary = ConfigurationLoader.get_agent(agent_id)
	if agent.is_empty():
		return "default"
	return String(agent.get("agent_type", "default"))


func _play_animation_for_state(asm_state: String) -> void:
	if animation_player == null:
		return
	var anim_name: StringName = ASM_STATE_TO_ANIM.get(asm_state, &"idle")
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)


## ADR-0009 one-shot revert: when `completed` (LOOP_NONE) finishes, return
## to idle. Other anims either loop or are explicitly replaced by the next
## state transition, so no revert is needed for them.
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"completed" and animation_player != null:
		animation_player.play(&"idle")


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


## Phase 2 weighted idle-wander (GDD Rules 7 + 8).
##
## Builds candidate categories with available targets, multiplies each base
## weight by the per-category recency multiplier, samples one category via
## weighted random, dispatches to that category's picker, drops the chosen
## category's recency to C_RECENCY_FLOOR.
##
## Falls back to own_room when no other category has candidates (e.g. a
## single configured agent + a single registered room). Bails silently if
## even own_room is unavailable (test paths with no room_system).
func _pick_idle_wander_target() -> void:
	if room_system == null or tile_map_renderer == null:
		return
	# 1. Build the list of available categories with their effective weights.
	var weights: Dictionary = _build_effective_weights()
	if weights.is_empty():
		return
	# 2. Weighted random pick of category.
	var chosen: String = _weighted_random_category(weights)
	if chosen.is_empty():
		return
	# 3. Dispatch to the category's picker.
	var target: Variant = _pick_target_for_category(chosen)
	if target == null:
		# Category said it could pick but failed at last mile; bail to avoid
		# a stuck-at-rest state.
		return
	# 4. Set the walk target and apply recency floor for this category.
	_current_category = chosen
	_set_walk_target(target as Vector2)
	_recency[chosen] = C_RECENCY_FLOOR


## Returns {category → effective_weight} for categories that (a) have a
## non-zero base weight AND (b) currently have valid candidates. Effective
## weight = base × recency. Categories with no candidates are filtered out
## entirely so weight allocation doesn't get wasted.
func _build_effective_weights() -> Dictionary:
	var weights: Dictionary = {}
	# own_room — needs an assigned room with non-trivial bounds.
	if W_OWN_ROOM_BASE > 0.0 and _has_own_room_candidates():
		weights[CAT_OWN_ROOM] = W_OWN_ROOM_BASE * float(_recency[CAT_OWN_ROOM])
	# other_room — needs at least one room other than our own.
	if W_OTHER_ROOM_BASE > 0.0 and _has_other_room_candidates():
		weights[CAT_OTHER_ROOM] = W_OTHER_ROOM_BASE * float(_recency[CAT_OTHER_ROOM])
	# social — needs at least one other ACC in the agent_characters group.
	if W_SOCIAL_BASE > 0.0 and _has_social_candidates():
		weights[CAT_SOCIAL] = W_SOCIAL_BASE * float(_recency[CAT_SOCIAL])
	# prop / corridor — Phase 2 leaves base weight at 0; included for future flip.
	if W_PROP_BASE > 0.0 and _has_prop_candidates():
		weights[CAT_PROP] = W_PROP_BASE * float(_recency[CAT_PROP])
	if W_CORRIDOR_BASE > 0.0:
		weights[CAT_CORRIDOR] = W_CORRIDOR_BASE * float(_recency[CAT_CORRIDOR])
	return weights


## Returns true iff the agent has an assigned room with insettable bounds.
func _has_own_room_candidates() -> bool:
	var room_id: StringName = room_system.get_room_for_agent(agent_id)
	if room_id == &"":
		return false
	var room_data = room_system.get_room(room_id)
	if room_data == null:
		return false
	var b: Rect2i = room_data.bounds
	# Need at least one walkable tile after the 1-tile wall inset.
	return b.size.x >= 3 and b.size.y >= 3


## Returns true iff at least one room other than the agent's own is registered.
func _has_other_room_candidates() -> bool:
	var own_room_id: StringName = room_system.get_room_for_agent(agent_id)
	for id: StringName in room_system.get_all_room_ids():
		if id != own_room_id:
			var rd = room_system.get_room(id)
			if rd != null and rd.bounds.size.x >= 3 and rd.bounds.size.y >= 3:
				return true
	return false


## Returns true iff at least one OTHER ACC is in the agent_characters group.
func _has_social_candidates() -> bool:
	if get_tree() == null:
		return false
	for peer: Node in get_tree().get_nodes_in_group(AGENT_CHARACTERS_GROUP):
		if peer != self:
			return true
	return false


## Returns true iff any ambient_prop nodes exist. Always false in Phase 2.
func _has_prop_candidates() -> bool:
	if get_tree() == null:
		return false
	return get_tree().get_nodes_in_group(&"ambient_prop").size() > 0


## Picks a category by weighted random sample. Returns "" if total weight is 0.
func _weighted_random_category(weights: Dictionary) -> String:
	var total: float = 0.0
	for w: Variant in weights.values():
		total += float(w)
	if total <= 0.0:
		return ""
	var roll: float = _rng.randf_range(0.0, total)
	var accumulator: float = 0.0
	for cat: String in weights.keys():
		accumulator += float(weights[cat])
		if roll <= accumulator:
			return cat
	# Floating-point edge — return the last category as a safe fallback.
	return weights.keys()[weights.size() - 1] as String


## Dispatches to the picker for a category. Returns a world-space target
## (Vector2) or null if the category couldn't pick at last mile.
func _pick_target_for_category(category: String) -> Variant:
	match category:
		CAT_OWN_ROOM:
			return _pick_own_room_target()
		CAT_OTHER_ROOM:
			return _pick_other_room_target()
		CAT_SOCIAL:
			return _pick_social_target()
		_:
			return null   # prop / corridor — Phase 3


## Picks a random walkable tile inside the agent's assigned room (1-tile inset).
func _pick_own_room_target() -> Variant:
	var room_id: StringName = room_system.get_room_for_agent(agent_id)
	if room_id == &"":
		return null
	return _pick_random_tile_in_room(room_id)


## Picks a random walkable tile inside any room OTHER than the agent's own.
## Uniform choice across other rooms (each room equally likely, regardless
## of size). Returns null if there are no other rooms.
func _pick_other_room_target() -> Variant:
	var own_room_id: StringName = room_system.get_room_for_agent(agent_id)
	var candidates: Array[StringName] = []
	for id: StringName in room_system.get_all_room_ids():
		if id != own_room_id:
			var rd = room_system.get_room(id)
			if rd != null and rd.bounds.size.x >= 3 and rd.bounds.size.y >= 3:
				candidates.append(id)
	if candidates.is_empty():
		return null
	var pick: StringName = candidates[_rng.randi_range(0, candidates.size() - 1)]
	return _pick_random_tile_in_room(pick)


## Picks a random tile within SOCIAL_PEER_RADIUS_TILES of another ACC's
## current world position. The peer is sampled uniformly across all peers
## (excluding self). Returned tile is clamped to the peer's room bounds
## so we don't pathfind through a wall when geometry lands.
func _pick_social_target() -> Variant:
	if get_tree() == null:
		return null
	# Collect peers.
	var peers: Array[Node] = []
	for n: Node in get_tree().get_nodes_in_group(AGENT_CHARACTERS_GROUP):
		if n != self:
			peers.append(n)
	if peers.is_empty():
		return null
	var peer: AgentCharacterController = peers[_rng.randi_range(0, peers.size() - 1)] as AgentCharacterController
	if peer == null:
		return null
	# Peer's tile coord.
	var peer_tile: Vector2i = tile_map_renderer.world_to_tile(peer.position)
	# Sample within ±radius tiles.
	var ox: int = _rng.randi_range(-SOCIAL_PEER_RADIUS_TILES, SOCIAL_PEER_RADIUS_TILES)
	var oy: int = _rng.randi_range(-SOCIAL_PEER_RADIUS_TILES, SOCIAL_PEER_RADIUS_TILES)
	var target_tile: Vector2i = peer_tile + Vector2i(ox, oy)
	# Clamp to peer's room bounds (1-tile inset) if peer has an assigned room.
	var peer_room_id: StringName = room_system.get_room_for_agent(peer.agent_id)
	if peer_room_id != &"":
		var peer_room = room_system.get_room(peer_room_id)
		if peer_room != null:
			var b: Rect2i = peer_room.bounds
			target_tile.x = clampi(target_tile.x, b.position.x + 1, b.position.x + b.size.x - 2)
			target_tile.y = clampi(target_tile.y, b.position.y + 1, b.position.y + b.size.y - 2)
	return tile_map_renderer.tile_to_world(target_tile)


## Internal helper: picks a random tile (1-tile wall inset) inside a room's
## bounds. Returns world-space center of that tile. Returns null if the room
## is too small to inset.
func _pick_random_tile_in_room(room_id: StringName) -> Variant:
	var room_data = room_system.get_room(room_id)
	if room_data == null:
		return null
	var bounds: Rect2i = room_data.bounds
	var min_x: int = bounds.position.x + 1
	var max_x: int = bounds.position.x + bounds.size.x - 2
	var min_y: int = bounds.position.y + 1
	var max_y: int = bounds.position.y + bounds.size.y - 2
	if max_x < min_x or max_y < min_y:
		return null
	var tx: int = _rng.randi_range(min_x, max_x)
	var ty: int = _rng.randi_range(min_y, max_y)
	return tile_map_renderer.tile_to_world(Vector2i(tx, ty))


## Starts a uniform-random dwell timer using the range for the category we
## just arrived at. On timeout, picks the next wander target.
func _start_dwell() -> void:
	var range_min: float = DWELL_OWN_ROOM_MIN_SEC
	var range_max: float = DWELL_OWN_ROOM_MAX_SEC
	match _current_category:
		CAT_SOCIAL:
			range_min = DWELL_SOCIAL_MIN_SEC
			range_max = DWELL_SOCIAL_MAX_SEC
		CAT_PROP:
			range_min = DWELL_PROP_MIN_SEC
			range_max = DWELL_PROP_MAX_SEC
		CAT_OTHER_ROOM:
			range_min = DWELL_OTHER_ROOM_MIN_SEC
			range_max = DWELL_OTHER_ROOM_MAX_SEC
		CAT_CORRIDOR:
			range_min = DWELL_CORRIDOR_MIN_SEC
			range_max = DWELL_CORRIDOR_MAX_SEC
		CAT_OWN_ROOM, _:
			range_min = DWELL_OWN_ROOM_MIN_SEC
			range_max = DWELL_OWN_ROOM_MAX_SEC
	var dwell_sec: float = _rng.randf_range(range_min, range_max)
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


## Test seam — read recency multiplier for a category.
func _test_get_recency(category: String) -> float:
	return float(_recency.get(category, 1.0))


## Test seam — read the last-picked category (drives dwell range).
func _test_get_current_category() -> String:
	return _current_category
