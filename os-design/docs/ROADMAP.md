# Roadmap

Each milestone ends with something demonstrable and a test that proves it.

Delivery runs on two tracks from one codebase ([ADR-0007](adr/0007-portable-runtime-first.md)): the **runtime** on existing OSes first, the **OS** in parallel.

### Track R — Arbiter runtime

| Milestone | Deliverable | Proof |
|---|---|---|
| **R0 — Specs** | TLA+ specs for txn / outbox / checkpoints; Verus-ready skeletons for gate and labeld | Model checker passes I4, I5 properties |
| **R1 — Policy core** | `labels`, value table, `gate` with digest-bound approvals, outbox, structured refusals — as hosted Rust crates | I1–I5 suites green on Linux |
| **R2 — Agent runtime** | Executor with handles, planner/reader split, drafts and checkpoints, adversarial injection harness | Zero unapproved violations with adversarial stubs |
| **R3 — MCP release** | MCP-compatible server exposing gated actions; approval app; audit viewer; Linux, Windows, macOS builds | Usable by existing MCP clients; ≤ 3 approval prompts per hour of typical use |

### Track O — Arbiter OS

| Milestone | Deliverable | Proof |
|---|---|---|
| **M0 — Boot** | seL4 + root task + supervisor on QEMU (x86_64, aarch64); serial console; components from a manifest | CI boots image in QEMU and checks log |
| **M1 — RPC** | Cap'n Proto RPC over seL4 endpoints; capability passing across components | Round-trip + cap-transfer tests |
| **M2 — State** | `store` (CoW, versioned, typed objects), `txn` (branch/commit/abort), `audit` (hash chain) | Crash-consistency tests; rollback tests |
| **M3 — Gate** | Port R1 crates onto seL4: `actions` registry, `gate`, outbox; text shell | I1, I4, I5 invariant suites green |
| **M4 — Labels** | `labeld`, label propagation in store reads, gate integrity floors, `egress` clearances | I2, I3 suites green with hand-written principals |
| **M5 — Inference** | `infer` with one local model (initially hosted in the Linux VM with accelerator passthrough), scheduler with interactive priority | Latency SLO under background load |
| **M6 — Agents** | `agentd`: delegation, planner/reader split, plan DSL executor on value handles (R2 crates ported) | Injection benchmark with adversarial stubs: zero unapproved violations |
| **M7 — Trusted UI** | Compositor with reserved approval layer, signing key, secure attention, intent shell, audit timeline, native browser | I6 suite: apps/agents cannot draw, inject input, or forge approvals |
| **M8 — Compat** | Linux VM as driver domain + legacy app host on one reference laptop | Daily-drivable on reference hardware |
| **M9 — Ecosystem** | SDK: schema-first app template, action codegen, local dev runner | Three real apps built only against the SDK |

## First 90 days (suggested)

1. Repo, CI, contribution guide.
2. **R0:** write the TLA+ and Verus specifications for the invariants before implementation.
3. **R1:** policy core as hosted crates, with the invariant test suites.
4. In parallel: M0 (seL4 boot in QEMU) to de-risk the OS track.
