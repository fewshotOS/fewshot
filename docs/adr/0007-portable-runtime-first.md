# ADR-0007: Ship a portable Fewshot runtime before the OS

**Status:** Proposed

## Context
A microkernel OS with its own drivers, compositor and app ecosystem is a multi-year effort before anyone can use it. The most novel and valuable parts of Fewshot — labels, the gate, the outbox, the planner/reader executor, structured refusals, growth — do not depend on seL4. They are useful today to anyone running agents on Linux, Windows or macOS.

## Decision
Deliver Fewshot in two forms from one codebase:

| | **Fewshot runtime** | **Fewshot OS** |
|---|---|---|
| Runs on | Linux, Windows, macOS | seL4 |
| Isolation | OS processes / containers | seL4 protection domains |
| Agent interface | MCP-compatible server exposing gated actions | Native Cap'n Proto |
| Approval surface | Separate privileged process with its own window | Reserved compositor layer |
| Assurance | Best effort: host OS is in the TCB | High: verified kernel, minimal TCB |
| Purpose | Adoption, real-world feedback, injection research | High-assurance deployment |

- Core crates (`labels`, `gate`, `txn`, `executor`, `growth`) are platform-independent Rust with a thin host-abstraction layer.
- The hosted prototype (P0) becomes the runtime's first release rather than a throwaway.
- Existing agents (Claude Code, other MCP clients) can connect to the runtime and get gated actions, labels and an outbox without changing models.

## Consequences
- + Usable in months instead of years; real users find the approval-fatigue and policy problems early.
- + The OS is built against a policy engine already hardened in the field.
- − On a host OS the runtime cannot enforce I1 or I6 against a compromised host; the docs must say so plainly.
- − Two isolation backends to maintain.

## Alternatives considered
- **OS only:** purest, slowest, highest risk of never being used.
- **Runtime only:** fastest, but never reaches the assurance level that motivated the design.
