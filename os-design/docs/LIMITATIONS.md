# Designing around model limitations

Models used as agents have known, recurring failure modes. Arbiter does not rely on a model overcoming them; it gives the system mechanisms that make each one visible, checkable, or harmless.

> These mechanisms make an agent more reliable **inside** its boundaries. None of them widen the boundaries. Approvals, capability limits and independent checks are limitations an agent should *not* design around.

## Summary

| # | Limitation | Mechanism | Lives in |
|---|---|---|---|
| L1 | Confidently wrong | Claims with provenance · independent verification | executor · gate |
| L2 | Drift on long tasks | Goal ledger | agentd · store |
| L3 | Acting on stale state | Version-checked writes | store · txn |
| L4 | Blind to effects | Action postconditions | actions · gate · audit |
| L5 | Sycophancy | Dissent reviewer | agentd · shell |
| L6 | No sense of time / knowledge cutoff | Trusted clock · freshness metadata | store · executor |
| L7 | Inconsistent answers | Plan sampling and agreement | executor · infer |
| L8 | Manipulable by content | Planner/reader split · labels | agentd · labeld · gate |
| L9 | Opaque failures | Structured refusals | gate · all services |

## L1 — Confidently wrong

Models can state plausible falsehoods with poorly calibrated confidence.

**Claims with provenance.** When a plan step depends on a factual claim, the executor records the store objects that support it. A claim with no supporting objects is marked **unverified**: it is shown as such in the shell and cannot satisfy an action's preconditions.

**Independent verification.** Plans above a risk threshold need agreement from an independent checker before the gate treats them as normal-risk:

| Checker | Used for |
|---|---|
| Deterministic (tests, type check, schema validation, diff review) | Code, data transforms, config |
| Different model family | Free-form reasoning, summaries driving actions |
| User | Anything the checkers disagree on |

## L2 — Drift on long tasks

Early instructions fade from attention; goals drift; work repeats.

**Goal ledger** — a store object per task, owned by the session:

```
GoalLedger {
  goal          the user's request, verbatim
  constraints   explicit rules ("don't touch prod", "keep CRLF")
  done          completed steps with audit refs
  open          remaining steps
}
```

The executor re-injects the ledger on every planning step and checks each proposed step against `constraints`. A step that violates one is rejected before it reaches the gate. The ledger survives context limits, restarts and handoffs between agents.

## L3 — Acting on stale state

An agent reads an object, something else changes it, and the agent writes based on the old version.

**Version-checked writes.** Every read returns a version (`ObjectRef.hash`). Every agent write names the version it was based on. If the current version differs, `store.update` returns `stale` with the current version instead of writing; the agent must re-read and merge. Required for agent principals; optional for legacy POSIX writes.

## L4 — Blind to effects

Agents usually assume an action worked.

**Postconditions.** Actions may declare a postcondition — a read-only check run after the effect (message present in Sent, build green, file hash as expected). The gate runs it, records the result in the audit log and returns it in the `Decision`. A failed postcondition:

1. Marks the step failed in the goal ledger.
2. Is surfaced to the user.
3. Produces a candidate **lesson** in the growth pipeline ([GROWTH.md](GROWTH.md)).

## L5 — Sycophancy

Models lean toward the user's framing and toward agreeing.

**Dissent reviewer.** An optional, separate model call whose brief is to argue *against* the plan: missed risks, simpler alternatives, wrong assumptions. Its output is shown next to the plan, not merged into it. Off by default for routine work; on by default for plans with external effects above a configurable threshold.

## L6 — No sense of time, fixed knowledge cutoff

Models do not know the current date or what has changed since training.

- A **trusted clock** is injected into every planning context.
- Every store object carries `observedAt` and, where relevant, `validUntil`.
- Knowledge with no store source is labeled `source: model-prior`. Time-sensitive facts (prices, versions, roles, availability) from `model-prior` must be refreshed from a live source before they drive an action.

## L7 — Inconsistent answers

Sampling makes outputs vary between runs.

**Plan agreement.** For high-stakes decisions the executor samples *k* independent plans (different seeds, optionally different models). Agreement → proceed. Disagreement → treated as uncertainty: the differences are shown and the user decides. Replay ([INFERENCE.md](INFERENCE.md) §8) makes any single answer reproducible afterwards.

## L8 — Manipulable by content

Covered by the core design: the planner never sees untrusted content, readers hold no capabilities, labels track every value, and the gate enforces integrity floors. See [ARCHITECTURE.md](ARCHITECTURE.md) §5.2 and [ADR-0003](adr/0003-information-flow-labels.md).

## L9 — Opaque failures

Agents often cannot tell *why* they were blocked, so they retry, guess, or work around it.

**Structured refusals.** Every denial from the gate or a core service is a `Refusal`:

```
Refusal {
  reason    missingCapability | labelConflict | budgetExhausted | staleVersion |
            approvalDenied | policyViolation | postconditionFailed
  detail    machine-readable specifics
  remedy    what would make this succeed
  grantor   who can provide it (user, admin, manifest)
}
```

Agents must not retry a refusal unchanged; the executor enforces this. The shell renders refusals for the user with the remedy and a one-step way to grant it, when the user is the grantor.

## Interfaces

See `annotation postcondition`, `Store.update`, `UpdateResult`, `GoalLedger`, `Refusal` and `Decision.postcondition` in [`interfaces/core.capnp`](../interfaces/core.capnp).
