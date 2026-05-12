extends RefCounted
##
## Test fixtures for Agent State Machine tests.
##
## Per ADR-0014 (test framework) + design/gdd/agent-state-machine.md §8.9.
## Use these helpers in GUT tests to avoid duplicating payload-construction
## boilerplate. All payloads return raw JSON String (the format Data Bridge
## emits per ADR-0001 single-writer rule).
##
## Naming convention:
##   payload_<scenario>(...) -> String
## Examples:
##   payload_end_turn()          → completed
##   payload_max_tokens()        → completed (max_tokens path)
##   payload_tool_use()          → working
##   payload_refusal()           → errored
##   payload_error_envelope()    → errored (Anthropic error shape)
##   payload_malformed()         → errored (parse failure)
##
## Each fixture is deterministic (no random IDs, no timestamps in content)
## so test assertions can compare expected output byte-for-byte where useful.
##
## When ASM implementation begins, this helper file enables AC-1 through
## AC-9 GUT tests to be written without copy-pasting JSON literals.
##

class_name AsmFixtures


# ───── Successful payloads (one per stop_reason) ─────

static func payload_end_turn(text: String = "ok") -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_end_turn",
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": text}],
		"stop_reason": "end_turn",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {
			"input_tokens": 8,
			"output_tokens": 5,
			"cache_creation_input_tokens": 0,
			"cache_read_input_tokens": 0
		}
	})


static func payload_max_tokens() -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_max_tokens",
		"type": "message",
		"role": "assistant",
		"content": [],   # empty per the prototype's observed max_tokens=1 path
		"stop_reason": "max_tokens",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {
			"input_tokens": 8,
			"output_tokens": 1,
			"cache_creation_input_tokens": 0,
			"cache_read_input_tokens": 0
		}
	})


static func payload_stop_sequence(sequence: String = "STOP") -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_stop_seq",
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": "partial response"}],
		"stop_reason": "stop_sequence",
		"stop_sequence": sequence,
		"stop_details": null,
		"usage": {"input_tokens": 8, "output_tokens": 3}
	})


static func payload_tool_use(tool_name: String = "test_tool") -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_tool_use",
		"type": "message",
		"role": "assistant",
		"content": [
			{
				"type": "tool_use",
				"id": "toolu_test_001",
				"name": tool_name,
				"input": {}
			}
		],
		"stop_reason": "tool_use",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {"input_tokens": 14, "output_tokens": 12}
	})


static func payload_pause_turn() -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_pause",
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": "thinking..."}],
		"stop_reason": "pause_turn",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {"input_tokens": 14, "output_tokens": 4}
	})


static func payload_refusal() -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_refusal",
		"type": "message",
		"role": "assistant",
		"content": [],
		"stop_reason": "refusal",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {"input_tokens": 14, "output_tokens": 0}
	})


# ───── Error payloads ─────

static func payload_error_envelope(error_type: String = "invalid_request_error",
		message: String = "test error message") -> String:
	# Anthropic error response shape — observed empirically in Sprint 1 prototype
	return JSON.stringify({
		"type": "error",
		"error": {
			"type": error_type,
			"message": message
		},
		"request_id": "req_test_error_envelope"
	})


static func payload_malformed() -> String:
	# Not valid JSON — ASM should JSON.parse_string this and get null
	return "{not-valid-json"


static func payload_empty() -> String:
	return ""


static func payload_unknown_stop_reason(unknown_value: String = "future_unknown_value") -> String:
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_unknown",
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": "response"}],
		"stop_reason": unknown_value,
		"stop_sequence": null,
		"stop_details": null,
		"usage": {"input_tokens": 8, "output_tokens": 1}
	})


# ───── Payload variants for accumulation tests ─────

static func payload_end_turn_with_usage(input_tokens: int, output_tokens: int) -> String:
	# For AC-25 token accumulation tests
	return JSON.stringify({
		"model": "claude-haiku-4-5-20251001",
		"id": "msg_test_usage_" + str(input_tokens) + "_" + str(output_tokens),
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": "ok"}],
		"stop_reason": "end_turn",
		"stop_sequence": null,
		"stop_details": null,
		"usage": {
			"input_tokens": input_tokens,
			"output_tokens": output_tokens
		}
	})


static func payload_missing_usage() -> String:
	# For AC-25 negative case — usage block omitted (some providers may not include it)
	return JSON.stringify({
		"model": "non-anthropic-provider",
		"id": "msg_no_usage",
		"type": "message",
		"role": "assistant",
		"content": [{"type": "text", "text": "ok"}],
		"stop_reason": "end_turn"
		# no usage field
	})


# ───── Config fixtures ─────

static func config_one_agent(mock: bool = true) -> Dictionary:
	return {
		"schema_version": 1,
		"mock": mock,
		"agents": [
			{
				"id": "test_agent",
				"agent_type": "default",
				"display_name": "Test Agent",
				"endpoint": "",
				"model": "",
				"token": "",
				"poll_interval": 5.0
			}
		]
	}


static func config_zero_agents() -> Dictionary:
	# For AC-32 empty-agent-list bootstrap test
	return {
		"schema_version": 1,
		"mock": true,
		"agents": []
	}


static func stats_blob_default() -> Dictionary:
	# Matches the persisted stats schema in ASM GDD §4.6
	return {
		"current_state": "idle",
		"tasks_completed": 0,
		"errored_count": 0,
		"last_state_change_ms": 0,
		"last_payload_id": "",
		"last_stop_reason": "",
		"total_input_tokens": 0,
		"total_output_tokens": 0,
		"session_start_ms": 0
	}


static func stats_blob_corrupt() -> Dictionary:
	# For AC-30 corrupt-blob test — missing required fields, wrong types
	return {
		"current_state": 123,   # wrong type (should be String)
		"tasks_completed": "not a number"   # wrong type
		# missing: errored_count, last_state_change_ms, etc.
	}
