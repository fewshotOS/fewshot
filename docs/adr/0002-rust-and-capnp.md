# ADR-0002: Rust for user space, Cap'n Proto for all interfaces

**Status:** Proposed

## Context
Memory-safety bugs are the dominant class of OS vulnerabilities. Components need a single interface language that can express typed actions and pass capabilities.

## Decision
- All user-space components are written in Rust (`no_std` where practical).
- All IPC interfaces, including app actions, are defined in Cap'n Proto schemas under `interfaces/`. Schemas are the source of truth; bindings are generated.
- Interface references map onto seL4 endpoint capabilities: holding a reference is holding the authority.

## Consequences
- + Memory safety across the TCB outside the kernel.
- + Cap'n Proto's object-capability RPC fits the security model without inventing an IDL.
- + Zero-copy message layout suits shared-memory transport.
- − Need a custom Cap'n Proto RPC transport over seL4 IPC + shared memory.
- − Action metadata (effect class, integrity floor) must be expressed as annotations and validated by tooling.

## Alternatives considered
- **Custom IDL (FIDL-like):** full control, but more to build and nobody knows it.
- **Protobuf/gRPC:** no capability passing.
- **JSON-schema / MCP-style:** good for bridging external agents, too loose for kernel-adjacent IPC. An MCP bridge can sit on top of the action registry.
