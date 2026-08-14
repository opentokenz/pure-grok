//! xAI control-plane / marketing surfaces.
//!
//! This fork keeps inference and the local TUI, but does not apply remote
//! fleet policy, managed-config sync, announcements, tips, access gates, or
//! feedback unless the operator explicitly sets `GROK_CONTROL_PLANE=1`.

/// Env that re-enables the official control plane (tests / explicit opt-in).
pub const ENABLE_ENV: &str = "GROK_CONTROL_PLANE";

/// Whether this process should talk to xAI control-plane and marketing
/// endpoints. Default **off**.
pub fn enabled() -> bool {
    crate::agent::config::env_bool(ENABLE_ENV).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    #[test]
    fn default_is_off_when_env_unset() {
        let _guard = crate::env::EnvVarGuard::remove(super::ENABLE_ENV);
        assert!(!super::enabled());
    }

    #[test]
    fn env_true_enables() {
        let _guard = crate::env::EnvVarGuard::set(super::ENABLE_ENV, "1");
        assert!(super::enabled());
    }
}
