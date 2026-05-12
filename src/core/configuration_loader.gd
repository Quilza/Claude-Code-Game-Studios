extends Node
##
## ConfigurationLoader — Foundation Autoload.
##
## Reads `config.json` at application startup. Provides agent registry,
## poll interval, protocol, and arbitrary-key get/set surface backed by
## `user://settings.json`.
##
## Governing architecture:
##   • ADR-0002 (Configuration Loading + Persistence)        — Accepted
##   • ADR-0003 (Autoload Scene Composition)                 — Accepted
##   • ADR-0004 (Web Export Compatibility)                   — Accepted (incl. A1)
##   • ADR-0008 (Mock Mode Strategy)                         — Accepted
##
## GDD: design/gdd/configuration-loader.md
## Manifest version: 2026-05-12.3
##
## State lifecycle (per GDD §Detailed Design):
##   UNINITIALIZED → LOADING → READY | CONFIG_MISSING | CONFIG_MALFORMED | CONFIG_INVALID
##   All non-READY states are terminal. App restart required.
##
## Signal contract:
##   config_loaded()                                — fires once when READY reached
##   config_load_failed(state: String, msg: String) — fires once on any error state
##   setting_changed(key: String, value: Variant)   — fires on every successful set_setting()
##

# ─── Signals ─────────────────────────────────────────────────────────────────

signal config_loaded
signal config_load_failed(state: String, message: String)
signal setting_changed(key: String, value: Variant)


# ─── State constants ─────────────────────────────────────────────────────────

const STATE_UNINITIALIZED: String = "UNINITIALIZED"
const STATE_LOADING: String = "LOADING"
const STATE_READY: String = "READY"
const STATE_CONFIG_MISSING: String = "CONFIG_MISSING"
const STATE_CONFIG_MALFORMED: String = "CONFIG_MALFORMED"
const STATE_CONFIG_INVALID: String = "CONFIG_INVALID"


# ─── Tuning constants (GDD §Tuning Knobs) ────────────────────────────────────

const DEFAULT_POLL_INTERVAL_SEC: float = 5.0
const MIN_POLL_INTERVAL_SEC: float = 1.0
const MAX_POLL_INTERVAL_SEC: float = 60.0
const MAX_AGENTS: int = 12
const MAX_DISPLAY_NAME_LENGTH: int = 48
const MAX_AGENT_ID_LENGTH: int = 32
const MIN_AGENT_ID_LENGTH: int = 1
const MAX_AGENT_TYPE_LENGTH: int = 32

const DEFAULT_PROTOCOL: String = "http_poll"
# Note: `var` not `const` because PackedStringArray() constructor isn't a
# constant expression in Godot 4.3+. UPPER_SNAKE_CASE preserves the "do not
# mutate" convention. (Const-friendly alternative `Array[String]` lacks
# `.join()` which we use below for error messages.)
var VALID_PROTOCOLS: PackedStringArray = PackedStringArray(["http_poll", "websocket"])
const DEFAULT_AGENT_TYPE: String = "default"
const DEFAULT_AUTH_TOKEN: String = ""

# Settings file backing arbitrary-key access (per C-9 extension 2026-05-12.3)
const USER_SETTINGS_PATH: String = "user://settings.json"


# ─── Per-platform config path resolution (GDD Rule 2) ────────────────────────

const CONFIG_FILENAME: String = "config.json"


# ─── Internal state ──────────────────────────────────────────────────────────

var _state: String = STATE_UNINITIALIZED
var _agents: Array[Dictionary] = []
var _poll_interval: float = DEFAULT_POLL_INTERVAL_SEC
var _protocol: String = DEFAULT_PROTOCOL
var _applied_defaults: Array[String] = []
var _is_mock: bool = false
var _web_mock_forced: bool = false
var _user_settings: Dictionary = {}
var _last_error_message: String = ""


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	_state = STATE_LOADING
	_load_user_settings()
	_load_config()
	# ADR-0004 A1 — web override (forces mock=true if config didn't already)
	if OS.has_feature("web") and not _is_mock:
		push_warning("[ConfigLoader] Web export forces mock=true (CORS); real-API config overridden per ADR-0004")
		_is_mock = true
		_web_mock_forced = true
	# Final state emission
	if _state == STATE_READY:
		config_loaded.emit()
	else:
		config_load_failed.emit(_state, _last_error_message)


# ─── Public getter API (GDD §Interactions) ───────────────────────────────────

