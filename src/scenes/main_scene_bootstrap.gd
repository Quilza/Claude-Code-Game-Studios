extends Node
##
## MainSceneBootstrap — Architecture layer.
##
## Wires the 10 implemented MVP systems into a runnable bunker. Attached
## to the root of Main.tscn. _ready() runs after both Autoloads have
## completed.
##
## GDD: design/gdd/main-scene-bootstrap.md
##
## Bootstrap sequence (per GDD §3.3 Rule 6):
##   ConfigurationLoader.READY check (gate)
##   → DataBridge (Main child)
##   → AgentStateMachine (Main child)
##   → RoomSystem (WorldRoot child)
##   → AgentCharacterController × N (WorldRoot children)
##   → AmbientAnimationLayer (WorldRoot child)
##   → TaskCompletionBeat (WorldRoot child)
##   → CommandersRoomHUD (HudLayer child)
##   → call_deferred("_perform_initial_wiring") — fires assignments + reveals WorldRoot
##

# ─── Constants ───────────────────────────────────────────────────────────────

const ERROR_SCENE_PATH: String = "res://src/ui/scenes/PreBunkerError.tscn"

const AMBIENT_MUSIC_SETTING_KEY: String = "bootstrap.ambient_music_path"
const AMBIENT_MUSIC_DEFAULT_PATH: String = "res://assets/audio/ambient.ogg"

const FADE_IN_SETTING_KEY: String = "bootstrap.fade_in_sec"
const FADE_IN_DEFAULT_SEC: float = 0.2

# Production-mode script preloads (load() at runtime for graceful asset-missing handling)
const DATA_BRIDGE_SCRIPT: String = "res://src/integration/data_bridge.gd"
const ASM_SCRIPT: String = "res://src/integration/agent_state_machine.gd"
const ROOM_SYSTEM_SCRIPT: String = "res://src/core/room_system.gd"
const ACC_SCRIPT: String = "res://src/gameplay/agent_character_controller.gd"
const AAL_SCRIPT: String = "res://src/gameplay/ambient_animation_layer.gd"
const TCB_SCRIPT: String = "res://src/gameplay/task_completion_beat.gd"
const HUD_SCRIPT: String = "res://src/ui/commanders_room_hud.gd"


# ─── Scene-authored sub-roots ────────────────────────────────────────────────

@onready var world_root: Node2D = $WorldRoot
@onready var hud_layer: CanvasLayer = $HudLayer
@onready var overlay_layer: CanvasLayer = $OverlayLayer if has_node("OverlayLayer") else null
# TileMapRenderer is authored as a child of WorldRoot in Main.tscn; resolved
# lazily so unit tests can run with a mock-built scene.
@onready var tile_map_renderer: TileMapRenderer = world_root.get_node_or_null("TileMapRenderer")


# ─── Instantiated system refs (populated during composition) ────────────────

var _data_bridge: Node = null
var _agent_state_machine: Node = null
var _room_system: Node = null
var _ambient_animation_layer: Node = null
var _task_completion_beat: Node = null
var _commanders_room_hud: Node = null
var _agent_character_controllers: Array[Node] = []


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	# Per Rule 3: hide WorldRoot until composition completes.
	if world_root != null:
		world_root.visible = false

	# Per Rule 2: gate on ConfigurationLoader state.
	if not _config_loader_available():
		push_error("[Bootstrap] ConfigurationLoader Autoload not found — cannot proceed")
		_swap_to_error_scene()
		return

	if ConfigurationLoader.get_state() != ConfigurationLoader.STATE_READY:
		_swap_to_error_scene()
		return

	# Compose the scene
	_instantiate_systems()
	_instantiate_agent_character_controllers()
	# Per Rule 10: defer wiring so all _ready() calls complete first
	call_deferred("_perform_initial_wiring")


# ─── System instantiation (per Rule 6) ───────────────────────────────────────

