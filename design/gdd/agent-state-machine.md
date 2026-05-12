# Agent State Machine — Game Design Document

> **Status**: SKELETON — section-by-section authoring per `.claude/rules/design-docs.md` ("create skeleton first, then fill each section one at a time with user approval between sections")
> **Created**: 2026-05-12
> **Owner**: game-designer (with technical-director consultation)
> **Linked**:
>   - ADR-0007 Agent State Vocabulary (Accepted 2026-05-12)
>   - ADR-0001 Data Bridge Transport (Accepted + Amendment 2026-05-12.b)
>   - ADR-0005 task_completed Signal Source
>   - ADR-0006 Signal-Based Decoupling
>   - `prototypes/data-bridge/findings.md` (empirical Anthropic API observations)

This is GDD #6 (the 10th and last MVP GDD). It was BLOCKED on the Data Bridge prototype + ADR-0007. Both are now closed; ASM can be designed.

---

## 1. Overview

> [SECTION TO BE AUTHORED] — one-paragraph summary of what the Agent State Machine is, why it exists, and how it fits between Data Bridge and the downstream consumers (ACC, AAL, HUD, TCB). Should be ≤120 words.

---

## 2. Player Fantasy

> [SECTION TO BE AUTHORED] — what should the player *feel* when an agent transitions between states? Tie back to the five game pillars (Alive by Default, Readable at a Glance, Satisfying Feedback, Commander Always Home, Earn Each Room). Should be ≤150 words.

---

## 3. Detailed Rules

