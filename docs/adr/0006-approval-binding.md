# ADR-0006: Approvals are bound to the exact invocation

**Status:** Proposed

## Context
An approval answered "yes" to *something*, but nothing tied it to the exact action and arguments the user saw. A compromised component could swap arguments between display and execution, or replay an old approval.

## Decision
- The gate computes an **invocation digest**: hash of action name, resolved argument values, argument labels, target principal, session, and a nonce.
- The trusted approval surface renders the invocation from the gate's data and, on user consent, returns a **signed approval** over that digest using a key held only by the compositor's trusted path (hardware-backed where available).
- At execution the gate recomputes the digest and executes only if it matches a fresh, unused approval. Approvals are single-use and expire.
- **Batched approvals** (several related effects in one decision) sign the list of digests; each effect still verifies individually.
- **Standing policies** (user-approved rules) are themselves signed objects; the gate records which policy authorised each effect.

## Consequences
- + Time-of-check/time-of-use attacks between display and execution are closed.
- + Every effect in the audit log carries verifiable proof of who authorised it.
- − Any argument change, however small, requires re-approval. This is intended.
- − Needs a protected signing key in the trusted UI path.

## Alternatives considered
- **Gate-internal approval tokens without signatures:** simpler, but the audit log could not prove approvals to a third party.
- **Approving a plan rather than invocations:** too coarse; arguments are often only known at execution time.
