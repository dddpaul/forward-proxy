## Save Design Conclusions (before Phase 4)

At the end of Phase 3 (after convergence, before presenting Phase 4 options), the design must be persisted to `design/`. Two cases — pick one before Phase 4:

### Case A — new brainstorm

Propose saving the design conclusions to `design/<name>-brainstorm.md` where `<name>` is a kebab-case slug shared with the eventual PRD (e.g., `design/auth-token-rotation-brainstorm.md`).

The file must follow this structure:

```markdown
# <Title>

## Architecture decision
What was chosen, briefly.

## Components / flows
- Bullet list of components, services, or data flows involved.

## Scope cuts
- What we explicitly excluded and why.

## Open questions
- Anything deferred for later resolution.

## Hand-off
Next: `ralph-prd` to formalize as PRD, then `ralph-backlog` to generate tasks.
```

### Case B — extending or modifying an already-saved brainstorm

If the current session is a follow-on to an existing `design/<name>-brainstorm.md` (e.g., adding a feature to an already-designed component, revisiting scope, deciding a previously deferred open question, capturing a defect that reshapes the design), propose **appending a dated addendum** to that file rather than writing a new one.

Append at the bottom of the file in chronological order. The addendum must use this structure:

```markdown
---

## Addendum: <topic> (added YYYY-MM-DD)

### Why
<one paragraph — the trigger / defect / new requirement that prompted the extension>

### What changed
<the decision, in the same shape as the parent brainstorm: prose, tables, or lists matching the parent's style>

### Implementation checklist
<bullets the implementer will execute, including any cleanup such as memory pruning, ralph-sync runs, or file deletions>
```

The dated heading lets future readers reconstruct decision history. Do not edit prior addenda or the original sections — always append.

### In both cases

If the user approves, write the file (or append the addendum) and confirm. If declined, skip and proceed to Phase 4 — but note in the conversation that the design exists only in ephemeral conversation context, so any backlog task created in Phase 4 will not have a stable doc reference for autonomous Ralph to read.

This rule supplements (does not replace) any user-global Phase 4 rules — both apply.

---

## Phase 4 Override

In Phase 4 (Next Steps), the first option must always be:

- **Create backlog task(s)** — Invoke the `ralph-task` skill with `feature=<slug>` (where `<slug>` matches the design-file slug saved in Phase 3 — e.g., `feature=auth-token-rotation` for `design/auth-token-rotation-brainstorm.md`) plus the brainstorm context (selected approach, design decisions, acceptance criteria, testing strategy) sufficient for autonomous execution in a Ralph loop without human guidance. Passing the slug enables ralph-task to auto-attach the `feature:<slug>` label to every created task — required downstream so `/ralph-review feature=<slug>` can find every task that belongs to this feature for cumulative consistency checks against design intent. If the scope is PRD-shaped (≥3 user stories, multiple lanes), `ralph-task`'s pre-check will redirect to `ralph-prd` → `ralph-backlog`.

The remaining options (Write plan, Plan mode, Start now) follow after.

---

## Project additions

<!-- Add project-specific brainstorm rules below this heading. Content here is preserved on `ralph upgrade`. -->

