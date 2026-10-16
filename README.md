# Fewshot

**An operating system where AI agents are first-class users — and the kernel, not the model, decides what they may do.**

> *The model proposes. The OS disposes.*

Fewshot is a capability-based, formally-grounded operating system designed from the start for a world where software agents act on a user's behalf. It assumes every model is fallible and every piece of content may be hostile, and builds safety into the layers that can actually enforce it: capabilities, information-flow labels, transactions, and a trusted approval path.

> Status: **design phase**. Nothing here runs yet.
>
> Delivery is **runtime first**: the same policy core ships as a portable Fewshot runtime on Linux, Windows and macOS (MCP-compatible) before the high-assurance OS. See [ADR-0007](docs/adr/0007-portable-runtime-first.md).

## Why

Current "AI PCs" bolt agents onto operating systems designed for humans clicking buttons. Agents scrape screens, inherit all of the user's authority, and rely on the model itself to resist prompt injection. That is not a security model.

## Core invariants

These are the properties the whole system exists to guarantee. Every component is judged against them.

| # | Invariant |
|---|---|
| **I1** | No effect without a capability. Authority is never ambient. |
| **I2** | No high-impact effect whose inputs were influenced by untrusted data, unless the user approves it through the trusted path. |
| **I3** | No data leaves the device to a destination not cleared for its secrecy labels — including remote model providers. |
| **I4** | Every effect is recorded in a tamper-evident audit log *before* it executes. |
| **I5** | Every local mutation made by an agent is reversible until its session commits. |
| **I6** | No agent or app can draw, spoof, or drive the approval UI. |

## Architecture at a glance

```
 ┌──────────────────────── user ────────────────────────┐
 │  Intent shell · Classic UI · Trusted approval surface │
 ├───────────────────────────────────────────────────────┤
 │ agentd  ── planner │ quarantined readers │ executor   │
 ├───────────────────────────────────────────────────────┤
 │ gate (reference monitor) · labeld · txn · audit       │
 │ actions registry · store (semantic) · infer · egress  │
 ├───────────────────────────────────────────────────────┤
 │ supervisor · drivers (user-space) · net · linux-vm    │
 ├───────────────────────────────────────────────────────┤
 │ seL4 microkernel (verified, MCS scheduling)           │
 └───────────────────────────────────────────────────────┘
```

Read next:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components, data flow, interfaces
- [`docs/INFERENCE.md`](docs/INFERENCE.md) — how models run: weights, labels, constrained decoding, scheduling
- [`docs/GROWTH.md`](docs/GROWTH.md) — how agents learn and improve without growing their own authority
- [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md) — designing around model failure modes: hallucination, drift, staleness, sycophancy
- [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) — adversaries, trust boundaries, what is out of scope
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — milestones from "boots in QEMU" to "survives an injection benchmark"
- [`docs/adr/`](docs/adr/) — architecture decision records
- [`interfaces/core.capnp`](interfaces/core.capnp) — draft core interfaces

## Design principles

1. **Enforce below the model.** Prompts are not a security boundary. Anything that matters is enforced by capabilities, labels, or the gate.
2. **Typed actions over pixels.** Apps expose schemas; the GUI is just one client of them.
3. **Reversible by default.** Agents work on a branch of system state. Irreversible effects wait in an outbox.
4. **Local first.** On-device inference by default; remote models are an egress decision like any other.
5. **Deterministic path stays instant.** AI accelerates the system; it never gates basic interaction.
6. **Model-agnostic.** Interfaces outlive any model generation.

## Proposed repository layout

```
docs/            architecture, threat model, ADRs, roadmap
interfaces/      Cap'n Proto schemas (source of truth for all IPC)
kernel/          seL4 configuration and platform support
components/      one crate per protection domain (gate, store, txn, agentd, …)
libs/            shared Rust crates (labels, caps, rpc runtime)
system/          declarative system manifests, image builder
compat/          Linux guest VM, legacy-app bridge
tests/           invariant tests, prompt-injection suites
tools/           build, QEMU runner, image signing
```

## Prior art

seL4 · Fuchsia · Genode · Redox · Plan 9 · Singularity/Midori · HiStar / Flume / Asbestos (DIFC) · CaMeL · NixOS / ostree · Cap'n Proto · MCP · App Intents / AppFunctions

## History

This repository previously held the original Fewshot: a local-first context and memory layer for AI agents (C#, MCP, SQLite, Ollama). That code is archived unchanged on the [`archive/fewshot-v1`](https://github.com/fewshot-app/fewshot/tree/archive/fewshot-v1) branch. Its ideas live on in the memory and growth design ([GROWTH.md](docs/GROWTH.md)).

## License

To be decided. Apache-2.0 OR MIT is suggested for user-space code; seL4 itself is GPL-2.0 (kernel) / BSD (libraries).
