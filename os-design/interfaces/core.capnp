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

interface Infer {
  generate @0 (model :Text, prompt :Text, outputSchema :Text, priority :Priority)
      -> (output :Text, label :Label);
  embed @1 (model :Text, input :Text) -> (vector :List(Float32));
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
