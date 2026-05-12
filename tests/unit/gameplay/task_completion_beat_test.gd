extends GutTest
##
## TaskCompletionBeat — unit tests.
##
## Covers the signal-emission + registry-lookup paths. Tween + AudioManager
## integration is tested at the integration level (real audio device).
##

const TCBScript = preload("res://src/gameplay/task_completion_beat.gd")


# ─── Constants ──────────────────────────────────────────────────────────────

func test_beat_total_duration_equals_1_5_sec() -> void:
	# Per Rule 3 — must match TR-hud-004 + beat_total_seconds
	assert_almost_eq(TCBScript.BEAT_TOTAL_SEC, 1.5, 0.0001)


func test_attack_hold_decay_phases_sum_to_total() -> void:
	var sum: float = TCBScript.BEAT_ATTACK_SEC + TCBScript.BEAT_HOLD_SEC + TCBScript.BEAT_DECAY_SEC
	assert_almost_eq(sum, TCBScript.BEAT_TOTAL_SEC, 0.0001)


# ─── Sound registry ─────────────────────────────────────────────────────────

func test_register_sound_makes_has_sound_true() -> void:
	var tcb: Node = TCBScript.new()
	var s: AudioStreamGenerator = AudioStreamGenerator.new()
	tcb.register_sound("default", s)
	assert_true(tcb.has_sound("default"))
	tcb.free()


func test_has_sound_with_default_fallback() -> void:
	# If "default" is registered, any agent_type query returns true.
	var tcb: Node = TCBScript.new()
	var s: AudioStreamGenerator = AudioStreamGenerator.new()
	tcb.register_sound("default", s)
	assert_true(tcb.has_sound("researcher"), "Falls back to default")
	tcb.free()


func test_has_sound_without_default_or_specific_returns_false() -> void:
	var tcb: Node = TCBScript.new()
	assert_false(tcb.has_sound("researcher"))
	tcb.free()


func test_resolve_stream_prefers_specific_agent_type() -> void:
	var tcb: Node = TCBScript.new()
	var s_default: AudioStreamGenerator = AudioStreamGenerator.new()
	s_default.buffer_length = 0.05
	var s_specific: AudioStreamGenerator = AudioStreamGenerator.new()
	s_specific.buffer_length = 0.10
	tcb.register_sound("default", s_default)
	tcb.register_sound("researcher", s_specific)
	var result: AudioStream = tcb._resolve_stream("researcher")
	assert_eq(result, s_specific, "Specific agent_type wins over default")
	tcb.free()


func test_resolve_stream_falls_back_to_default() -> void:
	var tcb: Node = TCBScript.new()
	var s_default: AudioStreamGenerator = AudioStreamGenerator.new()
	tcb.register_sound("default", s_default)
	var result: AudioStream = tcb._resolve_stream("unknown_type")
	assert_eq(result, s_default, "Falls back to default")
	tcb.free()


func test_resolve_stream_no_registry_returns_null() -> void:
	var tcb: Node = TCBScript.new()
	var result: AudioStream = tcb._resolve_stream("anything")
	assert_null(result)
	tcb.free()


# ─── beat_fired signal emission ──────────────────────────────────────────────

func test_beat_fired_emits_with_agent_id_and_timestamp() -> void:
	var tcb: Node = TCBScript.new()
	add_child(tcb)
	var emitted: Array = []
	tcb.beat_fired.connect(func(agent_id: String, ts: float) -> void:
		emitted.append([agent_id, ts])
	)
	tcb._on_task_completed("test_agent")
	assert_eq(emitted.size(), 1)
	assert_eq(String(emitted[0][0]), "test_agent")
	var ts: float = float(emitted[0][1])
	# Timestamp should be a recent unix time (greater than 2024-01-01 epoch).
	assert_gt(ts, 1704067200.0, "Timestamp should be a recent unix time")
	tcb.queue_free()


# ─── _resolve_agent_type ─────────────────────────────────────────────────────

func test_resolve_agent_type_returns_default_when_config_loader_absent() -> void:
	# In test isolation (no full autoload tree), ConfigLoader may not be
	# reachable. Should gracefully return "default".
	var tcb: Node = TCBScript.new()
	var result: String = tcb._resolve_agent_type("some_id")
	assert_eq(result, TCBScript.DEFAULT_AGENT_TYPE)
	tcb.free()
