extends Node
##
## Sprint 1 prototype — minimal ConfigurationLoader.
##
## Mirrors the contract from ADR-0002 + ADR-0008 + ADR-0004 enough for the
## Data Bridge prototype to run. Not the full production version — no
## settings persistence, no schema versioning, no signal emission. Just the
## subset the DataBridge needs to start polling.
##
## Production version: see ADR-0002.
##

const CONFIG_PATH: String = "res://config.json"
const CONFIG_USER_PATH: String = "user://config.json"

var _config: Dictionary = {}
var _is_loaded: bool = false


func _ready() -> void:
	_load_config()
	# ADR-0004 web override — even prototype must respect this
	if OS.has_feature("web") and not _config.get("mock", false):
		push_warning("[ConfigLoader] Web export forces mock=true (CORS); real-API config ignored")
		_config["mock"] = true
		_config["web_mock_forced"] = true


func _load_config() -> void:
	# Try user:// first (user's local copy with their real token), then res:// fallback
	var paths: Array[String] = [CONFIG_USER_PATH, CONFIG_PATH]
	for path: String in paths:
		if FileAccess.file_exists(path):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file == null:
				push_warning("[ConfigLoader] Could not open %s" % path)
				continue
			var raw: String = file.get_as_text()
			file.close()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				_config = parsed
				_is_loaded = true
				print("[ConfigLoader] Loaded config from %s" % path)
				return
			else:
				push_error("[ConfigLoader] Invalid JSON in %s" % path)
	# Test-mode fallback per ADR-0002 — mock mode with one agent
	_config = _test_mode_default()
	_is_loaded = true
	print("[ConfigLoader] No config file found — using test-mode default (mock=true)")


func _test_mode_default() -> Dictionary:
	return {
		"schema_version": 1,
		"mock": true,
		"agents": [
			{
				"id": "claude_dev",
				"agent_type": "default",
				"display_name": "Claude (mock)",
				"endpoint": "",
				"token": "",
				"poll_interval": 5.0
			}
		]
	}


func is_mock() -> bool:
	return _config.get("mock", false)


func get_agents() -> Array:
	return _config.get("agents", [])


func get_agent(id: String) -> Dictionary:
	for agent: Dictionary in get_agents():
		if String(agent.get("id", "")) == id:
			return agent
	return {}


func is_web_mock_forced() -> bool:
	return _config.get("web_mock_forced", false)
