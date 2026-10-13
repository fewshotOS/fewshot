# ADR-0003: Decentralized information-flow labels enforced by the OS

**Status:** Proposed

## Context
Prompt injection cannot be solved inside the model. Any agent that reads untrusted content and holds authority can be steered. The OS must know where data came from and refuse to let low-integrity data drive high-impact effects.

## Decision
- Every principal and stored object carries a label: a **secrecy tag set** and an **integrity level**.
- Reading data raises the reader's secrecy and lowers its integrity; components cannot reverse this themselves.
- The agent executor tracks labels per value; the gate checks argument integrity against each action's `integrityFloor` and argument secrecy against egress clearance.
- Declassification and endorsement happen only through the trusted approval surface or certified transformers declared in the manifest.

## Consequences
- + Injection resistance does not depend on model behaviour.
- + Exfiltration to remote models or third parties is a policy decision, not an accident.
- − Label creep: long sessions accumulate taint and require more approvals. Mitigated by the planner/reader split and short sessions.
- − Usability depends on good default policies; this is the main product risk.

## Alternatives considered
- **Model-level defences only** (system prompts, classifiers): not a security boundary.
- **Capabilities only:** limit *what* an agent can do, but not *whose instructions* it follows.
- **Full Flume-style DIFC with arbitrary tag ownership:** more expressive, too complex for v0.