## Returns the array of validated agent dictionaries.
## In any non-READY state, returns an empty array (safe default per AC-24).
func get_agents() -> Array[Dictionary]:
	if _state != STATE_READY:
		return [] as Array[Dictionary]
	# Return a shallow copy to prevent caller mutation per AC-25.
	var copy: Array[Dictionary] = []
	for entry: Dictionary in _agents:
		copy.append(entry.duplicate())
	return copy


## Returns one agent dictionary by id, or {} if not found.
func get_agent(id: String) -> Dictionary:
	if _state != STATE_READY:
		return {}
	for entry: Dictionary in _agents:
		if String(entry.get("id", "")) == id:
			return entry.duplicate()
	return {}


## Returns the configured poll interval in seconds.
## Default 5.0 in non-READY states (safe per AC-24).
func get_poll_interval() -> float:
	if _state != STATE_READY:
		return DEFAULT_POLL_INTERVAL_SEC
	return _poll_interval


## Returns the configured protocol string ("http_poll" or "websocket").
## Default "http_poll" in non-READY states (safe per AC-24).
func get_protocol() -> String:
	if _state != STATE_READY:
		return DEFAULT_PROTOCOL
	return _protocol


## Returns the list of optional field names that were defaulted during validation.
## Useful for diagnostics — Main Scene Bootstrap displays these.
func get_applied_defaults() -> Array[String]:
	return _applied_defaults.duplicate()


## Returns the current state string. Always safe to call.
func get_state() -> String:
	return _state


## True iff mock mode is active. Either via config.json's `mock: true`,
## OR via the ADR-0004 web override.
func is_mock() -> bool:
	return _is_mock


## True iff the ADR-0004 web override applied (config wanted real, web forced mock).
## Useful for a future demo-mode HUD badge.
func is_web_mock_forced() -> bool:
	return _web_mock_forced


# ─── Arbitrary-key access (C-9 extension, 2026-05-12.3) ─────────────────────

## Reads from user://settings.json with fallback to default.
## Future extension: union with entities.yaml read-only design constants.
func get_setting(key: String, default_value: Variant = null) -> Variant:
	if _user_settings.has(key):
		return _user_settings[key]
	# TODO(C-9 follow-up): consult entities.yaml as second-tier source.
	return default_value


## Writes to user://settings.json (atomic) and emits setting_changed.
## entities.yaml is read-only; this never writes there.
func set_setting(key: String, value: Variant) -> void:
	_user_settings[key] = value
	_save_user_settings()
	setting_changed.emit(key, value)


# ─── Config file loading + parsing ───────────────────────────────────────────

func _load_config() -> void:
	var config_path: String = _resolve_config_path()
	if not FileAccess.file_exists(config_path):
		_handle_missing_config(config_path)
		return

	var file: FileAccess = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		_enter_error(STATE_CONFIG_MISSING, "Could not open %s (OS error %d)" % [config_path, err])
		return

	var raw: String = file.get_as_text()
	file.close()

	# Whitespace-only or empty → MALFORMED per E.File-Access
	if raw.strip_edges().is_empty():
		_enter_error(STATE_CONFIG_MALFORMED, "Configuration file at %s is empty or whitespace-only" % config_path)
		return

	# UTF-8 BOM detection (E.File-Access)
	if raw.length() >= 3 and raw.unicode_at(0) == 0xFEFF:
		_enter_error(STATE_CONFIG_MALFORMED, "Configuration file at %s begins with a UTF-8 BOM. Re-save as UTF-8 without BOM." % config_path)
		return

	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null:
		_enter_error(STATE_CONFIG_MALFORMED, "Configuration file at %s is not valid JSON. Check for missing commas, unclosed braces, or invalid escape sequences." % config_path)
		return

	# JSON array root → INVALID, not MALFORMED (per E.Parse Errors)
	if not (parsed is Dictionary):
		_enter_error(STATE_CONFIG_INVALID, "Root of config.json must be a JSON object (got %s)." % typeof(parsed))
		return

	_validate_and_apply(parsed as Dictionary)


