# Inference

How models run on Fewshot.

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

## 9. Default models

Fewshot is model-agnostic: `infer` loads any signed weights through the same interface. The defaults below are a starting point, chosen by these rules.

### Selection rules

1. **Open weights for every local tier.** Weights must be signed, hashed and run on-device.
2. **Permissive licence (Apache-2.0 / MIT) for anything shipped in the image.** Models with custom or use-restricted licences are optional downloads, not bundled.
3. **Planner:** strong structured output and tool use — it writes plan-DSL under a grammar.
4. **Readers:** small and fast — they only fill schemas and their output is distrusted anyway.
5. **Hardware-aware:** at first boot `infer` detects RAM, VRAM and NPU and proposes the best set that fits.

### Defaults by tier

| Tier | Class of model | Ships in image |
|---|---|---|
| Always-on | ~0.5–1B instruction model + speech-to-text + embedding model | Yes |
| Reader | ~1–4B instruction model | Yes |
| Planner | 7–32B tool-use / coding-tuned model, sized to hardware | Downloaded at setup |
| Remote | Frontier API models, opt-in per provider | No — user adds a provider and its clearance |

Candidate families with permissively licensed releases at these sizes include Qwen, Mistral and Phi. Families with custom licences (e.g. Llama, Gemma) are offered as optional downloads. The open-model landscape moves quickly; defaults are re-evaluated per release against current benchmarks and licences.

### Planner by hardware

| Machine | Planner |
|---|---|
| 8 GB RAM, no GPU | ~3–4B, quantised |
| 16–32 GB / unified-memory laptops | 7–14B |
| 24 GB+ VRAM GPU | ~30B class |
| Below that | No local planner: the classic UI works without agents, or a remote planner is used under `egress` rules |

### Remote providers

Closed frontier models (e.g. Claude) run only in the remote tier. The user adds a provider and sets its **clearance** — which secrecy tags may be sent to it. `egress` enforces that clearance on every prompt (I3). No model, local or remote, is trusted by the design; remote models handle hard reasoning, local models handle private and routine work.

### Runtime path

| Phase | Engine | Location |
|---|---|---|
| Early | llama.cpp with GGUF quantised models | Linux driver domain, accelerator passthrough |
| Later | Native Rust inference engine | Native component on the tensor queue |

The `Infer` interface is identical in both phases; models and apps are unaffected by the switch.

## 10. Interface

See `Infer`, `ModelInfo` and `InferRequest` in [`interfaces/core.capnp`](../interfaces/core.capnp).
