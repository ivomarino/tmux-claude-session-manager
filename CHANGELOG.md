# Changelog

All notable changes to this project are documented here. This fork enhances the upstream tmux-claude-session-manager with comprehensive session management features.

## [Unreleased]

### Planned
- `tcsm-doctor` command for health checks and cleanup
- Session diagnostics and orphaned process detection
- Automated cleanup of stale sessions
- CHANGELOG.md tracking (this file)
- CLAUDE.md development guide

---

## [2.0.0] - 2026-07-25

### Added
- **Multi-account support** with rate-limit tracking
  - `--account` parameter for `tcsm-start` to specify Claude account
  - Account validation against `accounts.json` (must be active)
  - Rate limit tier display in `tcsm-list` and `tcsm-status`
  - Per-session account tracking in registry
  - Account display names from metadata.organization
  - Helper functions: `validate_account()`, `get_rate_limit_tier()`, `get_account_display()`

- **Enhanced display output**
  - `tcsm-list`: Added Account and Rate Limit Tier columns
  - `tcsm-status`: Added per-session account summary section
  - Color-coded account display with organization names
  - Rate limit tier abbreviation for readability

- **Session registry schema extension**
  - Extended `tcsm-session-map.json` with `account` and `rate_limit_tier` fields
  - Automatic migration of existing sessions to new schema
  - Backward compatible: old sessions default to "primary" account

- **Graceful session termination** (commit b738764)
  - Signal escalation: SIGINT (5s) → SIGTERM (2s) → SIGKILL
  - Process existence checking with `kill -0`
  - Detailed logging of shutdown progress
  - Timeout fallback for unresponsive processes
  - Allows Claude to save state before termination

- **Documentation enhancements**
  - Account management section in `skills/tcsm.md`
  - Multi-account support in README.md fork enhancements
  - Graceful shutdown behavior documentation
  - Claude Code path display limitation documented
  - Example accounts.json structure

### Fixed
- Session termination now gracefully exits Claude instead of force-killing
- Old sessions properly migrated to include account information
- Rate-limit scripts updated to use new tcsm-session-map.json path
  - `claude-rate-limit-monitor` - account lookup fixed
  - `claude-session-rate-limit` - registry path updated
  - `claude-system-status` - display format updated

### Changed
- Account configuration: switched primary/secondary account IDs
  - Secondary account now inactive
  - Primary account now active for web UI compatibility
  - All sessions registered under active primary account

### Removed
- Legacy session registry references (moved to ~/.claude/legacy/)
- Old claude-* namespaced tmux sessions (consolidated to TCSM)
- Obsolete rate-limit script references to old paths

---

## [1.0.0] - 2026-07-24

### Added
- **TCSM Session Manager Skill**
  - Interactive sessions in tmux windows
  - Auto-registration with Claude CLI
  - Web UI integration via bridgeSessionId
  - Workspace trust pre-configuration
  - Git-aware project discovery
  - Project path resolution from configuration
  - Support for local and elevated (sudo) operations
  - Multi-project support with flexible naming

- **Git-Aware Project Discovery**
  - Auto-fallback to real git-controlled source repos
  - TCSM_SEARCH_ROOTS configuration for search paths
  - Fallback search when stub directories don't have git

- **Configuration Management**
  - `tcsm-projects.json` - Project path overrides
  - `accounts.json` - Claude account configuration
  - Template files for initialization

- **Installation Script**
  - Automated setup for new VMs
  - TENANT parameter for multi-tenant setups
  - Optional systemd service installation

- **Boot-Time Auto-Restoration**
  - `tcsm-restore.service` systemd unit
  - Auto-restore all registered sessions on login
  - Persistent session management across reboots

- **Session Management Functions**
  - `tcsm-start` - Create and start session
  - `tcsm-stop` - Stop running session
  - `tcsm-restart` - Restart session
  - `tcsm-list` - List all sessions with status
  - `tcsm-restore` - Restore sessions (boot-time)
  - `tcsm-status` - Show system health
  - `tcsm-remote` - Manage remote sessions via SSH

- **Documentation**
  - `skills/README.md` - Skill overview
  - `skills/tcsm.md` - Comprehensive documentation
  - `skills/USAGE.txt` - Quick reference card
  - `config/README.md` - Configuration guide
  - Fork enhancements in main README.md

### Known Issues
- Claude Code path display limitation for self-hosted GitLab
  - Shows organization/namespace instead of project name
  - Documented in troubleshooting section
  - Does not affect functionality

- Workspace trust dialog may appear once on initial session start
  - Workaround for Claude Code bug #9113
  - Pre-configuration + explicit config set used
  - Future restarts skip the prompt

### Compatibility
- ✅ Backward compatible with upstream
- ✅ tmux 3.2+
- ✅ macOS and Linux
- ✅ Generic paths (no hardcoding)
- ✅ Multi-VM ready

---

## [Upstream] - craftzdog/tmux-claude-session-manager

Original project features:
- Tmux session picker with live preview
- Claude agent status monitoring
- Smart agent jumping and management
- Interactive picker with keybindings

See https://github.com/craftzdog/tmux-claude-session-manager for upstream details.

---

## How to Read This File

This changelog follows [Keep a Changelog](https://keepachangelog.com/) format:
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for bug fixes
- **Security** for security fixes

Version numbering follows [Semantic Versioning](https://semver.org/):
- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes (backward compatible)

---

**Last Updated:** 2026-07-25
