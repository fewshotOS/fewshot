# Specifications

Machine-checked specifications of Fewshot's core guarantees, written before the implementation (R0, [#1](https://github.com/fewshotOS/fewshotos/issues/1)).

```sh
specs/check.sh          # everything
specs/check.sh tla      # TLA+ model check only (~1–2 min)
specs/check.sh verus    # Verus proofs only (seconds)
```

The script downloads pinned, checksum-verified tools into `.tools/` on first run. It needs Java 17+ and `rustup`. CI runs the same script ([`.github/workflows/specs.yml`](../.github/workflows/specs.yml)).

| Tool | Version |
|---|---|
| TLA+ tools (TLC) | 1.8.0 |
| Verus | 0.2026.09.27.3cf1832 (Rust 1.98.1) |

## `tla/Txn.tla`: transactions, outbox, gate ordering, approvals

Models agent sessions working on transaction branches, queuing external effects in the outbox, committing or checkpointing under a commit lock, the gate auditing and executing outbox effects, digest-bound approvals, version-checked commits, and saga compensation when an effect fails or the user denies an approval.

| Property | Kind | Guarantee |
|---|---|---|
| `AuditBeforeEffect` | invariant | **I4**: every external effect has an earlier audit entry |
| `MainChangesOnlyOnPublish` | action property | **I5**: the committed store changes only when a session publishes, after all of its external effects ran |
| `AbortLeavesMainUnchanged` | action property | **I5**: abort, stale refusal and failed sagas never touch the committed store |
| `ApprovedOnly` | invariant | ADR-0006: an effect needing approval never runs without one |
| `ApprovalBinding` | invariant | ADR-0006: an approval is consumed only by the effect it signs |
| `NoDoubleExec` | invariant | No effect runs twice |
| `NoEffectAfterEnd` | invariant | No effect after a session ends |
| `LockHeldWhileCommitting` | invariant | Commits are serialised |
| `SagaCompensates` | invariant | Once a failed commit ends, every compensable effect it ran has been compensated |

Model: 2 sessions, 1 key, 2 values, 2 actions (`send` needs approval and has no compensation; `move` is compensable), up to 3 effects, event log bounded at 14 entries. About 3.2 million distinct states.

## `verus/`: label lattice and gate

| File | Proven |
|---|---|
| `labels.rs` | Flow is reflexive and transitive; `join` is commutative, associative, idempotent, and the least upper bound; reading data never raises integrity or drops secrecy; untrusted-web taint is sticky; the exec `join` and `can_flow` match their specs |
| `gate.rs` | `decide` returns `Execute`/`Queue` only if the caller holds the capability, every handle resolves, argument integrity meets the action's floor or a valid approval was presented, and external effects carry only cleared secrecy tags. Labels come only from the value table (ADR-0005). `run_effect` preserves audit-before-effect (I4) |

## Checking the checks

Each property was confirmed to fail against a deliberately broken copy of the model or code:

| Bug introduced | Caught by |
|---|---|
| Gate executes without an audit entry | `AuditBeforeEffect` |
| Approval check removed | `ApprovedOnly` |
| Any approval accepted for any effect | `ApprovedOnly` |
| Compensation skipped | `SagaCompensates` |
| Abort publishes the branch | `MainChangesOnlyOnPublish` |
| Writes go straight to the committed store | `MainChangesOnlyOnPublish` |
| Gate skips the egress check | `decide` postcondition |
| Gate skips the integrity floor | `decide` postcondition |
| Effect recorded before its audit entry | `run_effect` proof |
| `join` takes the maximum integrity | `join_exec` postcondition |

## Limits

- The TLA+ model is bounded: it shows the properties hold for every behaviour up to the bounds above, not for all sizes.
- Approval digests are abstracted to effect ids. Signing and digest computation are not modeled.
- Single-use approvals hold structurally here: each effect has a unique id and leaves the outbox when it runs. A retry mechanism would need this re-checked.
- The Verus code is a reference model. The shipping crates in [`libs/`](../libs) implement the same rules and property-test the same laws, but are not themselves verified; verifying them directly is future work.
- I1–I3 and I6 are not yet specified; I2/I3 are partly covered by `decide`.
