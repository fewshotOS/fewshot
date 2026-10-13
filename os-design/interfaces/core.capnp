# Arbiter core interfaces — DRAFT v0.
# Holding a reference to an interface is holding the authority to use it.

@0xc95c9024d3404725;

# ---------- Labels ----------

enum IntegrityLevel {
  untrustedWeb @0;
  untrustedLegacy @1;
  thirdParty @2;
  systemApp @3;
  user @4;
}

struct Label {
  secrecy @0 :List(Text);        # e.g. ["health", "work:acme"]
  integrity @1 :IntegrityLevel;
}

struct Provenance {
  principal @0 :Text;            # "user/agent/session" or component id
  inputs @1 :List(Data);         # content hashes of objects this value derived from
}

# ---------- Action metadata (annotations on methods) ----------

enum Effect {
  read @0;
  localReversible @1;
  localIrreversible @2;
  external @3;
}

annotation effect(method) :Effect;
annotation integrityFloor(method) :IntegrityLevel;
annotation egressTags(method) :List(Text);
annotation idempotent(method) :Void;
annotation compensatedBy(method) :Text;   # name of the undo method

# ---------- Store ----------

struct ObjectRef {
  hash @0 :Data;
  schema @1 :Text;               # fully-qualified type name
}

struct StoredObject {
  ref @0 :ObjectRef;
  label @1 :Label;
  provenance @2 :Provenance;
  body @3 :AnyPointer;
}

interface Store {
  get @0 (ref :ObjectRef) -> (object :StoredObject);
  query @1 (text :Text, schema :Text, limit :UInt32) -> (results :List(ObjectRef));
  put @2 (schema :Text, body :AnyPointer) -> (ref :ObjectRef);
  history @3 (ref :ObjectRef) -> (versions :List(ObjectRef));
}

# ---------- Transactions ----------

struct OutboxEntry {
  action @0 :Text;
  argumentLabels @1 :List(Label);
  needsApproval @2 :Bool;
}

interface Transaction {
  store @0 () -> (store :Store);         # store view on this session's branch
  diff @1 () -> (changed :List(ObjectRef));
  outbox @2 () -> (entries :List(OutboxEntry));
  commit @3 () -> (auditSeq :UInt64);
  abort @4 () -> ();
}

# ---------- Delegation ----------

struct Budget {
  wallSeconds @0 :UInt32;
  moneyMicros @1 :UInt64;
  tokens @2 :UInt64;
  calls @3 :UInt32;
}

struct Delegation {
  actions @0 :List(Text);        # action names; must be a subset of the grantor's
  scopeQuery @1 :Text;           # store objects reachable through this delegation
  effectCeiling @2 :Effect;      # above this, every call needs approval
  budget @3 :Budget;
  expiresAtUnixMs @4 :UInt64;
}

interface Principal {
  label @0 () -> (label :Label);
  delegate @1 (delegation :Delegation) -> (child :Principal);   # attenuating only
  begin @2 () -> (txn :Transaction);
  revoke @3 () -> ();
}

# ---------- Gate ----------

struct Invocation {
  action @0 :Text;
  arguments @1 :AnyPointer;
  argumentLabels @2 :List(Label);        # supplied by the executor, verified by gate
  argumentProvenance @3 :List(Provenance);
}

struct Decision {
  union {
    executed @0 :AnyPointer;             # result for read / localReversible
    queued @1 :UInt32;                   # outbox index
    denied @2 :Text;                     # reason
  }
  auditSeq @3 :UInt64;
}

interface Gate {
  invoke @0 (txn :Transaction, call :Invocation) -> (decision :Decision);
}

# ---------- Inference ----------

enum Priority {
  background @0;
  normal @1;
  interactive @2;
}

enum ModelTier {
  alwaysOn @0;
  planner @1;
  reader @2;
  remote @3;
}

struct ModelInfo {
  name @0 :Text;
  weightHash @1 :Data;           # signed, content-addressed weights
  tier @2 :ModelTier;
  contextTokens @3 :UInt32;
  local @4 :Bool;
}

struct SamplingParams {
  temperature @0 :Float32;
  topP @1 :Float32;
  maxTokens @2 :UInt32;
  seed @3 :UInt64;               # recorded for replay
}

struct InferRequest {
  model @0 :Text;
  adapters @1 :List(ObjectRef);  # their labels join into the output label
  context @2 :List(ObjectRef);   # assembled by the executor; model fetches nothing
  instruction @3 :Text;
  grammar @4 :Text;              # output schema name or plan-DSL grammar
  sampling @5 :SamplingParams;
  priority @6 :Priority;
}

struct InferResult {
  output @0 :Text;               # guaranteed to match the grammar
  label @1 :Label;               # join of context, adapter and instruction labels
  callRecord @2 :ObjectRef;      # replayable record of this call
}

interface Infer {
  models @0 () -> (models :List(ModelInfo));
  generate @1 (request :InferRequest) -> (result :InferResult);
  embed @2 (model :Text, input :ObjectRef) -> (vector :List(Float32), label :Label);
  replay @3 (callRecord :ObjectRef) -> (result :InferResult);
}

# ---------- Growth ----------

enum GrowthKind {
  memory @0;
  skill @1;
  lesson @2;
  adapter @3;
}

enum GrowthState {
  proposed @0;
  evaluated @1;
  adopted @2;
  rejected @3;
  rolledBack @4;
}

struct Memory {
  subject @0 :Text;
  fact @1 :Text;
  pinned @2 :Bool;
}

struct Skill {
  name @0 :Text;
  taskClass @1 :Text;
  procedure @2 :Text;            # plan-DSL template the planner may reuse
}

struct Adapter {
  baseWeightHash @0 :Data;
  deltaHash @1 :Data;
  rank @2 :UInt16;
  trainingSet @3 :List(ObjectRef);
}

struct EvalScore {
  suite @0 :Text;
  before @1 :Float32;
  after @2 :Float32;
}

struct EvalReport {
  task @0 :List(EvalScore);
  regression @1 :List(EvalScore);
  safety @2 :List(EvalScore);    # any decrease => automatic reject
  driftDetected @3 :Bool;
}

struct GrowthChange {
  id @0 :ObjectRef;
  kind @1 :GrowthKind;
  state @2 :GrowthState;
  label @3 :Label;               # join of source labels
  sources @4 :List(ObjectRef);   # sessions / audit entries it was learned from
  eval @5 :EvalReport;
  body :union {
    memory @6 :Memory;
    skill @7 :Skill;
    lesson @8 :Text;
    adapter @9 :Adapter;
  }
}

# Agents may propose; only the user (via the trusted surface) or a user-approved
# policy enforced by the gate may adopt. Nothing here can alter capabilities,
# labels policy, the gate, or the eval suites.
interface Growth {
  propose @0 (change :GrowthChange) -> (id :ObjectRef);
  evaluate @1 (id :ObjectRef) -> (report :EvalReport);
  list @2 (state :GrowthState) -> (changes :List(GrowthChange));
  rollback @3 (id :ObjectRef) -> ();
}

# ---------- Example app action ----------

interface Mail {
  draft @0 (to :List(Text), subject :Text, body :Text) -> (draft :ObjectRef)
      $effect(localReversible);

  send @1 (draft :ObjectRef) -> (messageId :Text)
      $effect(external)
      $integrityFloor(user)
      $egressTags([])
      $idempotent;
}
