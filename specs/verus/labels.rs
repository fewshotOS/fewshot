//! Information-flow labels (docs/ARCHITECTURE.md §4.1, ADR-0003).
//!
use vstd::prelude::*;

verus! {

// Integrity levels, lowest to highest.
pub const UNTRUSTED_WEB: u8 = 0;
pub const UNTRUSTED_LEGACY: u8 = 1;
pub const THIRD_PARTY: u8 = 2;
pub const BOUNDED: u8 = 3;
pub const SYSTEM_APP: u8 = 4;
pub const USER: u8 = 5;

#[derive(Clone, Copy)]
pub struct Label {
    /// Secrecy tags as a bitset: bit i set means tag i is present.
    pub secrecy: u64,
    pub integrity: u8,
}

/// The label of "no data yet": no secrecy, full integrity.
pub open spec fn top() -> Label {
    Label { secrecy: 0, integrity: USER }
}

pub open spec fn subset(a: u64, b: u64) -> bool {
    a & b == a
}

/// Data labeled `from` may flow into something labeled `to`:
/// no secrecy tag is lost and integrity is not raised.
pub open spec fn flows(from: Label, to: Label) -> bool {
    subset(from.secrecy, to.secrecy) && from.integrity >= to.integrity
}

pub open spec fn min_u8(a: u8, b: u8) -> u8 {
    if a <= b { a } else { b }
}

/// Least upper bound: union of secrecy, minimum of integrity.
pub open spec fn join(a: Label, b: Label) -> Label {
    Label { secrecy: a.secrecy | b.secrecy, integrity: min_u8(a.integrity, b.integrity) }
}

pub fn join_exec(a: &Label, b: &Label) -> (r: Label)
    ensures r == join(*a, *b),
{
    Label {
        secrecy: a.secrecy | b.secrecy,
        integrity: if a.integrity <= b.integrity { a.integrity } else { b.integrity },
    }
}

pub fn can_flow(from: &Label, to: &Label) -> (r: bool)
    ensures r == flows(*from, *to),
{
    (from.secrecy & to.secrecy) == from.secrecy && from.integrity >= to.integrity
}

// ---------------------------------------------------------------------------
// The flow relation is a partial order.

pub proof fn lemma_flows_reflexive(a: Label)
    ensures flows(a, a),
{
    let x = a.secrecy;
    assert(x & x == x) by (bit_vector);
}

pub proof fn lemma_flows_transitive(a: Label, b: Label, c: Label)
    requires flows(a, b), flows(b, c),
    ensures flows(a, c),
{
    let (x, y, z) = (a.secrecy, b.secrecy, c.secrecy);
    assert((x & y == x && y & z == y) ==> x & z == x) by (bit_vector);
}

// ---------------------------------------------------------------------------
// join is the least upper bound.

pub proof fn lemma_join_upper_bound(a: Label, b: Label)
    ensures flows(a, join(a, b)), flows(b, join(a, b)),
{
    let (x, y) = (a.secrecy, b.secrecy);
    assert(x & (x | y) == x) by (bit_vector);
    assert(y & (x | y) == y) by (bit_vector);
}

pub proof fn lemma_join_least(a: Label, b: Label, c: Label)
    requires flows(a, c), flows(b, c),
    ensures flows(join(a, b), c),
{
    let (x, y, z) = (a.secrecy, b.secrecy, c.secrecy);
    assert((x & z == x && y & z == y) ==> (x | y) & z == (x | y)) by (bit_vector);
}

pub proof fn lemma_join_commutative(a: Label, b: Label)
    ensures join(a, b) == join(b, a),
{
    let (x, y) = (a.secrecy, b.secrecy);
    assert(x | y == y | x) by (bit_vector);
}

pub proof fn lemma_join_associative(a: Label, b: Label, c: Label)
    ensures join(join(a, b), c) == join(a, join(b, c)),
{
    let (x, y, z) = (a.secrecy, b.secrecy, c.secrecy);
    assert((x | y) | z == x | (y | z)) by (bit_vector);
}

pub proof fn lemma_join_idempotent(a: Label)
    ensures join(a, a) == a,
{
    let x = a.secrecy;
    assert(x | x == x) by (bit_vector);
}

pub proof fn lemma_top_is_identity(a: Label)
    requires a.integrity <= USER,
    ensures join(top(), a) == a,
{
    let x = a.secrecy;
    assert(0u64 | x == x) by (bit_vector);
}

// ---------------------------------------------------------------------------
// Labels only move in the safe direction automatically: reading data can
// add secrecy and lower integrity, never the reverse.

pub open spec fn after_read(reader: Label, data: Label) -> Label {
    join(reader, data)
}

pub proof fn lemma_read_is_monotone(reader: Label, data: Label)
    ensures
        subset(reader.secrecy, after_read(reader, data).secrecy),
        after_read(reader, data).integrity <= reader.integrity,
        after_read(reader, data).integrity <= data.integrity,
{
    lemma_join_upper_bound(reader, data);
}

/// A principal that has read untrusted web content can never again pass
/// an integrity floor above `UNTRUSTED_WEB` without an explicit endorsement.
pub proof fn lemma_taint_is_sticky(reader: Label, web: Label, later: Label)
    requires web.integrity == UNTRUSTED_WEB,
    ensures
        after_read(after_read(reader, web), later).integrity == UNTRUSTED_WEB,
{
}

} // verus!
