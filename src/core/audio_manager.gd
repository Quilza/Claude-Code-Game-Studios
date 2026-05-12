extends Node
##
## AudioManager — Foundation Autoload (second of two per ADR-0003).
##
## Wraps Godot's AudioServer: owns bus topology (Master → Music + SFX),
## an 8-slot AudioStreamPlayer pool for transient SFX, plus a dedicated
## music player. Stream-agnostic — callers resolve their own AudioStreams.
##
## Governing architecture:
##   • ADR-0003 (Autoload Scene Composition)            — Accepted
##   • ADR-0004 (Web Export Compatibility) + A1 audio   — Accepted (silent-stream unlock)
##   • ADR-0006 (Signal-Based Decoupling)               — Accepted
##
## GDD: design/gdd/audio-manager.md
##
## Persistence: per the C-9 ConfigLoader extension (manifest 2026-05-12.3),
## settings are read/written via ConfigurationLoader.get_setting / .set_setting
## rather than direct file I/O. Keys used:
##   audio.music_volume_db (float)
##   audio.sfx_volume_db   (float)
##   audio.muted           (bool)
##

# ─── Constants ───────────────────────────────────────────────────────────────

const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"

const SFX_POOL_SIZE: int = 8
const DEFAULT_MUSIC_VOLUME_DB: float = -18.0
const DEFAULT_SFX_VOLUME_DB: float = -12.0
const MIN_VOLUME_DB: float = -80.0
const MAX_VOLUME_DB: float = 6.0
const MUTED_VOLUME_DB: float = -80.0

const SETTING_MUSIC_VOLUME: String = "audio.music_volume_db"
const SETTING_SFX_VOLUME: String = "audio.sfx_volume_db"
const SETTING_MUTED: String = "audio.muted"

const SILENCE_UNLOCK_ASSET: String = "res://assets/audio/silence_50ms.ogg"


# ─── Internal state ──────────────────────────────────────────────────────────

var _music_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_volume_db: float = DEFAULT_MUSIC_VOLUME_DB
var _sfx_volume_db: float = DEFAULT_SFX_VOLUME_DB
var _muted: bool = false
var _volume_before_mute: Dictionary = {
	"music": DEFAULT_MUSIC_VOLUME_DB,
	"sfx": DEFAULT_SFX_VOLUME_DB,
}

# Web AudioContext unlock state (ADR-0004 A1)
var _web_unlock_player: AudioStreamPlayer = null
var _web_audio_unlocked: bool = false


# ─── Godot lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_buses()
	_instantiate_pool()
	_load_persisted_settings()
	_apply_volumes_to_buses()
	if OS.has_feature("web"):
		_prepare_web_unlock()


