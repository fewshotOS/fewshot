# Inference

How models run on Arbiter.

> **The model is a stateless function the OS runs — not a program that runs the OS.**
> It holds no capabilities, keeps no hidden state, and its output is labeled data like any other.

## 1. Placement

```
agentd (planner / readers)
   │  Infer.generate(model, context refs, output grammar, priority)
   ▼
infer ── scheduler · KV-cache manager · model registry
   │  narrow tensor-queue interface (submit / complete)
   ▼
accelerator driver (GPU / NPU)   ← Linux driver domain at first
```

- Apps never bundle shared models; they call `infer`.
- The inference engine holds capabilities only to the accelerator queue and to read-only weight objects. It cannot reach `store`, `net`, or `gate`.
- GPU drivers are outside the TCB. Initially they live in the Linux driver domain behind a narrow queue; native NPU drivers come later.

## 2. Weights

- **Signed, content-addressed, read-only** memory objects, mapped once and shared by every session using that model.
- The weight hash is measured at load and recorded on every audit entry.
- **Adapters** (LoRA, etc.) are store objects with labels. Their label is the join of the labels of their training data; anything generated with them inherits it. See [GROWTH.md](GROWTH.md).

## 3. Context assembly

- The model never fetches anything. The executor assembles context from store references; every span keeps its provenance and label.
- **Output label = join of all input labels**, including adapter labels. Summarising untrusted content does not make it trusted.
- Labels join over a call, so the runtime prefers **many small, narrowly-scoped calls** over one large context.

## 4. Constrained decoding

Every call carries an **output grammar** generated from a Cap'n Proto schema; the decoder cannot emit anything outside it.

| Caller | Grammar | Effect |
|---|---|---|
| Planner | Plan DSL | Cannot invent actions or syntax; only references registered actions |
| Reader | Requested result schema | Injected instructions have nowhere to go |
| Reader with closed schema (enum, bounded number) | Closed set | Eligible as a **certified transformer** (ADR-0003) |

Models never call tools. They produce plans or values; the executor and gate decide what runs.

## 5. Scheduling

- Priorities map to MCS scheduling contexts: `interactive` > `normal` > `background`.
- Continuous batching with **preemption at token boundaries**: background work yields within one decode step.
- **KV cache** is a memory object owned by the session, with its label. Under pressure it is evicted to RAM/SSD and restored, never silently dropped.
- Speculative decoding with a small draft model for interactive latency.
- Each priority class has an energy budget; background work pauses on battery.

## 6. Isolation between sessions

- Prefix / KV reuse across sessions is a timing side channel. Reuse only between sessions whose labels are compatible (same secrecy tag set).
- Batching across secrecy classes is a policy setting. Default: batch only within a class. Strict mode: time-partition the accelerator per class.

## 7. Model tiers

| Tier | Size | Role | Where |
|---|---|---|---|
| Always-on | ≤1B | Wake word, intent routing, classification | NPU, resident |
| Planner | 7–30B | Writes plans; sees only high-integrity input | On-device |
| Readers | 1–8B | Untrusted content → schema; hold no capabilities | On-device, parallel |
| Remote | Frontier | Hard tasks, opt-in | Via `egress`; prompt labels checked against provider clearance |

## 8. Reproducibility

Each call records: weight hash, adapter hashes, context refs, grammar, sampling parameters, seed, output. With deterministic kernels a call can be **replayed** to answer "why did the agent do that?".

## 9. Interface

See `Infer`, `ModelInfo` and `InferRequest` in [`interfaces/core.capnp`](../interfaces/core.capnp).
