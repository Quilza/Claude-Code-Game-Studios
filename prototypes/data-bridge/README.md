# Data Bridge Prototype — Sprint 1

**Goal**: Validate ADR-0001's HTTP polling transport against a real Claude API endpoint, capture state-vocabulary findings, unblock ADR-0007.

See `production/sprints/sprint-1.md` for the full charter and DoD.

## Quick start

### Mock mode (no setup needed)

```bash
cd prototypes/data-bridge/
godot --path .
```

Should open a 480×270 window showing one agent "claude_dev" cycling through mock payloads. Every ~7th cycle simulates a failure to exercise the STALE → DISCONNECTED → auto-heal backoff machine. State transitions print to stdout.

### Real Claude API mode

1. Copy `config.example.json` to `config.json` (it's gitignored — your token never leaves your machine)
2. Set `"mock": false`
3. Replace `"YOUR_ANTHROPIC_API_KEY_HERE"` with a real key
4. (Optional) Remove the second agent entry if you only want to test one
5. Run:

```bash
godot --path .
```

The prototype will poll `claude-3-5-haiku-latest` with a 1-token "ping" message every 5 seconds. Watch the connection state evolve and the payloads stream in.

**Budget guard** (per `production/risk-register/2026-05-12-sprint-1.md` R-S1-01): each poll consumes ~2 tokens. At 5s cadence × 1 hour = ~720 tokens. Run for a few minutes at a time, not continuously.

### Web export mode

ADR-0004 forces `mock: true` on web. To verify the override:

```bash
godot --path . --headless --export-release "Web" build/web
```

Then serve `build/web/` from any static host and watch the console — should say `[ConfigLoader] Web export forces mock=true (CORS); real-API config ignored`.

## What this prototype tests

| Question | Resolution path |
|---|---|
| Q1: Realistic poll cadence? | Default 5s — adjust in config.json and observe API rate-limit response |
| Q2: Real payload shape? | Run real mode, save payloads to `findings.md` |
| Q3: Transient failure frequency? | Run for 10+ minutes; count failures in console log |
| Q4: **Canonical agent state vocabulary?** | Inspect payloads in `findings.md` — what states can we derive? |
| Q5: **Connection-quality reporting mechanism?** | The bridge already separates connection-state from agent-state. Validate this is right. |
| Q6: Web CORS strategy | ADR-0004 already answered (mock-forced). Verify the override fires. |
| VERIFY-7 | `request_completed` signal signature — assertions in code |
| VERIFY-8 | `HTTPRequest.timeout` cancellation — observe console for orphan errors |

## Files

- `project.godot` — Godot 4.6.2 project config (480×270 viewport per ADR-0013)
- `Main.tscn` — entry scene (Main node + DataBridge child + CanvasLayer UI)
- `AgentStatusLabel.tscn` — per-agent visual indicator
- `scripts/configuration_loader.gd` — minimal ConfigurationLoader autoload (ADR-0002 + ADR-0004 subset)
- `scripts/data_bridge.gd` — the bridge under test (ADR-0001 transport pattern)
- `scripts/agent_status_label.gd` — UI subscriber (ADR-0006 Tier 2 pattern)
- `scripts/main.gd` — scene wiring + agent label spawning
- `config.example.json` — config template (commit-safe)
- `config.json` — your local config with real token (gitignored)
- `findings.md` — running document of prototype findings (commit answers here)

## What gets promoted to the main project after Sprint 1

After the sprint retro, the following patterns land in `src/integration/`:

- `ConfigurationLoader` shape (with the production additions ADR-0002 specifies: schema validation, signal emission, settings persistence)
- `DataBridge` shape (with production additions: registry mock-file loading, full backoff curve, possibly WebSocket post-MVP per ADR-0001)
- The two signals (`agent_response_received`, `agent_connection_changed`) — names + signatures locked

The visual indicator (`AgentStatusLabel`) is throwaway — the real HUD is ADR-0011.

## What stays out of this prototype

Per Sprint 1 charter "Out of scope":
- ASM, ACC, AAL, TCB, HUD — none of these belong here
- The 4-state agent vocabulary (`idle/working/completed/errored`) — that's ADR-0007's job, post-prototype
- Audio, sprite rendering, room layout

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "No config file found — using test-mode default" but you wrote a config.json | Wrong directory; the prototype looks at `res://config.json` relative to its own project dir |
| All requests fail with HTTP 401 | Bad token in config.json |
| All requests fail with HTTP 400 | Endpoint URL wrong, or model name wrong |
| State stuck at CONNECTING forever | No agents in config (check `agents` array) |
| Web build hits real API | ADR-0004 override bug; check `[ConfigLoader] Web export forces mock=true` warning fired |
| Console says `request() returned err=` | Network unreachable or invalid endpoint format |