func _unhandled_input(event: InputEvent) -> void:
	# M key (per Audio Manager GDD Rule 6) — global mute toggle.
	if event.is_action_pressed(&"toggle_mute"):
		toggle_mute()
		get_viewport().set_input_as_handled()
		return
	# Web AudioContext unlock (ADR-0004 A1) — first user gesture only.
	if OS.has_feature("web") and not _web_audio_unlocked:
		var is_press: bool = (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed()
		if is_press:
			_unlock_web_audio_context()


# ─── Public API (per GDD §Public API surface) ────────────────────────────────

## Stops current music, plays new stream looped on the Music bus.
## Hard cut (no fade in MVP per AC-06).
func play_music(stream: AudioStream) -> void:
	if stream == null:
		push_error("[AudioManager] play_music received null stream")
		return
	if _music_player == null:
		push_warning("[AudioManager] play_music called before _ready() — ignored")
		return
	_music_player.stop()
	_music_player.stream = stream
	_music_player.play()


## Stops music player. Hard cut.
func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()


## Plays a one-shot SFX on the first available pool slot.
## Silently drops if pool exhausted (per AC-09 — push_warning logged).
## Rejects null streams with push_error (per AC-10).
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		push_error("[AudioManager] play_sfx received null stream")
		return
	for player: AudioStreamPlayer in _sfx_pool:
		if not player.playing:
			player.stream = stream
			player.play()
			return
	push_warning("[AudioManager] SFX pool exhausted — sound dropped")


## Stops every player in the pool. For scene transitions / emergency silence.
func stop_sfx_all() -> void:
	for player: AudioStreamPlayer in _sfx_pool:
		player.stop()


## Sets Music bus volume. Clamps to [MIN_VOLUME_DB, MAX_VOLUME_DB].
## Persists via ConfigLoader.set_setting per the C-9 extension.
func set_music_volume(db: float) -> void:
	var clamped: float = clampf(db, MIN_VOLUME_DB, MAX_VOLUME_DB)
	_music_volume_db = clamped
	if not _muted:
		_set_bus_volume(BUS_MUSIC, clamped)
	_persist_setting(SETTING_MUSIC_VOLUME, clamped)


## Sets SFX bus volume. Clamps to [MIN_VOLUME_DB, MAX_VOLUME_DB].
func set_sfx_volume(db: float) -> void:
	var clamped: float = clampf(db, MIN_VOLUME_DB, MAX_VOLUME_DB)
	_sfx_volume_db = clamped
	if not _muted:
		_set_bus_volume(BUS_SFX, clamped)
	_persist_setting(SETTING_SFX_VOLUME, clamped)


## Toggles global mute. On mute, captures current volumes for restore.
## On unmute, restores them (NOT the hardcoded defaults — per E6).
func toggle_mute() -> void:
	if _muted:
		# Unmute: restore from _volume_before_mute.
		_muted = false
		_set_bus_volume(BUS_MUSIC, float(_volume_before_mute.get("music", DEFAULT_MUSIC_VOLUME_DB)))
		_set_bus_volume(BUS_SFX, float(_volume_before_mute.get("sfx", DEFAULT_SFX_VOLUME_DB)))
	else:
		# Mute: capture current, set both to silence.
		_volume_before_mute = {
			"music": _music_volume_db,
			"sfx": _sfx_volume_db,
		}
		_muted = true
		_set_bus_volume(BUS_MUSIC, MUTED_VOLUME_DB)
		_set_bus_volume(BUS_SFX, MUTED_VOLUME_DB)
	_persist_setting(SETTING_MUTED, _muted)


# ─── Read-only accessors ────────────────────────────────────────────────────

func is_muted() -> bool:
	return _muted


func get_music_volume_db() -> float:
	return _music_volume_db


func get_sfx_volume_db() -> float:
	return _sfx_volume_db


func get_sfx_pool_size() -> int:
	return _sfx_pool.size()


# ─── Bus setup ──────────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	# Create Music + SFX buses under Master if absent.
	# Programmatic rather than .tres so this works on a fresh checkout
	# without a default_bus_layout.tres asset.
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		_add_bus_child_of_master(BUS_MUSIC)
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		_add_bus_child_of_master(BUS_SFX)


func _add_bus_child_of_master(bus_name: String) -> void:
	var new_idx: int = AudioServer.bus_count
	AudioServer.add_bus(new_idx)
	AudioServer.set_bus_name(new_idx, bus_name)
	AudioServer.set_bus_send(new_idx, BUS_MASTER)


func _set_bus_volume(bus_name: String, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("[AudioManager] _set_bus_volume: bus '%s' not found" % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, db)


# ─── Pool instantiation ─────────────────────────────────────────────────────

func _instantiate_pool() -> void:
	# 8 SFX pool players + 1 dedicated music player. All assigned to their bus.
	for i: int in SFX_POOL_SIZE:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "SfxPlayer_%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)


# ─── Persistence (via ConfigLoader per C-9 extension) ────────────────────────

func _load_persisted_settings() -> void:
	# ConfigurationLoader is the Autoload registered before AudioManager (per
	# project.godot autoload order). If for any reason it's not present,
	# fall back to defaults silently.
	if not _config_loader_available():
		push_warning("[AudioManager] ConfigurationLoader not available; using hardcoded defaults")
		return
	_music_volume_db = float(ConfigurationLoader.get_setting(SETTING_MUSIC_VOLUME, DEFAULT_MUSIC_VOLUME_DB))
	_sfx_volume_db = float(ConfigurationLoader.get_setting(SETTING_SFX_VOLUME, DEFAULT_SFX_VOLUME_DB))
	_muted = bool(ConfigurationLoader.get_setting(SETTING_MUTED, false))
	# If muted at startup, _volume_before_mute carries the previous session's
	# values so unmute restores them rather than the hardcoded defaults.
	if _muted:
		_volume_before_mute = {
			"music": _music_volume_db,
			"sfx": _sfx_volume_db,
		}


func _apply_volumes_to_buses() -> void:
	if _muted:
		_set_bus_volume(BUS_MUSIC, MUTED_VOLUME_DB)
		_set_bus_volume(BUS_SFX, MUTED_VOLUME_DB)
	else:
		_set_bus_volume(BUS_MUSIC, _music_volume_db)
		_set_bus_volume(BUS_SFX, _sfx_volume_db)


func _persist_setting(key: String, value: Variant) -> void:
	if not _config_loader_available():
		push_warning("[AudioManager] ConfigurationLoader unavailable; setting '%s' not persisted" % key)
		return
	ConfigurationLoader.set_setting(key, value)


func _config_loader_available() -> bool:
	# Detect whether the Autoload is reachable. Used so unit tests that
	# instantiate AudioManager standalone (without the full Autoload tree)
	# don't crash on ConfigurationLoader access.
	return Engine.has_singleton("ConfigurationLoader") or (
		get_tree() != null
		and get_tree().root != null
		and get_tree().root.has_node("ConfigurationLoader")
	)


# ─── Web AudioContext unlock (ADR-0004 A1) ───────────────────────────────────

func _prepare_web_unlock() -> void:
	# Per ADR-0004 A1 — preferred primary path is a zero-volume play() on a
	# silent stream. The original no-op set_bus_volume_db pattern is the
	# documented fallback because it relies on undocumented engine behaviour.
	# If the silent OGG asset isn't shipped yet, we skip the dedicated player
	# and rely on the first real sound to unlock (browsers auto-resume the
	# AudioContext on any AudioServer activity following a user gesture).
	if not ResourceLoader.exists(SILENCE_UNLOCK_ASSET):
		push_warning("[AudioManager] %s not found; web AudioContext unlock will use first real sound" % SILENCE_UNLOCK_ASSET)
		return
	var stream: AudioStream = load(SILENCE_UNLOCK_ASSET) as AudioStream
	if stream == null:
		push_warning("[AudioManager] %s failed to load as AudioStream; skipping unlock pre-arm" % SILENCE_UNLOCK_ASSET)
		return
	_web_unlock_player = AudioStreamPlayer.new()
	_web_unlock_player.name = "WebUnlockPlayer"
	_web_unlock_player.bus = BUS_MASTER
	_web_unlock_player.volume_db = MUTED_VOLUME_DB
	_web_unlock_player.stream = stream
	add_child(_web_unlock_player)


func _unlock_web_audio_context() -> void:
	if _web_audio_unlocked:
		return
	_web_audio_unlocked = true
	if _web_unlock_player != null:
		_web_unlock_player.play()
	else:
		# Fallback path: nudge the Master bus volume to itself. Per ADR-0004
		# this is documented as the fallback-fallback if the silence asset
		# can't ship; behaviour is engine-undocumented but observed to work.
		var idx: int = AudioServer.get_bus_index(BUS_MASTER)
		AudioServer.set_bus_volume_db(idx, AudioServer.get_bus_volume_db(idx))


# ─── Test-only seam ─────────────────────────────────────────────────────────

## Resets bus volumes and pool state to defaults. ONLY for use by GUT tests.
## Production code must not call this — it bypasses persistence.
func _test_reset() -> void:
	_music_volume_db = DEFAULT_MUSIC_VOLUME_DB
	_sfx_volume_db = DEFAULT_SFX_VOLUME_DB
	_muted = false
	_volume_before_mute = {"music": DEFAULT_MUSIC_VOLUME_DB, "sfx": DEFAULT_SFX_VOLUME_DB}
	_apply_volumes_to_buses()
	for player: AudioStreamPlayer in _sfx_pool:
		player.stop()
	if _music_player != null:
		_music_player.stop()
