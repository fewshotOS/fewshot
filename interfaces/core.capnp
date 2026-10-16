# Fewshot core interfaces — DRAFT v0.
# Holding a reference to an interface is holding the authority to use it.

@0xc95c9024d3404725;

# ---------- Labels ----------

enum IntegrityLevel {
  untrustedWeb @0;
  untrustedLegacy @1;
  thirdParty @2;
  bounded @3;                    # certified-transformer output: may only select pre-approved options
  systemApp @4;
  user @5;
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
annotation postcondition(method) :Text;   # read-only check run after the effect
annotation draftFor(method) :Text;        # this method creates a local draft of the named external action

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
  update @4 (base :ObjectRef, body :AnyPointer) -> (result :UpdateResult);  # required for agents
}

struct UpdateResult {
  union {
    written @0 :ObjectRef;
    stale @1 :ObjectRef;         # current version; re-read and merge
  }
}

# ---------- Transactions ----------

struct OutboxEntry {
  action @0 :Text;
  digest @1 :Data;               # invocation digest (ADR-0006)
  needsApproval @2 :Bool;
}

interface Transaction {
  store @0 () -> (store :Store);         # store view on this session's branch
  diff @1 () -> (changed :List(ObjectRef));
  outbox @2 () -> (entries :List(OutboxEntry));
  commit @3 () -> (auditSeq :UInt64);
  abort @4 () -> ();
  checkpoint @5 () -> (auditSeq :UInt64);  # approve + commit outbox so far, continue on a new branch
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

struct GoalStep {
  description @0 :Text;
  auditSeq @1 :UInt64;           # 0 while open
}

struct GoalLedger {
  goal @0 :Text;                 # user's request, verbatim
  constraints @1 :List(Text);
  done @2 :List(GoalStep);
  open @3 :List(GoalStep);
}

interface Principal {
  label @0 () -> (label :Label);
  delegate @1 (delegation :Delegation) -> (child :Principal);   # attenuating only
  begin @2 () -> (txn :Transaction);
  revoke @3 () -> ();
}

# ---------- Gate ----------

# ---------- Value table (ADR-0005) ----------
# Agents hold only handles; labels and provenance live in labeld.

struct ValueHandle {
  id @0 :UInt64;                 # session-scoped, unforgeable via the ValueTable capability
}

interface ValueTable {
  intern @0 (value :AnyPointer, source :ObjectRef) -> (handle :ValueHandle);
  derive @1 (op :Text, inputs :List(ValueHandle)) -> (handle :ValueHandle);  # label = join of inputs
  read @2 (handle :ValueHandle) -> (value :AnyPointer);                      # raises caller's label
  label @3 (handle :ValueHandle) -> (label :Label, provenance :Provenance);
}

# ---------- Approvals (ADR-0006) ----------

struct SignedApproval {
  digests @0 :List(Data);        # one or more invocation digests (batched approval)
  nonce @1 :Data;
  expiresAtUnixMs @2 :UInt64;
  policy @3 :ObjectRef;          # set when a standing policy authorised it
  signature @4 :Data;            # trusted UI path key
}

struct Invocation {
  action @0 :Text;
  arguments @1 :List(ValueHandle);       # gate resolves labels itself via labeld
}

enum RefusalReason {
  missingCapability @0;
  labelConflict @1;
  budgetExhausted @2;
  staleVersion @3;
  approvalDenied @4;
  policyViolation @5;
  postconditionFailed @6;
}

enum Grantor {
  user @0;
  admin @1;
  manifest @2;
  none @3;
}

struct Refusal {
  reason @0 :RefusalReason;
  detail @1 :Text;
  remedy @2 :Text;
  grantor @3 :Grantor;
}

struct PostconditionResult {
  check @0 :Text;
  passed @1 :Bool;
  detail @2 :Text;
}

struct Decision {
  union {
    executed @0 :AnyPointer;             # result for read / localReversible
    queued @1 :UInt32;                   # outbox index
    denied @2 :Refusal;
  }
  auditSeq @3 :UInt64;
  postcondition @4 :PostconditionResult; # set after the effect runs
  digest @5 :Data;                       # invocation digest
  approval @6 :SignedApproval;           # set when the effect was approved
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

# Held only by the trusted approval surface, and by the gate when enforcing a
# user-approved policy. adopt fails on any safety decrease or detected drift.
interface GrowthAdmin {
  adopt @0 (id :ObjectRef) -> (auditSeq :UInt64);
  reject @1 (id :ObjectRef, reason :Text) -> ();
}

# ---------- Example app action ----------

interface Mail {
  draft @0 (to :List(Text), subject :Text, body :Text) -> (draft :ObjectRef)
      $effect(localReversible)
      $draftFor("send");

  send @1 (draft :ObjectRef) -> (messageId :Text)
      $effect(external)
      $integrityFloor(user)
      $egressTags([])
      $idempotent;
}
