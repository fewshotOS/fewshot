# ADR-0005: Labeled value handles — remove the executor from the TCB

**Status:** Proposed

## Context
In the original design the executor tracked a label per value and passed `argumentLabels` to the gate with each invocation. The gate could not independently check them, so a bug in the executor would silently break I2 and I3. The executor is a large interpreter; it should not be trusted.

## Decision
- Every runtime value an agent session produces or receives lives in a **value table** owned by `labeld`. Each entry holds the value, its label and its provenance.
- The executor, planner and readers only ever hold **opaque handles** to entries. They cannot read or set labels.
- Operations that derive a new value (reader output, string concatenation, field extraction) go through `labeld`, which computes the result's label as the join of its inputs.
- `Invocation` carries argument **handles**, not labels. The gate resolves each handle in `labeld` to get the true label and provenance.
- Handles are session-scoped capabilities: unforgeable, unusable outside the session that created them.

## Consequences
- + The executor leaves the TCB. A compromised executor can choose *which* handles to pass, but cannot misstate their labels.
- + The gate's label check depends only on `labeld` and itself — both small and verifiable.
- − Every derived value costs an IPC to `labeld`. Mitigated by batching derivations per plan step and keeping large payloads in shared memory with only metadata in the table.
- − Values must be explicitly freed or garbage-collected with the session.

## Alternatives considered
- **Trust the executor:** simplest, but makes the largest agent component security-critical.
- **Re-derive labels in the gate from provenance:** possible for store objects, impossible for computed values without replaying the plan.
