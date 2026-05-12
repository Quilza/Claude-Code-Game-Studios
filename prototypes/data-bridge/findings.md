# Data Bridge Prototype — Findings

> **Sprint**: 1
> **Status**: SCAFFOLD WRITTEN — NOT YET RUN
> **Last Updated**: 2026-05-12

This is a **living document**. Fill in answers as you run the prototype. When all 6 Qs are answered + ADR-0007 is drafted, Sprint 1 DoD is met.

---

## Q1 — Realistic poll cadence?

**Status**: ⬜ unanswered

| Variable | Value |
|---|---|
| Cadence tried | _e.g. 5s, 15s, 30s_ |
| Rate-limit response observed at | _e.g. "429 after 20 polls in a minute"_ |
| Recommendation | _e.g. "5s for prototype; 15s for production"_ |

Notes:

---

## Q2 — Real payload shape?

**Status**: ⬜ unanswered

Paste 2–3 raw payloads observed in console here (truncate as needed):

```json
{
  "_paste real payload sample 1 here_"
}
```

```json
{
  "_paste real payload sample 2 here_"
}
```

```json
{
  "_paste real payload sample 3 here_"
}
```

Key fields observed:
- `_field1_`: _what it tells us_
- `_field2_`: _what it tells us_

---

## Q3 — Transient failure frequency?

**Status**: ⬜ unanswered

| Variable | Value |
|---|---|
| Duration ran | _e.g. "30 minutes"_ |
| Total polls attempted | |
| Total failures | |
| Failure rate | |
| Failure types observed | _network / 429 / 5xx / timeout_ |

Notes on auto-heal behaviour:

---

## Q4 — Canonical agent state vocabulary? **[BLOCKS ADR-0007]**

**Status**: ⬜ unanswered

### What real-API payloads tell us about "agent state"

Anthropic Messages API is request/response, not stateful. Each request returns a `stop_reason` and content. To know if an agent is "currently working", we have to track in-flight state on our side, not poll for it.

**Implications for ASM state vocabulary** (fill in after running):

- Does the original `idle / working / completed / errored` vocabulary survive contact with reality?
  - Answer: _yes / no / partially_
- If partially: which states are derivable from API response, which need bridge-tracked side state?
- Should ASM treat `working` as "request in-flight" + `idle` as "no request in-flight"? Or polled from something else?
- Is there a 5th state we missed (e.g., `waiting_for_tool_result`, `streaming`)?

**Recommended ADR-0007 state list** (proposal — refine after running):

```
idle       — no request in-flight, no work pending
working    — request in-flight (tracked by bridge, not API-reported)
completed  — most recent response had stop_reason ∈ {end_turn, stop_sequence}
errored    — most recent response had stop_reason ∈ {error, max_tokens-with-no-content} or HTTP error
```

### Open sub-questions for ADR-0007 to resolve

- How does `completed` decay back to `idle`? Time? Next poll?
- Is `working` even visible if requests complete in <1 frame?
- Tool-use responses (`stop_reason: tool_use`) — that's mid-flight from the user's perspective. State?

---

## Q5 — Connection-quality reporting mechanism? **[BLOCKS ADR-0007]**

**Status**: ⬜ unanswered (partial design)

### Current bridge design

`DataBridge` emits two **separate** signals:
- `agent_response_received(agent_id, payload)` — pure data
- `agent_connection_changed(agent_id, new_state)` — connection states from `{CONNECTING, CONNECTED, STALE, DISCONNECTED, ERROR}`

ASM (future) consumes both and derives the *agent* state vocabulary. HUD (future) renders connection-quality via slot `modulate.a` per ADR-0011.

### Question to validate

After running the prototype:
- Does this separation hold up? Or do connection-state and agent-state actually entangle?
- If a poll succeeds but the payload is garbage, what state should the system be in? CONNECTED + errored? STALE? Some new state?

**Proposed answer**: keep them separate. Connection-state = "can we talk to the provider?" Agent-state = "what is the AI saying about its own work?"

---

## Q6 — Web CORS strategy

**Status**: ✅ ANSWERED by ADR-0004 (web export forces mock=true)

Verification:
- ⬜ Web build verified that the override fires (`[ConfigLoader] Web export forces mock=true` warning observed in browser console)
- ⬜ Web build's `Network` DevTools tab confirms zero requests to `api.anthropic.com`

---

## VERIFY-7 — `HTTPRequest.request_completed` signal signature

**Status**: ⬜ unverified

Expected: `request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray)`.

Run the prototype, observe the signal connection works without runtime errors. Confirm or document deviation.

Result: _confirmed / deviation: ..._

---

## VERIFY-8 — `HTTPRequest.timeout` clean cancellation

**Status**: ⬜ unverified

Test: configure `http.timeout = 0.001` to force timeout on every poll. Observe:
- ⬜ No "Object was freed" errors
- ⬜ No orphan callbacks fire after timeout
- ⬜ `request_completed` fires with `result == RESULT_TIMEOUT`

Result:

---

## Action items emerging from this sprint

- ⬜ ADR-0007 drafted with state vocabulary derived from above
- ⬜ ADR-0001 reviewed for any pattern that didn't survive contact with reality
- ⬜ Mock file format finalised (does `assets/data/mock/[agent_id].json` need to be richer than a String array?)
- ⬜ Sprint 1 retro doc written
- ⬜ Control manifest version bumped to reflect ADR-0007 acceptance