> [SECTION TO BE AUTHORED] — the full state machine, expressed as unambiguous mechanics.
>
> Will draw from ADR-0007:
>   - The four states (`idle`, `working`, `completed`, `errored`)
>   - Derivation rule: parse Data Bridge raw payload JSON, match `stop_reason`
>   - `completed` is transient (1.5s decay → `idle`)
>   - `errored` is persistent (no auto-decay)
>   - `task_completed(agent_id)` emits on every entry into `completed`
>   - Orthogonality with Data Bridge connection-state
>
> Must specify:
>   - Numbered rule list (10-20 rules expected)
>   - State machine entry rules (what's the initial state? what happens on agent first registration?)
>   - State machine exit rules (what happens when ConfigurationLoader removes an agent?)
>   - In-flight tracking via ADR-0001 B2 signals (`request_dispatched` / `request_settled`)
>   - Per-agent isolation (each agent has its own state — never aggregated except for HUD-level summary)
>   - Edge case enumeration that feeds Section 5

---

## 4. Formulas

> [SECTION TO BE AUTHORED] — all math defined with variables and ranges.
>
> Expected formulas:
>   - `COMPLETED_DECAY_SEC = 1.5` (matches TR-hud-004 slot glyph timer)
>   - `UNKNOWN_STOP_REASON_FALLBACK = "completed"` (conservative)
>   - `INITIAL_AGENT_STATE = "idle"`
>   - State transition table (matrix: from-state × event → to-state)
>   - Stats accumulator math (`tasks_completed += 1` on each `completed` entry; `errored_count`; `last_state_change_ms`)
>
> Each constant must include: default, safe range, what gameplay aspect it affects.

---

## 5. Edge Cases

> [SECTION TO BE AUTHORED] — explicitly state what happens in each unusual situation.
>
> Expected edge cases (from prototype + ADR-0007 analysis):
>   - Malformed JSON payload from Data Bridge → `errored` + push_warning
>   - HTTP error envelope (`{"type":"error",...}`) → `errored`
>   - Unknown `stop_reason` value → `completed` + push_warning
>   - Empty `content[]` array (max_tokens=1 cut off) → `completed` (still a valid completion)
>   - Rapid response cascade — new response arrives before `COMPLETED_DECAY_SEC` timer expires → kill old timer, apply new state immediately
>   - Bridge transitions to DISCONNECTED mid-request → in-flight tracking: ASM keeps `working` until `request_settled` arrives, then transitions per response or marks `errored` if response was abandoned
>   - Agent removed from ConfigurationLoader at runtime (hot-reload) → ASM deregisters; `agent_state_changed` final emission with `previous_state=<last>, new_state="<removed>"` (or skip emission and document)
>   - Agent added at runtime via config reload → ASM registers with `INITIAL_AGENT_STATE`
>   - Bridge mock mode (ADR-0008) — mock payloads must conform to the parse rule. ASM does NOT differentiate mock-source from real-source.
>   - Web mode (ADR-0004 — mock forced) — ASM is unaware of web override; receives mock payloads exactly as in PC mock mode.

---

## 6. Dependencies

> [SECTION TO BE AUTHORED] — list other systems ASM depends on and that depend on ASM.
>
> Upstream (ASM reads from these):
>   - Data Bridge — `agent_response_received(agent_id, payload)`, `agent_connection_changed(agent_id, conn_state)`, `request_dispatched(agent_id)`, `request_settled(agent_id)` (latter two per ADR-0001 B2)
>   - ConfigurationLoader — agent registry (`get_agents()`)
>
> Downstream (these read from ASM):
>   - Agent Character Controller (ACC) — subscribes to `agent_state_changed` via `.bind(agent_id)` to drive sprite animation per ADR-0009
>   - Ambient Animation Layer (AAL) — subscribes to per-room aggregate of agent states
>   - Task Completion Beat (TCB) — subscribes to `task_completed` to fire room beat + audio
>   - Commander's Room HUD — subscribes to `agent_state_changed` + reads `get_agent_stats(id)` per ADR-0006 Tier 2/3
>
> Bidirectional verification: each downstream system's GDD must list ASM as an upstream dependency.

---

## 7. Tuning Knobs

> [SECTION TO BE AUTHORED] — configurable values + safe ranges + gameplay impact.
>
> Expected knobs (carry forward from ADR-0007 + extend):
>   - `COMPLETED_DECAY_SEC` (1.5; range 0.5-3.0; longer = slower visual feedback; must stay ≤ TR-hud-004 slot timer)
>   - `UNKNOWN_STOP_REASON_FALLBACK` (`completed`; one of `{completed, errored, idle}`)
>   - `INITIAL_AGENT_STATE` (`idle`; one of `{idle, working}`)
>   - Bridge-derived: poll cadence, retry counts (owned by ADR-0001, not ASM)
>   - Stats reset behaviour: do `tasks_completed` counters persist across session? (Pinned in section 4 + here)

---

## 8. Acceptance Criteria

> [SECTION TO BE AUTHORED] — testable conditions that QA can verify pass/fail.
>
> Expected ACs (15-25 total):
>   - One AC per state transition rule (covers the derivation rule table)
>   - One AC per edge case in Section 5
>   - One AC per signal emission contract
>   - One AC per public read-only API method
>   - One AC for the orthogonality property (mock both signal sources, assert no coupling)
>   - GUT test names already pinned in ADR-0007's Validation Criteria — those become ACs here verbatim

---

## Section authoring order

Recommended order for incremental authoring:
1. **Overview** — sets the framing
2. **Player Fantasy** — keeps the design grounded in feel
3. **Dependencies** — clarifies the interface surface before mechanics
4. **Detailed Rules** — the big one
5. **Formulas** — extract from Rules
6. **Edge Cases** — pressure-test Rules
7. **Tuning Knobs** — extract from Formulas
8. **Acceptance Criteria** — closes the loop

Each section: I draft → you redline → I commit to file → next section.

---

## Open questions for the user before authoring begins

1. **Stats reset behaviour**: should `tasks_completed` counters persist across sessions (saved to `user://settings.json`) or reset on each app launch? Default proposal: reset (in-memory only) for MVP. Stats persistence is a post-MVP polish item.
2. **Agent removal at runtime**: should hot-reload of ConfigurationLoader be supported in MVP? Default proposal: NO — agents are registered at bootstrap only; config edits require restart. Simplifies ASM substantially.
3. **Stats granularity**: what fields exactly in `get_agent_stats(id)`? Proposal: `{tasks_completed: int, errored_count: int, last_state_change_ms: int, last_payload_id: String, current_state: String}`. Open to additions.
4. **Multi-message conversation context**: ASM treats every poll as independent. We don't track conversation history. Confirm this is intended? (Per ADR-0001, bridge is stateless — and ASM should mirror that simplicity.)
