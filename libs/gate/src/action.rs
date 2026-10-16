//! The action registry (docs/ARCHITECTURE.md §4.4).

use alloc::collections::BTreeMap;
use alloc::string::String;
use alloc::vec::Vec;
use fewshot_labels::{Integrity, Secrecy};

/// Identifies a registered action.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ActionId(pub u32);

/// What running an action does to the world.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Effect {
    /// Reads only.
    Read,
    /// Local change that can be undone.
    LocalReversible,
    /// Local change that cannot be undone.
    LocalIrreversible,
    /// Leaves the device: sends, pays, posts.
    External,
}

impl Effect {
    /// Runs at once; otherwise the effect waits in the outbox until commit.
    pub fn is_immediate(self) -> bool {
        matches!(self, Effect::Read | Effect::LocalReversible)
    }
}

/// How a parameter may be filled.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ParamKind {
    /// Any value.
    Open,
    /// One of a user-approved set. `Bounded`-integrity values may fill it
    /// without approval when they pick one of these options.
    Choice(Vec<Vec<u8>>),
}

/// A declared parameter.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Param {
    /// Name shown in approvals.
    pub name: String,
    /// How it may be filled.
    pub kind: ParamKind,
}

impl Param {
    /// An open parameter.
    pub fn open(name: impl Into<String>) -> Self {
        Param { name: name.into(), kind: ParamKind::Open }
    }

    /// A choice parameter.
    pub fn choice(name: impl Into<String>, options: impl IntoIterator<Item = Vec<u8>>) -> Self {
        Param { name: name.into(), kind: ParamKind::Choice(options.into_iter().collect()) }
    }
}

/// An action's declared metadata.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ActionSpec {
    /// Identifier.
    pub id: ActionId,
    /// Name, e.g. `"mail.send"`.
    pub name: String,
    /// Effect class.
    pub effect: Effect,
    /// Minimum argument integrity that needs no approval.
    pub integrity_floor: Integrity,
    /// Secrecy tags allowed to leave the device through this action
    /// (its egress tags intersected with the destination's clearance).
    pub egress_clearance: Secrecy,
    /// Declared parameters, in order.
    pub params: Vec<Param>,
}

/// Two actions registered with the same id.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DuplicateAction(pub ActionId);

/// Registered actions.
#[derive(Clone, Debug, Default)]
pub struct Registry {
    actions: BTreeMap<ActionId, ActionSpec>,
}

impl Registry {
    /// Empty registry.
    pub fn new() -> Self {
        Registry::default()
    }

    /// Registers an action.
    pub fn register(&mut self, spec: ActionSpec) -> Result<(), DuplicateAction> {
        if self.actions.contains_key(&spec.id) {
            return Err(DuplicateAction(spec.id));
        }
        self.actions.insert(spec.id, spec);
        Ok(())
    }

    /// Looks up an action.
    pub fn get(&self, id: ActionId) -> Option<&ActionSpec> {
        self.actions.get(&id)
    }
}
