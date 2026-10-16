# ADR-0004: Linux compatibility through a guest VM, not syscall emulation

**Status:** Proposed

## Context
Without drivers and applications the OS is unusable. Syscall emulation (Starnix, WSL1) is a huge, permanently incomplete surface.

## Decision
Run a Linux guest under an seL4 VMM in two roles: a **driver domain** exporting devices over VirtIO, and a **legacy app host**. The guest is a single principal labeled `untrusted:legacy`. Agents reach legacy apps only through an accessibility/screen bridge with low-integrity outputs.

## Consequences
- + Usable on real hardware years earlier.
- + Legacy software is contained, not trusted.
- − Legacy apps get none of the typed-action benefits; incentive for native ports.
- − VM memory and performance overhead; GPU sharing is hard.

## Alternatives considered
- **Linux syscall personality:** better integration, enormous ongoing cost.
- **No compatibility:** clean, but nobody can use it.
