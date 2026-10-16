-------------------------------- MODULE Txn --------------------------------
(***************************************************************************)
(* Agent sessions, transaction branches, the outbox, checkpoints, sagas,   *)
(* the gate's audit ordering and digest-bound approvals.                   *)
(*                                                                         *)
(* See docs/ARCHITECTURE.md §4.3 (txn), §4.5 (gate), ADR-0006 (approvals). *)
(*                                                                         *)
(* Checked properties:                                                     *)
(*   I4  AuditBeforeEffect      every external effect is audited first     *)
(*   I5  MainChangesOnlyOnPublish / AbortLeavesMainUnchanged               *)
(*       local writes reach the committed store only on publish            *)
(*   ADR-0006  ApprovedOnly, ApprovalBinding, NoDoubleExec                 *)
(*   Sagas     SagaCompensates                                             *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Sessions,       \* agent sessions
    Keys,           \* store keys
    Values,         \* store values
    Actions,        \* external action kinds
    NeedsApproval,  \* actions that require a user approval
    Compensable,    \* actions with a declared compensation
    MaxEffects      \* bound on queued effects (model size)

ASSUME NeedsApproval \subseteq Actions
ASSUME Compensable \subseteq Actions
ASSUME MaxEffects \in Nat

NoSession == "none"
EffectIds == 1..MaxEffects
V0 == CHOOSE v \in Values : TRUE

VARIABLES
    main,      \* committed store                         [Keys -> Values]
    base,      \* snapshot at begin / last checkpoint      [Sessions -> [Keys -> Values]]
    branch,    \* session working copy                     [Sessions -> [Keys -> Values]]
    written,   \* keys written on the branch               [Sessions -> SUBSET Keys]
    outbox,    \* queued external effects                  [Sessions -> Seq(EffectIds)]
    act,       \* effect id -> action kind (registry)      [EffectIds -> Actions \cup {"none"}]
    owner,     \* effect id -> session                     [EffectIds -> Sessions \cup {NoSession}]
    nextId,    \* next fresh effect id
    status,    \* session lifecycle
    cont,      \* current commit is a checkpoint           [Sessions -> BOOLEAN]
    done,      \* effects executed in the current commit   [Sessions -> Seq(EffectIds)]
    approved,  \* effect ids with a signed approval
    used,      \* approvals already consumed (single use)
    lock,      \* session holding the commit lock
    log        \* global event log (audit trail + world effects)

vars == <<main, base, branch, written, outbox, act, owner, nextId, status,
          cont, done, approved, used, lock, log>>

States == {"idle", "active", "committing", "compensating", "committed", "aborted"}

Event(t, e, s) == [type |-> t, eid |-> e, ses |-> s]

Range(q) == {q[i] : i \in 1..Len(q)}

Audited(e) == \E i \in 1..Len(log) : log[i] = Event("audit", e, owner[e])

-----------------------------------------------------------------------------

TypeOK ==
    /\ main \in [Keys -> Values]
    /\ base \in [Sessions -> [Keys -> Values]]
    /\ branch \in [Sessions -> [Keys -> Values]]
    /\ written \in [Sessions -> SUBSET Keys]
    /\ \A s \in Sessions : Range(outbox[s]) \subseteq EffectIds
    /\ act \in [EffectIds -> Actions \cup {"none"}]
    /\ owner \in [EffectIds -> Sessions \cup {NoSession}]
    /\ nextId \in 1..(MaxEffects + 1)
    /\ status \in [Sessions -> States]
    /\ cont \in [Sessions -> BOOLEAN]
    /\ \A s \in Sessions : Range(done[s]) \subseteq EffectIds
    /\ approved \subseteq EffectIds
    /\ used \subseteq EffectIds
    /\ lock \in Sessions \cup {NoSession}

Init ==
    /\ main = [k \in Keys |-> V0]
    /\ base = [s \in Sessions |-> main]
    /\ branch = [s \in Sessions |-> main]
    /\ written = [s \in Sessions |-> {}]
    /\ outbox = [s \in Sessions |-> <<>>]
    /\ act = [e \in EffectIds |-> "none"]
    /\ owner = [e \in EffectIds |-> NoSession]
    /\ nextId = 1
    /\ status = [s \in Sessions |-> "idle"]
    /\ cont = [s \in Sessions |-> FALSE]
    /\ done = [s \in Sessions |-> <<>>]
    /\ approved = {}
    /\ used = {}
    /\ lock = NoSession
    /\ log = <<>>

-----------------------------------------------------------------------------
(* Session work on its own branch                                          *)

Begin(s) ==
    /\ status[s] = "idle"
    /\ status' = [status EXCEPT ![s] = "active"]
    /\ base' = [base EXCEPT ![s] = main]
    /\ branch' = [branch EXCEPT ![s] = main]
    /\ written' = [written EXCEPT ![s] = {}]
    /\ UNCHANGED <<main, outbox, act, owner, nextId, cont, done, approved, used, lock, log>>

Write(s, k, v) ==
    /\ status[s] = "active"
    /\ branch' = [branch EXCEPT ![s][k] = v]
    /\ written' = [written EXCEPT ![s] = @ \cup {k}]
    /\ UNCHANGED <<main, base, outbox, act, owner, nextId, status, cont, done, approved, used, lock, log>>

\* An external effect goes to the outbox; it does not run.
Queue(s, a) ==
    /\ status[s] = "active"
    /\ nextId \in EffectIds
    /\ outbox' = [outbox EXCEPT ![s] = Append(@, nextId)]
    /\ act' = [act EXCEPT ![nextId] = a]
    /\ owner' = [owner EXCEPT ![nextId] = s]
    /\ nextId' = nextId + 1
    /\ UNCHANGED <<main, base, branch, written, status, cont, done, approved, used, lock, log>>

\* The user signs an approval over one queued effect's digest.
Approve(e) ==
    /\ e \in EffectIds
    /\ act[e] \in NeedsApproval
    /\ e \notin approved
    /\ owner[e] \in Sessions
    /\ status[owner[e]] \in {"active", "committing"}
    /\ e \in Range(outbox[owner[e]])
    /\ approved' = approved \cup {e}
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, status, cont, done, used, lock, log>>

Abort(s) ==
    /\ status[s] = "active"
    /\ status' = [status EXCEPT ![s] = "aborted"]
    /\ outbox' = [outbox EXCEPT ![s] = <<>>]
    /\ log' = Append(log, Event("abort", 0, s))
    /\ UNCHANGED <<main, base, branch, written, act, owner, nextId, cont, done, approved, used, lock>>

-----------------------------------------------------------------------------
(* Commit and checkpoint                                                   *)

NotStale(s) == \A k \in written[s] : main[k] = base[s][k]

StartCommit(s, isCheckpoint) ==
    /\ status[s] = "active"
    /\ lock = NoSession
    /\ NotStale(s)
    /\ isCheckpoint => outbox[s] # <<>>
    /\ lock' = s
    /\ status' = [status EXCEPT ![s] = "committing"]
    /\ cont' = [cont EXCEPT ![s] = isCheckpoint]
    /\ done' = [done EXCEPT ![s] = <<>>]
    /\ log' = Append(log, Event("commit", 0, s))
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, approved, used>>

\* Version-checked commit: a stale branch is refused (LIMITATIONS.md L3).
RefuseStale(s) ==
    /\ status[s] = "active"
    /\ lock = NoSession
    /\ ~NotStale(s)
    /\ status' = [status EXCEPT ![s] = "aborted"]
    /\ outbox' = [outbox EXCEPT ![s] = <<>>]
    /\ log' = Append(log, Event("stale", 0, s))
    /\ UNCHANGED <<main, base, branch, written, act, owner, nextId, cont, done, approved, used, lock>>

\* Gate step 5: audit entry for the next outbox effect.
AuditHead(s) ==
    /\ status[s] = "committing"
    /\ outbox[s] # <<>>
    /\ ~Audited(Head(outbox[s]))
    /\ log' = Append(log, Event("audit", Head(outbox[s]), s))
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, status, cont, done, approved, used, lock>>

CanRun(e) == act[e] \in NeedsApproval => e \in approved \ used

\* The external effect runs and succeeds.
ExecHead(s) ==
    /\ status[s] = "committing"
    /\ outbox[s] # <<>>
    /\ LET e == Head(outbox[s]) IN
        /\ Audited(e)
        /\ CanRun(e)
        /\ log' = Append(log, Event("exec", e, s))
        /\ done' = [done EXCEPT ![s] = Append(@, e)]
        /\ outbox' = [outbox EXCEPT ![s] = Tail(@)]
        /\ used' = IF act[e] \in NeedsApproval THEN used \cup {e} ELSE used
    /\ UNCHANGED <<main, base, branch, written, act, owner, nextId, status, cont, approved, lock>>

\* The external effect runs and fails: start compensating.
FailHead(s) ==
    /\ status[s] = "committing"
    /\ outbox[s] # <<>>
    /\ LET e == Head(outbox[s]) IN
        /\ Audited(e)
        /\ CanRun(e)
        /\ log' = Append(log, Event("fail", e, s))
        /\ used' = IF act[e] \in NeedsApproval THEN used \cup {e} ELSE used
    /\ status' = [status EXCEPT ![s] = "compensating"]
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, cont, done, approved, lock>>

\* The user declines the approval the gate is waiting on.
Deny(s) ==
    /\ status[s] = "committing"
    /\ outbox[s] # <<>>
    /\ act[Head(outbox[s])] \in NeedsApproval
    /\ Head(outbox[s]) \notin approved
    /\ log' = Append(log, Event("deny", Head(outbox[s]), s))
    /\ status' = [status EXCEPT ![s] = "compensating"]
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, cont, done, approved, used, lock>>

\* Saga: undo already-executed effects of this commit in reverse order.
CompensateLast(s) ==
    /\ status[s] = "compensating"
    /\ done[s] # <<>>
    /\ LET e == done[s][Len(done[s])] IN
        log' = Append(log, Event(IF act[e] \in Compensable THEN "comp" ELSE "uncomp", e, s))
    /\ done' = [done EXCEPT ![s] = SubSeq(@, 1, Len(@) - 1)]
    /\ UNCHANGED <<main, base, branch, written, outbox, act, owner, nextId, status, cont, approved, used, lock>>

EndCompensate(s) ==
    /\ status[s] = "compensating"
    /\ done[s] = <<>>
    /\ status' = [status EXCEPT ![s] = "aborted"]
    /\ outbox' = [outbox EXCEPT ![s] = <<>>]
    /\ lock' = NoSession
    /\ log' = Append(log, Event("abort", 0, s))
    /\ UNCHANGED <<main, base, branch, written, act, owner, nextId, cont, done, approved, used>>

\* All effects ran: publish the branch. A checkpoint continues on a fresh branch.
Publish(s) ==
    /\ status[s] = "committing"
    /\ outbox[s] = <<>>
    /\ LET merged == [k \in Keys |-> IF k \in written[s] THEN branch[s][k] ELSE main[k]] IN
        /\ main' = merged
        /\ IF cont[s]
             THEN /\ status' = [status EXCEPT ![s] = "active"]
                  /\ base' = [base EXCEPT ![s] = merged]
                  /\ branch' = [branch EXCEPT ![s] = merged]
                  /\ written' = [written EXCEPT ![s] = {}]
             ELSE /\ status' = [status EXCEPT ![s] = "committed"]
                  /\ UNCHANGED <<base, branch, written>>
    /\ done' = [done EXCEPT ![s] = <<>>]
    /\ lock' = NoSession
    /\ log' = Append(log, Event("publish", 0, s))
    /\ UNCHANGED <<outbox, act, owner, nextId, cont, approved, used>>

-----------------------------------------------------------------------------

Next ==
    \/ \E s \in Sessions :
        \/ Begin(s)
        \/ \E k \in Keys, v \in Values : Write(s, k, v)
        \/ \E a \in Actions : Queue(s, a)
        \/ Abort(s)
        \/ StartCommit(s, FALSE)
        \/ StartCommit(s, TRUE)
        \/ RefuseStale(s)
        \/ AuditHead(s)
        \/ ExecHead(s)
        \/ FailHead(s)
        \/ Deny(s)
        \/ CompensateLast(s)
        \/ EndCompensate(s)
        \/ Publish(s)
    \/ \E e \in EffectIds : Approve(e)

Spec == Init /\ [][Next]_vars

\* State constraint for model checking: bounds checkpoint loops.
LogBound == Len(log) <= 14

-----------------------------------------------------------------------------
(* Properties                                                              *)

\* I4: every executed external effect has an earlier audit entry.
AuditBeforeEffect ==
    \A i \in 1..Len(log) :
        log[i].type = "exec" =>
            \E j \in 1..(i - 1) : log[j] = Event("audit", log[i].eid, log[i].ses)

\* ADR-0006: an effect that needs approval runs only with one.
ApprovedOnly ==
    \A i \in 1..Len(log) :
        (log[i].type = "exec" /\ act[log[i].eid] \in NeedsApproval) => log[i].eid \in approved

\* ADR-0006: an approval is consumed only by the effect whose digest it signs.
ApprovalBinding == used \subseteq approved

\* ADR-0006: approvals are single-use; no effect runs twice.
NoDoubleExec ==
    \A i, j \in 1..Len(log) :
        (log[i].type \in {"exec", "fail"} /\ log[j].type \in {"exec", "fail"}
            /\ log[i].eid = log[j].eid) => i = j

\* No external effect after a session has ended.
NoEffectAfterEnd ==
    \A i, j \in 1..Len(log) :
        (log[i].type = "abort" /\ log[j].type = "exec" /\ log[j].ses = log[i].ses) => j < i

\* Commits are serialised by the lock.
LockHeldWhileCommitting ==
    \A s \in Sessions : status[s] \in {"committing", "compensating"} => lock = s

\* Sagas: once a failed commit has ended, every compensable effect it
\* executed has been compensated after the failure.
PublishedBetween(s, x, f) == \E p \in (x + 1)..(f - 1) : log[p] = Event("publish", 0, s)

SagaCompensates ==
    \A s \in Sessions : status[s] = "aborted" =>
        \A f \in 1..Len(log) :
            (log[f].type \in {"fail", "deny"} /\ log[f].ses = s) =>
                \A x \in 1..(f - 1) :
                    (/\ log[x].type = "exec" /\ log[x].ses = s
                     /\ act[log[x].eid] \in Compensable
                     /\ ~PublishedBetween(s, x, f))
                        => \E c \in (f + 1)..Len(log) : log[c] = Event("comp", log[x].eid, s)

\* I5: the committed store changes only when a session publishes,
\* i.e. after all of its external effects ran.
MainChangesOnlyOnPublish ==
    [][main' # main => \E s \in Sessions : status[s] = "committing" /\ outbox[s] = <<>>]_vars

\* I5: ending a session by abort, refusal or failed saga never touches main.
AbortLeavesMainUnchanged ==
    [][\A s \in Sessions : (status'[s] = "aborted" /\ status[s] # "aborted") => main' = main]_vars

=============================================================================
