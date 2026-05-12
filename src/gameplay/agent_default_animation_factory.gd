class_name AgentDefaultAnimationFactory extends RefCounted
##
## AgentDefaultAnimationFactory — Presentation layer.
##
## Programmatic placeholder `AnimationLibrary` for agent characters.
## Constructs the 4 animations specified in ADR-0009 §"Shared Asset:
## AnimationLibrary" in code, targeting modulate / scale on a child
## node named "Body".
##
## Governing architecture:
##   • ADR-0009 (AnimationPlayer Strategy) — placeholder library acceptable
##     for early stub work (§345)
##
## Replace this factory with `load("res://assets/animations/agent_default.tres")`
## once authored AnimationLibrary assets land. The factory's output shape
## (4 named anims, identical loop modes + durations) matches the spec so the
## swap is a one-line change in ACC.
##
## Per ADR-0009 §"Per-agent-type variants": agent_type selects a body color
## here (placeholder for sprite variation). Real variants will swap the
## entire library asset.
##

# ─── Animation names (must match ADR-0009 §ASM State → Animation Dispatch) ───

const ANIM_IDLE: StringName = &"idle"
const ANIM_WORKING: StringName = &"working"
const ANIM_COMPLETED: StringName = &"completed"
const ANIM_ERRORED: StringName = &"errored"


# ─── Animation durations (per ADR-0009 §Shared Asset table) ──────────────────

const DURATION_IDLE_SEC: float = 1.2
const DURATION_WORKING_SEC: float = 0.6
const DURATION_COMPLETED_SEC: float = 0.5
const DURATION_ERRORED_SEC: float = 1.5


# ─── Body target path (relative to AnimationPlayer.root_node) ────────────────

## The placeholder visual is named "Body" — animations target its
## `modulate` and `scale` properties. AnimationPlayer's `root_node` defaults
## to its parent (the ACC); NodePaths in animation tracks are evaluated from
## that root. So "Body:modulate" means "ACC's Body child's modulate". Verified
## by the runtime warning "couldn't resolve track" when path was set to
## "../Body:modulate" — it walked one level too high.
const BODY_NODE_PATH: NodePath = ^"Body:modulate"
const BODY_SCALE_PATH: NodePath = ^"Body:scale"


# ─── Per-agent-type body colors (placeholder palette) ────────────────────────

## ACC reads `agent_type` from ConfigurationLoader and looks up this dict
## to color its placeholder body. Real sprite variants supersede this
## entirely. Falls back to DEFAULT_BODY_COLOR for unknown types.
const DEFAULT_BODY_COLOR: Color = Color8(0xB0, 0xB0, 0xB0)   # neutral gray
const AGENT_TYPE_COLORS: Dictionary = {
	"default": Color8(0xB0, 0xB0, 0xB0),
	"researcher": Color8(0x6B, 0x9F, 0xD4),    # cool blue
	"marketing": Color8(0xD4, 0x88, 0x2A),     # amber
	"engineer": Color8(0x5B, 0xAD, 0x63),      # green
}


# ─── Public API ──────────────────────────────────────────────────────────────

## Returns an AnimationLibrary populated with the 4 ADR-0009 animations.
## Caller adds it to an AnimationPlayer via
## `player.add_animation_library(&"", lib)`.
static func build_placeholder_library() -> AnimationLibrary:
	var lib: AnimationLibrary = AnimationLibrary.new()
	lib.add_animation(ANIM_IDLE, _build_idle_anim())
	lib.add_animation(ANIM_WORKING, _build_working_anim())
	lib.add_animation(ANIM_COMPLETED, _build_completed_anim())
	lib.add_animation(ANIM_ERRORED, _build_errored_anim())
	return lib


## Returns the body color for a given agent_type. Used by ACC to tint
## its placeholder ColorRect. Unknown agent_type → DEFAULT_BODY_COLOR.
static func body_color_for_agent_type(agent_type: String) -> Color:
	return AGENT_TYPE_COLORS.get(agent_type, DEFAULT_BODY_COLOR)


# ─── Animation builders ──────────────────────────────────────────────────────

## `idle` — gentle alpha pulse 0.85 ↔ 1.0. Loops. Signals "agent is
## present but not busy". Modulate is the only animated property.
static func _build_idle_anim() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = DURATION_IDLE_SEC
	anim.loop_mode = Animation.LOOP_LINEAR
	var track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, BODY_NODE_PATH)
	anim.track_insert_key(track, 0.0, Color(1, 1, 1, 1.0))
	anim.track_insert_key(track, DURATION_IDLE_SEC * 0.5, Color(1, 1, 1, 0.85))
	anim.track_insert_key(track, DURATION_IDLE_SEC, Color(1, 1, 1, 1.0))
	return anim


## `working` — green-tinted pulse Color(0.7,1,0.7) ↔ white. Faster than
## idle. Signals "agent is processing". Loops.
static func _build_working_anim() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = DURATION_WORKING_SEC
	anim.loop_mode = Animation.LOOP_LINEAR
	var track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, BODY_NODE_PATH)
	anim.track_insert_key(track, 0.0, Color(1, 1, 1, 1.0))
	anim.track_insert_key(track, DURATION_WORKING_SEC * 0.5, Color(0.7, 1.0, 0.7, 1.0))
	anim.track_insert_key(track, DURATION_WORKING_SEC, Color(1, 1, 1, 1.0))
	return anim


## `completed` — bright green flash + scale bump 1.0 → 1.2 → 1.0. One-shot
## (LOOP_NONE). On `animation_finished("completed")`, ACC reverts to idle
## per ADR-0009 §"One-Shot Animation Revert".
static func _build_completed_anim() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = DURATION_COMPLETED_SEC
	anim.loop_mode = Animation.LOOP_NONE
	# Modulate track — bright green flash
	var modulate_track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(modulate_track, BODY_NODE_PATH)
	anim.track_insert_key(modulate_track, 0.0, Color(1, 1, 1, 1.0))
	anim.track_insert_key(modulate_track, DURATION_COMPLETED_SEC * 0.2, Color(0.6, 1.4, 0.6, 1.0))
	anim.track_insert_key(modulate_track, DURATION_COMPLETED_SEC, Color(1, 1, 1, 1.0))
	# Scale track — bump 1.0 → 1.2 → 1.0
	var scale_track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(scale_track, BODY_SCALE_PATH)
	anim.track_insert_key(scale_track, 0.0, Vector2.ONE)
	anim.track_insert_key(scale_track, DURATION_COMPLETED_SEC * 0.3, Vector2(1.2, 1.2))
	anim.track_insert_key(scale_track, DURATION_COMPLETED_SEC, Vector2.ONE)
	return anim


## `errored` — slow red pulse Color(1,0.4,0.4) ↔ Color(0.6,0.2,0.2). Loops.
## Distress signal. Visually distinct from idle (red) and working (green).
static func _build_errored_anim() -> Animation:
	var anim: Animation = Animation.new()
	anim.length = DURATION_ERRORED_SEC
	anim.loop_mode = Animation.LOOP_LINEAR
	var track: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, BODY_NODE_PATH)
	anim.track_insert_key(track, 0.0, Color(1.0, 0.4, 0.4, 1.0))
	anim.track_insert_key(track, DURATION_ERRORED_SEC * 0.5, Color(0.6, 0.2, 0.2, 1.0))
	anim.track_insert_key(track, DURATION_ERRORED_SEC, Color(1.0, 0.4, 0.4, 1.0))
	return anim