func _validate_and_apply(config: Dictionary) -> void:
	# Collect every error before reporting (per GDD Rule 5).
	var errors: Array[String] = []

	# Top-level: agents required
	if not config.has("agents"):
		errors.append("Required field 'agents' is missing.")
	elif not (config["agents"] is Array):
		errors.append("Field 'agents' must be a JSON array; got %s." % typeof(config["agents"]))

	# Top-level: mock (optional, bool)
	var declared_mock: bool = false
	if config.has("mock"):
		if not (config["mock"] is bool):
			errors.append("Field 'mock' must be a boolean; got %s." % typeof(config["mock"]))
		else:
			declared_mock = config["mock"] as bool

	# Top-level: poll_interval_sec (optional, float, range)
	var poll: float = DEFAULT_POLL_INTERVAL_SEC
	if config.has("poll_interval_sec"):
		var raw_poll: Variant = config["poll_interval_sec"]
		if not (raw_poll is float or raw_poll is int):
			errors.append("Field 'poll_interval_sec' must be a number; got %s." % typeof(raw_poll))
		else:
			poll = float(raw_poll)
			if poll < MIN_POLL_INTERVAL_SEC or poll > MAX_POLL_INTERVAL_SEC:
				errors.append("Field 'poll_interval_sec' = %f is out of range [%.1f, %.1f]." % [poll, MIN_POLL_INTERVAL_SEC, MAX_POLL_INTERVAL_SEC])
	else:
		_applied_defaults.append("poll_interval_sec")

	# Top-level: protocol (optional, enum)
	var protocol: String = DEFAULT_PROTOCOL
	if config.has("protocol"):
		var raw_proto: Variant = config["protocol"]
		if not (raw_proto is String):
			errors.append("Field 'protocol' must be a string; got %s." % typeof(raw_proto))
		else:
			protocol = String(raw_proto)
			if protocol not in VALID_PROTOCOLS:
				errors.append("Field 'protocol' = '%s' is not one of %s." % [protocol, ", ".join(VALID_PROTOCOLS)])
	else:
		_applied_defaults.append("protocol")

	# Per-agent validation (if agents array is well-formed enough to iterate)
	var validated_agents: Array[Dictionary] = []
	if config.has("agents") and config["agents"] is Array:
		var agents_array: Array = config["agents"] as Array
		if agents_array.is_empty():
			errors.append("Field 'agents' must contain at least 1 entry.")
		elif agents_array.size() > MAX_AGENTS:
			errors.append("Field 'agents' contains %d entries; maximum is %d." % [agents_array.size(), MAX_AGENTS])
		else:
			validated_agents = _validate_agents(agents_array, errors)

	# Slot conflict + auto-assignment (only if no errors so far for agents)
	if errors.is_empty():
		_assign_room_slots(validated_agents, errors)

	# Final disposition
	if not errors.is_empty():
		_enter_error(STATE_CONFIG_INVALID, "\n".join(errors))
		return

	_agents = validated_agents
	_poll_interval = poll
	_protocol = protocol
	_is_mock = declared_mock
	_state = STATE_READY


func _validate_agents(agents_array: Array, errors: Array[String]) -> Array[Dictionary]:
	var seen_ids: Dictionary = {}    # id (String) → first array-index seen
	var validated: Array[Dictionary] = []

	for i: int in agents_array.size():
		var raw_entry: Variant = agents_array[i]
		if not (raw_entry is Dictionary):
			errors.append("Entry at index %d in 'agents' is not a JSON object (got %s)." % [i, typeof(raw_entry)])
			continue
		var entry: Dictionary = raw_entry as Dictionary

		# Validate per-agent fields and collect errors
		var validated_entry: Dictionary = _validate_single_agent(entry, i, errors)
		# Track id duplicates regardless of other validation outcome
		var id_value: String = String(validated_entry.get("id", ""))
		if not id_value.is_empty():
			if seen_ids.has(id_value):
				errors.append("Agent id '%s' appears at index %d and index %d." % [id_value, seen_ids[id_value], i])
			else:
				seen_ids[id_value] = i
		validated.append(validated_entry)

	return validated


