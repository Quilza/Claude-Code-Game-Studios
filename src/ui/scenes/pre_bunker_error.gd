extends Control
##
## PreBunkerError — pre-bunker error scene script.
##
## Renders when ConfigurationLoader fails to reach READY state. Reads its
## content from ConfigurationLoader's public state.
##
## GDD: design/gdd/main-scene-bootstrap.md §3.7
##

@onready var state_label: Label = $Margin/VStack/StateLabel
@onready var message_label: Label = $Margin/VStack/MessageLabel
@onready var path_label: Label = $Margin/VStack/PathLabel


func _ready() -> void:
	if not _config_loader_available():
		state_label.text = "ConfigurationLoader unavailable"
		message_label.text = "The application could not access its configuration system."
		path_label.text = ""
		return

	var state: String = ConfigurationLoader.get_state()
	state_label.text = _human_label_for_state(state)
	message_label.text = String(ConfigurationLoader._last_error_message)
	path_label.text = "Config path: %s" % _resolved_config_path()


func _human_label_for_state(state: String) -> String:
	match state:
		"CONFIG_MISSING":
			return "Configuration missing"
		"CONFIG_MALFORMED":
			return "Configuration malformed"
		"CONFIG_INVALID":
			return "Configuration invalid"
		_:
			return "Configuration error: %s" % state


func _resolved_config_path() -> String:
	# Mirror ConfigurationLoader._resolve_config_path() for display
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://config.json")
	return OS.get_executable_path().get_base_dir().path_join("config.json")


func _config_loader_available() -> bool:
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)
