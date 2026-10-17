//! Host abstraction for the policy core.
//!
//! The core crates are `no_std` and reach the outside world only through these
//! traits, so the same code runs in the portable runtime (ADR-0007) and as
//! seL4 components.
#![cfg_attr(not(feature = "std"), no_std)]

use core::cell::Cell;

/// Wall-clock time.
pub trait Clock {
    /// Milliseconds since the Unix epoch.
    fn now_ms(&self) -> u64;
}

impl<C: Clock + ?Sized> Clock for &C {
    fn now_ms(&self) -> u64 {
        (**self).now_ms()
    }
}

/// A clock that only moves when told to. For tests and deterministic replay.
#[derive(Debug, Default)]
pub struct ManualClock(Cell<u64>);

impl ManualClock {
    /// Starts at `ms`.
    pub fn new(ms: u64) -> Self {
        ManualClock(Cell::new(ms))
    }

    /// Moves time forward.
    pub fn advance(&self, ms: u64) {
        self.0.set(self.0.get() + ms);
    }
}

impl Clock for ManualClock {
    fn now_ms(&self) -> u64 {
        self.0.get()
    }
}

/// The host OS clock.
#[cfg(feature = "std")]
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemClock;

#[cfg(feature = "std")]
impl Clock for SystemClock {
    fn now_ms(&self) -> u64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manual_clock_advances() {
        let c = ManualClock::new(10);
        c.advance(5);
        assert_eq!(c.now_ms(), 15);
    }

    #[cfg(feature = "std")]
    #[test]
    fn system_clock_is_after_2025() {
        assert!(SystemClock.now_ms() > 1_735_689_600_000);
    }
}