func _instantiate_systems() -> void:
	# Order matters — earlier systems are wired as @export refs into later ones.

	# 1. DataBridge → Main child (sibling of WorldRoot)
	_data_bridge = _instantiate_script(DATA_BRIDGE_SCRIPT, "DataBridge")
	if _data_bridge != null:
		add_child(_data_bridge)

	# 2. AgentStateMachine → Main child
	_agent_state_machine = _instantiate_script(ASM_SCRIPT, "AgentStateMachine")
	if _agent_state_machine != null:
		add_child(_agent_state_machine)

	# 3. RoomSystem → WorldRoot child
	_room_system = _instantiate_script(ROOM_SYSTEM_SCRIPT, "RoomSystem")
	if _room_system != null:
		_room_system.tile_map_renderer = tile_map_renderer
		world_root.add_child(_room_system)

	# 4. (ACC × N — separate loop in _instantiate_agent_character_controllers)

	# 5. AmbientAnimationLayer → WorldRoot child
	_ambient_animation_layer = _instantiate_script(AAL_SCRIPT, "AmbientAnimationLayer")
	if _ambient_animation_layer != null:
		_ambient_animation_layer.agent_state_machine = _agent_state_machine
		_ambient_animation_layer.room_system = _room_system
		world_root.add_child(_ambient_animation_layer)

	# 6. TaskCompletionBeat → WorldRoot child
	_task_completion_beat = _instantiate_script(TCB_SCRIPT, "TaskCompletionBeat")
	if _task_completion_beat != null:
		_task_completion_beat.agent_state_machine = _agent_state_machine
		_task_completion_beat.room_system = _room_system
		world_root.add_child(_task_completion_beat)

	# 7. CommandersRoomHUD → HudLayer child
	_commanders_room_hud = _instantiate_script(HUD_SCRIPT, "CommandersRoomHUD")
	if _commanders_room_hud != null:
		_commanders_room_hud.agent_state_machine = _agent_state_machine
		_commanders_room_hud.data_bridge = _data_bridge
		_commanders_room_hud.task_completion_beat = _task_completion_beat
		_commanders_room_hud.room_system = _room_system
		_commanders_room_hud.overlay_layer = overlay_layer   # for detail-overlay parenting
		hud_layer.add_child(_commanders_room_hud)
	# Show OverlayLayer (Main.tscn sets it visible=false by default; HUD code controls its content)
	if overlay_layer != null:
		overlay_layer.visible = true


func _instantiate_agent_character_controllers() -> void:
	# Per Rule 8: programmatic loop over ConfigurationLoader.get_agents().
	if not ResourceLoader.exists(ACC_SCRIPT):
		push_error("[Bootstrap] %s missing — agents will not render" % ACC_SCRIPT)
		return
	var agents: Array[Dictionary] = ConfigurationLoader.get_agents()
	for i: int in agents.size():
		var agent: Dictionary = agents[i]
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			continue
		var acc: Node = _instantiate_script(ACC_SCRIPT, "ACC_%s" % id)
		if acc == null:
			continue
		acc.agent_id = id
		acc.agent_index = i
		acc.agent_state_machine = _agent_state_machine
		acc.room_system = _room_system
		acc.tile_map_renderer = tile_map_renderer
		# acc.animation_player remains null until per-agent .tscn template lands
		world_root.add_child(acc)
		_agent_character_controllers.append(acc)


# ─── Deferred wiring (per Rule 10) ───────────────────────────────────────────

func _perform_initial_wiring() -> void:
	# Assign each configured agent to the agent room (per RoomSystem Rule 6).
	if _room_system != null and _config_loader_available():
		var agents: Array[Dictionary] = ConfigurationLoader.get_agents()
		# Use the RoomSystem.AGENT_ROOM_ID constant per ADR-0001 type contract.
		var agent_room_id: StringName = _room_system.AGENT_ROOM_ID
		for agent: Dictionary in agents:
			var id: String = String(agent.get("id", ""))
			if id.is_empty():
				continue
			_room_system.assign_agent(agent_room_id, id)

	# Begin ambient music per Q6 (optional asset).
	_begin_ambient_music()

	# Show WorldRoot — composition complete.
	if world_root != null:
		world_root.visible = true


# ─── Ambient music (per Rule 11 + Q6) ────────────────────────────────────────

func _begin_ambient_music() -> void:
	if not _audio_manager_available():
		return
	var path: String = AMBIENT_MUSIC_DEFAULT_PATH
	if _config_loader_available():
		path = String(ConfigurationLoader.get_setting(AMBIENT_MUSIC_SETTING_KEY, AMBIENT_MUSIC_DEFAULT_PATH))
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		push_warning("[Bootstrap] ambient music asset not found at %s; running silent" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		push_warning("[Bootstrap] %s failed to load as AudioStream" % path)
		return
	AudioManager.play_music(stream)


# ─── Error scene swap (per Rule 12) ──────────────────────────────────────────

func _swap_to_error_scene() -> void:
	if not ResourceLoader.exists(ERROR_SCENE_PATH):
		push_error("[Bootstrap] %s missing — error scene cannot be shown" % ERROR_SCENE_PATH)
		return
	# Deferred — `change_scene_to_file` inside `_ready()` triggers
	# "Parent node is busy adding/removing children" because we're
	# still mid-tree-construction. Defer to the next idle frame.
	get_tree().call_deferred("change_scene_to_file", ERROR_SCENE_PATH)


# ─── Helpers ────────────────────────────────────────────────────────────────

func _instantiate_script(script_path: String, node_name: String) -> Node:
	if not ResourceLoader.exists(script_path):
		push_error("[Bootstrap] %s missing" % script_path)
		return null
	var script: Script = load(script_path) as Script
	if script == null:
		push_error("[Bootstrap] %s failed to load as Script" % script_path)
		return null
	var node: Node = script.new()
	node.name = node_name
	return node


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


# ─── Test-only seam ─────────────────────────────────────────────────────────

## Returns the ACC instance for a given agent_id, or null. For integration tests.
func _test_get_acc(agent_id: String) -> Node:
	for acc: Node in _agent_character_controllers:
		if acc.agent_id == agent_id:
			return acc
	return null


func _test_get_acc_count() -> int:
	return _agent_character_controllers.size()
