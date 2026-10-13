# Roadmap

Each milestone ends with something demonstrable and a test that proves it.

| Milestone | Deliverable | Proof |
|---|---|---|
| **M0 — Boot** | seL4 + root task + supervisor on QEMU (x86_64, aarch64); serial console; components from a manifest | CI boots image in QEMU and checks log |
| **M1 — RPC** | Cap'n Proto RPC over seL4 endpoints; capability passing across components | Round-trip + cap-transfer tests |
| **M2 — State** | `store` (CoW, versioned, typed objects), `txn` (branch/commit/abort), `audit` (hash chain) | Crash-consistency tests; rollback tests |
| **M3 — Gate** | `actions` registry, `gate` with capability + effect routing + outbox; text shell | I1, I4, I5 invariant suites green |
| **M4 — Labels** | `labeld`, label propagation in store reads, gate integrity floors, `egress` clearances | I2, I3 suites green with hand-written principals |
| **M5 — Inference** | `infer` with one local model (initially hosted in the Linux VM with accelerator passthrough), scheduler with interactive priority | Latency SLO under background load |
| **M6 — Agents** | `agentd`: delegation, planner/reader split, plan DSL executor with taint tracking | Injection benchmark with adversarial stubs: zero unapproved violations |
| **M7 — Trusted UI** | Compositor with reserved approval layer, secure attention, intent shell, audit timeline | I6 suite: apps/agents cannot draw or inject input into approval layer |
| **M8 — Compat** | Linux VM as driver domain + legacy app host on one reference laptop | Daily-drivable on reference hardware |
| **M9 — Ecosystem** | SDK: schema-first app template, action codegen, local dev runner | Three real apps built only against the SDK |

## First 90 days (suggested)

1. Repo, CI, QEMU runner, seL4 build via `rust-sel4`.
2. M0 and M1.
3. Write `interfaces/core.capnp` for real and freeze v0.
4. Prototype the gate + label logic as a **hosted library on Linux** in parallel, so the policy engine and injection tests can mature before the OS can run them.
