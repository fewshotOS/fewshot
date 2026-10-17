# Policy core

The R1 crates ([#2](https://github.com/fewshotOS/fewshotos/issues/2)): portable, `no_std` Rust shared by the Fewshot runtime and the OS (ADR-0007).

| Crate | What it does |
|---|---|
| [`fewshot-labels`](labels) | Secrecy tags, integrity levels (including `Bounded`), `join` and `flows_to`. Same laws as `specs/verus/labels.rs`, property-tested |
| [`fewshot-labeld`](labeld) | The value table (ADR-0005): labeled values behind session-scoped handles. Labels are set only through an `Ingress` capability and computed by `derive`; agents never choose them |
| [`fewshot-host`](host) | Host abstraction (`Clock`), with `SystemClock` (std) and `ManualClock` |
| [`fewshot-gate`](gate) | Capability check, integrity floors and bounded choices, egress clearance, outbox with commit/abort, structured refusals, hash-chained audit log, Ed25519 digest-bound single-use approvals (ADR-0006) |

```sh
cargo test --workspace                                   # unit, invariant and property tests
cargo build --target aarch64-unknown-none --no-default-features \
  -p fewshot-labels -p fewshot-labeld -p fewshot-host -p fewshot-gate   # no_std
```

## Invariant suites

`libs/gate/tests/invariants.rs`, one module per guarantee:

| Module | Checks |
|---|---|
| `i1_no_ambient_authority` | No capability, no effect; attenuated delegation cannot widen; unknown sessions refused |
| `i2_untrusted_data_cannot_steer` | Tainted arguments need approval and do nothing until approved; taint survives `derive`; `Bounded` values may only pick pre-approved options |
| `i3_no_uncleared_egress` | Uncleared secrecy cannot leave; approval does not declassify; local effects are not egress |
| `i4_audit_before_effect` | Every effect receives its own `EffectStarted` entry, already in the log; refusals and requests are audited; chain verifies |
| `i5_reversible_until_commit` | External and irreversible effects wait for commit; abort and close drop them unrun; commit runs in order and stops at the first failure |
| `adr_0005_labels_from_the_table` | Handles from another session do not resolve |
| `adr_0006_approvals` | A modified argument invalidates the approval; forged digest, reuse, expiry, wrong key and wrong session are all rejected |
| `oracle` | Property tests: the gate's decisions match a direct statement of its rules |

Each suite was checked against a deliberately broken gate (capability, egress, floor, digest, single-use and audit-order checks removed one at a time; external effects run immediately). Every break fails at least one test.

## Not in R1

- Store branches for local-reversible writes (M2); the gate runs them immediately.
- Checkpoints, saga compensation, budgets and the agent executor (R2).
- Batched approvals and standing policies (ADR-0006) and declassification.
- Persistent audit storage; the log is in memory.
