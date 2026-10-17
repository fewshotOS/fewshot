//! Capabilities (I1).

use crate::action::ActionId;
use alloc::collections::BTreeSet;

/// The actions a session may invoke. Authority is never ambient.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CapSet(BTreeSet<ActionId>);

impl CapSet {
    /// A set holding exactly these actions.
    pub fn new(actions: impl IntoIterator<Item = ActionId>) -> Self {
        CapSet(actions.into_iter().collect())
    }

    /// Whether the set holds `action`.
    pub fn contains(&self, action: ActionId) -> bool {
        self.0.contains(&action)
    }

    /// A subset for delegation: only actions in both `self` and `keep`.
    /// Delegation can narrow authority, never widen it.
    pub fn attenuate(&self, keep: impl IntoIterator<Item = ActionId>) -> CapSet {
        CapSet(keep.into_iter().filter(|a| self.0.contains(a)).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attenuate_never_widens() {
        let parent = CapSet::new([ActionId(1), ActionId(2)]);
        let child = parent.attenuate([ActionId(2), ActionId(3)]);
        assert!(child.contains(ActionId(2)));
        assert!(!child.contains(ActionId(1)));
        assert!(!child.contains(ActionId(3)));
    }
}
