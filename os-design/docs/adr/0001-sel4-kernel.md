# ADR-0001: Use seL4 as the kernel

**Status:** Proposed

## Context
The invariants depend on strong isolation and capability-based authority. Writing a new kernel would take years before reaching the assurance seL4 already has.

## Decision
Use the seL4 microkernel (MCS configuration) as the only privileged code. Build everything else as user-space components in Rust using the `rust-sel4` crates.

## Consequences
- + Formal proofs of functional correctness and isolation on supported platforms.
- + Capability model and MCS scheduling contexts match our needs directly.
- − Small hardware support surface; needs the Linux driver domain early (ADR-0004).
- − We inherit seL4's static-system bias; dynamic component creation must be built in the supervisor.

## Alternatives considered
- **Custom Rust microkernel** (Redox/Theseus-style): more control, no proofs, years of work.
- **Zircon (Fuchsia):** capability-based but large, unverified, and tied to Google's roadmap.
- **Linux + sandboxing:** fastest path, but the TCB stays ~30M lines with ambient authority.
