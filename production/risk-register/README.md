# Risk Register

**Created**: 2026-05-12
**Owner**: producer (no dedicated agent; co-owned by user + technical-director)

## Schema

Each risk file is a markdown doc at `YYYY-MM-DD-[scope].md` (e.g. `2026-05-12-sprint-1.md`). Inside:

```markdown
## R-[scope-id]: Title

| Field | Value |
|---|---|
| **Severity** | LOW / MEDIUM / HIGH / CRITICAL |
| **Likelihood** | LOW / MEDIUM / HIGH |
| **Status** | OPEN / MITIGATING / CLOSED / REALIZED |
| **Opened** | YYYY-MM-DD |
| **Owner** | role / agent |
| **Linked to** | ADR / story / sprint / VERIFY |

### Description
What could go wrong.

### Impact
What happens if it goes wrong.

### Mitigation
What we're doing to reduce likelihood or impact.

### Trigger
What event causes us to escalate this risk's status.
```

## Severity definitions

- **CRITICAL** — Project-killer or multi-week delay
- **HIGH** — Sprint slip or scope cut
- **MEDIUM** — Adds rework or burns a meaningful slice of capacity
- **LOW** — Minor friction; document for awareness

## Rules

- One risk per `R-id`. Never renumber.
- When a risk realizes (mitigation fails, event happens), update Status: REALIZED and link the resulting story/incident.
- When a risk closes (no longer relevant, root cause removed), Status: CLOSED and explain why.
- Review at sprint-start and sprint-retro.

## Open scopes

| File | Scope |
|---|---|
| `2026-05-12-sprint-1.md` | Sprint 1 — Data Bridge prototype |
