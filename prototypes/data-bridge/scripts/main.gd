extends Node
##
## Sprint 1 prototype — Main scene entry point.
##
## Wires ConfigurationLoader (autoload) + DataBridge + per-agent
## AgentStatusLabel UI. No production scene structure — bypasses ADR-0011's
## CanvasLayer topology entirely. This is prototype-tier code.
##

@onready var _bridge: DataBridge = $DataBridge
@onready var _agents_container: VBoxContainer = $UI/AgentsContainer
@onready var _header: Label = $UI/Header


func _ready() -> void:
	_header.text = _build_header()
	_spawn_agent_labels()


func _build_header() -> String:
	var mode: String = "MOCK" if ConfigurationLoader.is_mock() else "REAL API"
	if ConfigurationLoader.is_web_mock_forced():
		mode = "MOCK (web-forced)"
	var agent_count: int = ConfigurationLoader.get_agents().size()
	return "Sprint 1 — Data Bridge Prototype\nMode: %s   Agents: %d" % [mode, agent_count]


func _spawn_agent_labels() -> void:
	for agent: Dictionary in ConfigurationLoader.get_agents():
		var id: String = String(agent.get("id", ""))
		if id.is_empty():
			continue
		var label_scene: PackedScene = preload("res://AgentStatusLabel.tscn")
		var label: AgentStatusLabel = label_scene.instantiate()
		label.agent_id = id
		_agents_container.add_child(label)


func _input(event: InputEvent) -> void:
	# Press Q to quit (prototype convenience)
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_Q:
		get_tree().quit()