func _validate_single_agent(entry: Dictionary, index: int, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}

	# id (required, string, length, charset)
	if not entry.has("id"):
		errors.append("Agent at index %d is missing required field 'id'." % index)
	elif not (entry["id"] is String):
		errors.append("Agent at index %d 'id' must be a string." % index)
	else:
		var id_str: String = String(entry["id"])
		if id_str.length() < MIN_AGENT_ID_LENGTH or id_str.length() > MAX_AGENT_ID_LENGTH:
			errors.append("Agent at index %d 'id' length %d is out of range [%d, %d]." % [index, id_str.length(), MIN_AGENT_ID_LENGTH, MAX_AGENT_ID_LENGTH])
		elif not _is_valid_id_charset(id_str):
			errors.append("Agent at index %d 'id' must be alphanumeric + underscore only." % index)
		else:
			result["id"] = id_str

	# display_name (required, string, length)
	if not entry.has("display_name"):
		errors.append("Agent at index %d is missing required field 'display_name'." % index)
	elif not (entry["display_name"] is String):
		errors.append("Agent at index %d 'display_name' must be a string." % index)
	else:
		var name_str: String = String(entry["display_name"])
		if name_str.is_empty():
			errors.append("Agent at index %d 'display_name' must not be empty." % index)
		elif name_str.length() > MAX_DISPLAY_NAME_LENGTH:
			errors.append("Agent at index %d 'display_name' length %d exceeds max %d." % [index, name_str.length(), MAX_DISPLAY_NAME_LENGTH])
		else:
			result["display_name"] = name_str

	# endpoint_url (required, string, non-empty)
	if not entry.has("endpoint_url"):
		errors.append("Agent at index %d is missing required field 'endpoint_url'." % index)
	elif not (entry["endpoint_url"] is String):
		errors.append("Agent at index %d 'endpoint_url' must be a string." % index)
	else:
		var url: String = String(entry["endpoint_url"])
		if url.is_empty():
			errors.append("Agent at index %d 'endpoint_url' must not be empty." % index)
		# Loose URL validation — must contain a scheme separator.
		# Full URL parsing is delegated to HTTPRequest at use time.
		elif not (url.contains("://")):
			errors.append("Agent at index %d 'endpoint_url' = '%s' is not a valid URL (missing scheme)." % [index, url])
		else:
			result["endpoint_url"] = url

	# auth_token (optional, string OR null → empty)
	if entry.has("auth_token"):
		var raw_token: Variant = entry["auth_token"]
		if raw_token == null:
			result["auth_token"] = DEFAULT_AUTH_TOKEN
		elif raw_token is String:
			result["auth_token"] = String(raw_token)
		else:
			errors.append("Agent at index %d 'auth_token' must be a string or null." % index)
	else:
		result["auth_token"] = DEFAULT_AUTH_TOKEN

	# agent_type (optional, string, charset)
	if entry.has("agent_type"):
		var raw_type: Variant = entry["agent_type"]
		if not (raw_type is String):
			errors.append("Agent at index %d 'agent_type' must be a string." % index)
		else:
			var type_str: String = String(raw_type)
			if type_str.is_empty() or type_str.length() > MAX_AGENT_TYPE_LENGTH:
				errors.append("Agent at index %d 'agent_type' length %d is out of range." % [index, type_str.length()])
			elif not _is_valid_id_charset(type_str):
				errors.append("Agent at index %d 'agent_type' must be alphanumeric + underscore only." % index)
			else:
				result["agent_type"] = type_str
	else:
		result["agent_type"] = DEFAULT_AGENT_TYPE

	# room_slot (optional, int OR whole-number float)
	if entry.has("room_slot"):
		var raw_slot: Variant = entry["room_slot"]
		if raw_slot is int:
			var slot_int: int = int(raw_slot)
			if slot_int < 0 or slot_int >= MAX_AGENTS:
				errors.append("Agent at index %d 'room_slot' = %d is out of range [0, %d)." % [index, slot_int, MAX_AGENTS])
			else:
				result["room_slot"] = slot_int
		elif raw_slot is float:
			var slot_f: float = float(raw_slot)
			if slot_f != floor(slot_f):
				errors.append("Agent at index %d 'room_slot' = %f is not a whole number." % [index, slot_f])
			elif slot_f < 0.0 or slot_f >= float(MAX_AGENTS):
				errors.append("Agent at index %d 'room_slot' = %d is out of range [0, %d)." % [index, int(slot_f), MAX_AGENTS])
			else:
				result["room_slot"] = int(slot_f)
		else:
			errors.append("Agent at index %d 'room_slot' must be an integer." % index)

	return result


