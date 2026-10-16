# Threat model

## Assets

- User data in `store` (documents, messages, memory, credentials)
- User authority: money, identity, outbound communication
- Integrity of system state and the audit log
- The user's attention and the approval decision itself

## Adversaries

| Adversary | Capability | Primary defence |
|---|---|---|
| **Malicious content** — web pages, emails, documents, images containing instructions | Can fully control a model that reads it | Planner/reader split, labeled value handles, gate integrity floors (I2) |
| **Compromised or misaligned model** (local or remote) | Arbitrary outputs from any model call | Models hold no authority; all effects go through the gate |
| **Malicious app** | Arbitrary code in its own protection domain | Capabilities (I1), labels, cannot reach the approval surface (I6) |
| **Malicious remote model provider** | Sees whatever prompt is sent to it | Egress clearances; local-first routing (I3) |
| **Network attacker** | Read/modify traffic | TLS in `net`/`egress`; signed updates |
| **Compromised driver** | Arbitrary code in driver domain, DMA | IOMMU, isolated component, restart by supervisor |
| **Approval swapping / replay** — change arguments between display and execution, reuse an old approval | Compromised non-TCB component | Digest-bound, signed, single-use approvals (ADR-0006) |
| **Bounded steering** — injection picks which allowed option a certified transformer outputs | Influence over a closed choice | `bounded` integrity: may only select among user pre-approved options |
| **Approval fatigue** | Social: user clicks "yes" to everything | Drafts by default, batched approvals, standing policies, risk-proportional checks, plain-language templates; measured in R3 |

## Trust boundaries

Trusted computing base (TCB), in order of how much we care about shrinking and verifying it:

1. seL4 kernel (verified)
2. supervisor, gate, labeld, txn, audit, egress
3. compositor's trusted surface, input routing and approval signing key

**Not** in the TCB: every model, agentd's planner, readers **and executor** (ADR-0005: labels live in `labeld`, agents hold only handles), all apps, all drivers, the Linux VM.

When running as the **Fewshot runtime** on a host OS (ADR-0007), the host kernel and its administrator are also in the TCB.

## Explicitly out of scope (for now)

- Physical attacks, cold boot, hardware side channels beyond what seL4 MCS time partitioning mitigates
- A user who deliberately approves a harmful action with full information
- Malicious hardware / firmware below the boot measurement
- Denial of service by a component consuming its *own* quota

## Security test strategy

- **Invariant tests:** each invariant has a test suite that tries to violate it directly.
- **Injection benchmarks:** run AgentDojo-style suites with the reader and planner replaced by *adversarial* stubs that always follow injected instructions. Pass condition: zero policy-violating effects reach execution without an approval.
- **Fuzzing:** gate and labeld IPC interfaces, store query parser, plan DSL interpreter.
