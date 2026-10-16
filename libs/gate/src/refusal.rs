//! Structured refusals (docs/LIMITATIONS.md L9).

use alloc::string::String;
use core::fmt;

/// Why an approval was not accepted.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ApprovalError {
    /// The gate never issued this nonce to this session.
    UnknownNonce,
    /// The approval was already used.
    Reused,
    /// The approval has expired.
    Expired,
    /// The signature does not verify against the trusted approval key.
    BadSignature,
    /// The invocation differs from what was approved.
    DigestMismatch,
}

/// Why the gate refused.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reason {
    /// The session is not open.
    UnknownSession,
    /// No such action is registered.
    UnknownAction,
    /// The session holds no capability for the action (I1).
    MissingCapability,
    /// Wrong number of arguments.
    WrongArity,
    /// An argument handle does not resolve in this session.
    UnknownHandle,
    /// Argument secrecy is not cleared to leave the device this way (I3).
    EgressNotCleared,
    /// A presented approval was rejected (ADR-0006).
    ApprovalInvalid(ApprovalError),
}

/// Who can grant what would make the call succeed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Grantor {
    /// The user, through the trusted surface.
    User,
    /// An administrator policy.
    Admin,
    /// The system manifest.
    Manifest,
    /// Nobody: the call is malformed.
    None,
}

/// A refusal: reason, specifics, remedy and who can grant it.
/// Agents must not retry a refusal unchanged.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Refusal {
    /// Machine-readable reason.
    pub reason: Reason,
    /// Specifics.
    pub detail: String,
    /// What would make the call succeed.
    pub remedy: String,
    /// Who can provide it.
    pub grantor: Grantor,
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}: {} (remedy: {}; grantor: {:?})", self.reason, self.detail, self.remedy, self.grantor)
    }
}
