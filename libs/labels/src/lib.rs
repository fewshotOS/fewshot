//! Information-flow labels (docs/ARCHITECTURE.md §4.1, ADR-0003).
//!
//! A [`Label`] has a secrecy part (a set of tags: who may eventually see the
//! data) and an integrity part (how far the data may be trusted to steer
//! actions). Labels form a lattice; [`Label::join`] is its least upper bound.
//! The laws are proven for the reference model in `specs/verus/labels.rs` and
//! property-tested here.
#![no_std]

use core::fmt;

/// How far data may be trusted to steer actions, lowest first.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u8)]
pub enum Integrity {
    /// Content from the open web.
    UntrustedWeb = 0,
    /// Output of legacy apps in the Linux VM.
    UntrustedLegacy = 1,
    /// Third-party apps and services.
    ThirdParty = 2,
    /// Output of a certified transformer: may only select pre-approved options.
    Bounded = 3,
    /// System components.
    SystemApp = 4,
    /// The user, through a trusted input path.
    User = 5,
}

/// A secrecy tag, `0..64`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Tag(u8);

impl Tag {
    /// Number of distinct tags.
    pub const COUNT: u8 = 64;

    /// Creates a tag, or `None` if `index >= Tag::COUNT`.
    pub const fn new(index: u8) -> Option<Self> {
        if index < Self::COUNT { Some(Tag(index)) } else { None }
    }

    /// The tag's index.
    pub const fn index(self) -> u8 {
        self.0
    }
}

/// A set of secrecy tags.
#[derive(Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct Secrecy(u64);

impl Secrecy {
    /// No tags.
    pub const EMPTY: Secrecy = Secrecy(0);

    /// Builds a set from raw bits (bit `i` = tag `i`).
    pub const fn from_bits(bits: u64) -> Self {
        Secrecy(bits)
    }

    /// Raw bits.
    pub const fn bits(self) -> u64 {
        self.0
    }

    /// Adds a tag.
    pub const fn with(self, tag: Tag) -> Self {
        Secrecy(self.0 | (1 << tag.0))
    }

    /// Whether `tag` is in the set.
    pub const fn contains(self, tag: Tag) -> bool {
        self.0 & (1 << tag.0) != 0
    }

    /// Set union.
    pub const fn union(self, other: Secrecy) -> Self {
        Secrecy(self.0 | other.0)
    }

    /// Whether every tag in `self` is also in `other`.
    pub const fn is_subset(self, other: Secrecy) -> bool {
        self.0 & other.0 == self.0
    }
}

impl fmt::Debug for Secrecy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_set().entries((0..Tag::COUNT).filter(|i| self.0 & (1 << i) != 0)).finish()
    }
}

/// A secrecy set paired with an integrity level.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Label {
    /// Who may eventually see the data.
    pub secrecy: Secrecy,
    /// How far the data may be trusted to steer actions.
    pub integrity: Integrity,
}

impl Label {
    /// The label of "no data yet": no secrecy, full integrity. Identity for [`Label::join`].
    pub const TOP: Label = Label { secrecy: Secrecy::EMPTY, integrity: Integrity::User };

    /// Creates a label.
    pub const fn new(secrecy: Secrecy, integrity: Integrity) -> Self {
        Label { secrecy, integrity }
    }

    /// Least upper bound: union of secrecy, minimum of integrity.
    pub fn join(self, other: Label) -> Label {
        Label { secrecy: self.secrecy.union(other.secrecy), integrity: self.integrity.min(other.integrity) }
    }

    /// Whether data labeled `self` may flow into something labeled `to`:
    /// no secrecy tag is lost and integrity is not raised.
    pub fn flows_to(self, to: Label) -> bool {
        self.secrecy.is_subset(to.secrecy) && self.integrity >= to.integrity
    }

    /// The label a reader holds after reading data labeled `data`.
    /// Secrecy can only grow and integrity can only fall.
    pub fn after_read(self, data: Label) -> Label {
        self.join(data)
    }

    /// Join of an iterator of labels; [`Label::TOP`] when empty.
    pub fn join_all<I: IntoIterator<Item = Label>>(labels: I) -> Label {
        labels.into_iter().fold(Label::TOP, Label::join)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn integrity() -> impl Strategy<Value = Integrity> {
        prop_oneof![
            Just(Integrity::UntrustedWeb),
            Just(Integrity::UntrustedLegacy),
            Just(Integrity::ThirdParty),
            Just(Integrity::Bounded),
            Just(Integrity::SystemApp),
            Just(Integrity::User),
        ]
    }

    fn label() -> impl Strategy<Value = Label> {
        (any::<u64>(), integrity()).prop_map(|(s, i)| Label::new(Secrecy::from_bits(s), i))
    }

    /// A label that flows to `to`: a subset of its tags, at least its integrity.
    fn below(to: Label, mask: u64, i: Integrity) -> Label {
        Label::new(Secrecy::from_bits(to.secrecy.bits() & mask), i.max(to.integrity))
    }

    // Same laws as specs/verus/labels.rs.
    proptest! {
        #[test]
        fn flows_reflexive(a in label()) {
            prop_assert!(a.flows_to(a));
        }

        #[test]
        fn flows_transitive(c in label(), mb in any::<u64>(), ma in any::<u64>(), ib in integrity(), ia in integrity()) {
            let b = below(c, mb, ib);
            let a = below(b, ma, ia);
            prop_assert!(a.flows_to(b) && b.flows_to(c));
            prop_assert!(a.flows_to(c));
        }

        #[test]
        fn join_is_upper_bound(a in label(), b in label()) {
            prop_assert!(a.flows_to(a.join(b)));
            prop_assert!(b.flows_to(a.join(b)));
        }

        #[test]
        fn join_is_least(c in label(), ma in any::<u64>(), mb in any::<u64>(), ia in integrity(), ib in integrity()) {
            let (a, b) = (below(c, ma, ia), below(c, mb, ib));
            prop_assert!(a.flows_to(c) && b.flows_to(c));
            prop_assert!(a.join(b).flows_to(c));
        }

        #[test]
        fn join_laws(a in label(), b in label(), c in label()) {
            prop_assert_eq!(a.join(b), b.join(a));
            prop_assert_eq!(a.join(b).join(c), a.join(b.join(c)));
            prop_assert_eq!(a.join(a), a);
            prop_assert_eq!(Label::TOP.join(a), a);
        }

        #[test]
        fn read_is_monotone(r in label(), d in label()) {
            let after = r.after_read(d);
            prop_assert!(r.secrecy.is_subset(after.secrecy));
            prop_assert!(after.integrity <= r.integrity);
            prop_assert!(after.integrity <= d.integrity);
        }

        #[test]
        fn taint_is_sticky(r in label(), later in label(), s in any::<u64>()) {
            let web = Label::new(Secrecy::from_bits(s), Integrity::UntrustedWeb);
            prop_assert_eq!(r.after_read(web).after_read(later).integrity, Integrity::UntrustedWeb);
        }
    }

    #[test]
    fn tags() {
        assert!(Tag::new(63).is_some());
        assert!(Tag::new(64).is_none());
        let health = Tag::new(3).unwrap();
        let s = Secrecy::EMPTY.with(health);
        assert!(s.contains(health));
        assert!(!s.contains(Tag::new(4).unwrap()));
    }
}