func _assign_room_slots(agents: Array[Dictionary], errors: Array[String]) -> void:
	# Step 1: collect explicit slot claims; detect conflicts.
	var explicit_slots: Dictionary = {}   # slot_int → first agent index that claimed it
	for i: int in agents.size():
		var entry: Dictionary = agents[i]
		if entry.has("room_slot"):
			var slot: int = int(entry["room_slot"])
			if explicit_slots.has(slot):
				var first_idx: int = explicit_slots[slot]
				errors.append("Agents at index %d and %d both claim room_slot %d." % [first_idx, i, slot])
			else:
				explicit_slots[slot] = i

	if not errors.is_empty():
		return

	# Step 2: auto-assign agents without room_slot, gap-filling.
	var occupied: Dictionary = {}
	for slot: int in explicit_slots.keys():
		occupied[slot] = true

	for i: int in agents.size():
		var entry: Dictionary = agents[i]
		if entry.has("room_slot"):
			continue
		var next_slot: int = -1
		for candidate: int in MAX_AGENTS:
			if not occupied.has(candidate):
				next_slot = candidate
				break
		if next_slot == -1:
			errors.append("Agent at index %d ('%s') has no room_slot and all %d slots are occupied by explicit assignments." % [i, String(entry.get("id", "?")), MAX_AGENTS])
			return
		agents[i]["room_slot"] = next_slot
		occupied[next_slot] = true


# ─── Helpers ────────────────────────────────────────────────────────────────

func _is_valid_id_charset(s: String) -> bool:
	# Alphanumeric + underscore only (per GDD per-agent schema).
	for c: String in s:
		var code: int = c.unicode_at(0)
		var is_lower: bool = code >= 97 and code <= 122
		var is_upper: bool = code >= 65 and code <= 90
		var is_digit: bool = code >= 48 and code <= 57
		var is_underscore: bool = code == 95
		if not (is_lower or is_upper or is_digit or is_underscore):
			return false
	return true


func _resolve_config_path() -> String:
	# In editor: project root. In exported builds: executable directory.
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + CONFIG_FILENAME)
	return OS.get_executable_path().get_base_dir().path_join(CONFIG_FILENAME)


func _handle_missing_config(config_path: String) -> void:
	# Attempt to write the template (one-shot; never overwrites existing).
	var template_written: bool = _write_template(config_path)
	var note: String = (" A template has been written to the path above. Edit it with your agent details and restart."
		if template_written
		else " Template generation failed (write permission denied). Create the file manually.")
	_enter_error(STATE_CONFIG_MISSING, "Configuration file not found at %s.%s" % [config_path, note])


func _write_template(config_path: String) -> bool:
	var template: Dictionary = {
		"_INSTRUCTIONS": "Edit this file with your AI agent details. Save and restart the bunker. See https://github.com/<repo>/blob/main/HOME.md for the full schema.",
		"agents": [
			{
				"id": "researcher",
				"display_name": "Researcher",
				"endpoint_url": "http://localhost:8080/status",
				"auth_token": "",
				"agent_type": "default"
			}
		],
		"poll_interval_sec": 5.0,
		"protocol": "http_poll"
	}
	var file: FileAccess = FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_warning("[ConfigLoader] Could not write template to %s" % config_path)
		return false
	# Godot 4.3 store_string returns void; 4.4+ returns bool. Code targets the
	# 4.3 baseline since that's the locally-installed version; success is
	# inferred from non-null FileAccess + successful close. Re-introduce
	# return-value check when the project upgrades to 4.6.2 per VERSION.md.
	file.store_string(JSON.stringify(template, "\t"))
	file.close()
	return true


func _enter_error(state: String, message: String) -> void:
	_state = state
	_last_error_message = message
	push_error("[ConfigLoader] %s: %s" % [state, message])


# ─── User settings (arbitrary-key) ──────────────────────────────────────────

func _load_user_settings() -> void:
	if not FileAccess.file_exists(USER_SETTINGS_PATH):
		_user_settings = {}
		return
	var file: FileAccess = FileAccess.open(USER_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_warning("[ConfigLoader] Could not open %s for reading" % USER_SETTINGS_PATH)
		_user_settings = {}
		return
	var raw: String = file.get_as_text()
	file.close()
	if raw.strip_edges().is_empty():
		_user_settings = {}
		return
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		_user_settings = parsed
	else:
		push_warning("[ConfigLoader] %s is not a JSON object; resetting to empty" % USER_SETTINGS_PATH)
		_user_settings = {}


func _save_user_settings() -> void:
	var file: FileAccess = FileAccess.open(USER_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[ConfigLoader] Could not write %s" % USER_SETTINGS_PATH)
		return
	# Godot 4.3 store_string returns void (4.4+ returns bool). See _write_template.
	file.store_string(JSON.stringify(_user_settings, "\t"))
	file.close()
