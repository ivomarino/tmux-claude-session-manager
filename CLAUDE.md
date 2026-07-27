# Developing with Claude

This file documents how to use Claude Code for development on this project. It includes project context, common tasks, and workflow tips.

## Project Overview

**tmux-claude-session-manager** is a tmux plugin + skill that manages Claude Code sessions across projects. This fork extends the upstream project with comprehensive session management features.

**Key Technologies:**
- Bash shell scripting
- tmux window management
- JSON configuration (jq parsing)
- Git repository management
- Claude CLI integration
- systemd service management

## Quick Start

### 1. Load the TCSM Skill

```bash
source ~/.claude/skills/tcsm.sh
```

### 2. Common Tasks

**Start a session:**
```bash
tcsm-start myproject --account secondary
```

**List all sessions:**
```bash
tcsm-list
```

**Check system health:**
```bash
tcsm-status
```

**View documentation:**
```bash
cat skills/tcsm.md    # Full documentation
cat skills/README.md  # Quick overview
```

## Project Structure

```
tmux-claude-session-manager/
├── claude_session_manager.tmux    # Upstream plugin (tmux keybindings)
├── CLAUDE.md                      # This file - development guide
├── CHANGELOG.md                   # Version history and changes
├── README.md                      # Main documentation (with fork enhancements)
├── LICENSE                        # MIT license
├── install.sh                     # Installation script (creates $TENANT-tcsm session)
│
├── skills/                        # TCSM Skill (Bash scripts)
│   ├── tcsm.sh                   # Main skill implementation
│   ├── README.md                 # Skill overview
│   ├── tcsm.md                   # Comprehensive documentation
│   └── USAGE.txt                 # Quick reference
│
├── config/                        # Configuration templates
│   ├── tcsm-projects.json.template
│   ├── accounts.json.template
│   └── README.md
│
├── systemd/                       # Systemd service unit
│   └── tcsm-restore.service      # Boot-time session restoration
│
└── docs/                          # Documentation
    └── screenshot.jpg             # Plugin demo screenshot
```

## Key Files to Know

### `skills/tcsm.sh` - Main Skill Implementation
- **Lines 1-50**: Configuration and logging setup
- **Lines 122-165**: Helper functions (validation, git discovery)
- **Lines 168-338**: `tcsm-start()` - Session creation
- **Lines 374-420**: `tcsm-list()` - Display sessions
- **Lines 483-536**: `tcsm-restore()` - Boot restoration
- **Lines 537-575**: `tcsm-status()` - Health check

**Key Functions:**
- `validate_account()` - Account validation
- `get_rate_limit_tier()` - Rate limit lookup
- `tcsm-find-git-dir()` - Git repo discovery
- `ensure_workspace_trusted()` - Workspace trust setup
- `cleanup_orphaned_sessions()` - Session cleanup

### `README.md` - Project Documentation
- **Fork Enhancements** section documents new features
- **Installation** instructions for fresh VMs
- **Known Issues** section for workarounds
- **Upstream** reference to original project

### `CHANGELOG.md` - What's Been Done
- Complete history of changes and versions
- Grouped by Added/Changed/Fixed/Removed
- Timestamps and commit references

## Session Naming and Cleanup

### Session Architecture
- **Main Session**: Always named `tcsm` (created during installation)
  - This is a tmux session that acts as a container for all windows
  - Should NEVER be killed during normal operations
  - Persists across entire session lifecycle
  
- **Critical Window**: First window (window 0) named after tenant
  - Window format: `tcsm:<TENANT>-tcsm>`
  - Example for floads tenant: `tcsm:floads-tcsm`
  - Runs the TCSM management Claude session (priority: critical)
  
- **Project Windows**: Child windows (window 1+) named after projects
  - Named after the project (with `/` replaced by `-`)
  - Window format: `tcsm:<project-name>`
  - Example: `tcsm:my-project`, `tcsm:flamelet-kbe`

### Cleanup Safety

When stopping a project session (`tcsm-stop`):
1. Targets the specific pane process by PID
2. Uses signal escalation: SIGINT (graceful) → SIGTERM → SIGKILL
3. Kills only child processes of that specific pane (using `pgrep -P`)
4. Removes only the project window from the main session
5. **Never kills the main `$TENANT-tcsm` session itself**

This architecture ensures:
- No accidental termination of the main `tcsm` session during cleanup
- Precise targeting of only the project's Claude process
- Critical window (`<TENANT>-tcsm`) protected from manual stops
- Multiple projects can run concurrently in the same main session

## Common Development Tasks

### Adding a New Feature

1. **Update the skill** (`skills/tcsm.sh`):
   - Add function or modify existing
   - Test interactively: `source ~/.claude/skills/tcsm.sh && function-name`
   - Add logging with `log_session()` for debugging

2. **Update documentation**:
   - Add usage examples to `skills/tcsm.md`
   - Update README.md if user-facing
   - Add entry to CHANGELOG.md

3. **Test thoroughly**:
   - Test with multiple sessions
   - Test error cases (invalid input, missing files)
   - Test backward compatibility (old sessions still work)

4. **Commit** with clear message:
   ```bash
   git add skills/tcsm.sh skills/tcsm.md README.md CHANGELOG.md
   git commit -m "feat: Description of feature"
   ```

### Debugging Sessions

**Check session status:**
```bash
tcsm-status
tcsm-list
```

**View logs:**
```bash
tail -50 ~/.claude/tcsm.log
```

**Check registry:**
```bash
jq . ~/.claude/tcsm-session-map.json
```

**List tmux windows:**
```bash
tmux list-windows -t tcsm
```

**Attach to a session:**
```bash
tmux attach -t tcsm:project-name
```

**View running Claude processes:**
```bash
ps aux | grep "claude --"
```

## Important Configuration

### Session Registry (`~/.claude/tcsm-session-map.json`)
```json
{
  "sessions": {
    "project-name": {
      "id": "project-name",
      "path": "/home/user/src/project",
      "window": "project-name",
      "account": "secondary",
      "rate_limit_tier": "default_claude_max_5x",
      "created": 1234567890.123
    }
  }
}
```

### Accounts Configuration (`~/.claude/accounts.json`)
```json
{
  "accounts": [
    {
      "id": "secondary",
      "email": "user@example.com",
      "active": true,
      "rate_limit_tier": "default_claude_max_5x",
      "metadata": {
        "organization": "example-org"
      }
    }
  ]
}
```

### Environment Variables
```bash
# Tmux session configuration (set by install.sh, can be overridden)
export TCSM_TENANT="dev"                       # Tenant name (default: dev)
export TCSM_SESSION="tcsm"                     # Main tmux session (always 'tcsm')
export TCSM_CRITICAL_WINDOW="dev-tcsm"         # Critical window name (default: $TCSM_TENANT-tcsm)

# Search roots for git-controlled projects
export TCSM_SEARCH_ROOTS="$HOME/src $HOME/projects"

# Custom installation locations
export SKILLS_DEST="$HOME/.claude/skills"
export CONFIG_DEST="$HOME/.claude"
```

**Note:** The main tmux session is always named `tcsm` (invariant across all tenants). Window 0 is the critical management session named `<TENANT>-tcsm` (e.g., `floads-tcsm`). Project windows are windows 1+ within this session. The main `tcsm` session should never be killed during normal operation.

## Testing Workflow

### Unit Testing a Function

```bash
# Load the skill
source ~/.claude/skills/tcsm.sh

# Test a function
validate_account "secondary"  # Should return 0 (success)
validate_account "invalid"    # Should return 1 (failure)

# Check output
get_rate_limit_tier "secondary"
get_account_display "secondary"
```

### Integration Testing

```bash
# Test full session lifecycle
tcsm-start test-project --account secondary

# Verify in registry
jq '.sessions."test-project"' ~/.claude/tcsm-session-map.json

# Check display
tcsm-list

# Clean up
tcsm-stop test-project
```

## Common Issues and Solutions

### Sessions not showing in web UI
**Check:** Are sessions registered under the active account?
```bash
jq '.sessions[] | .account' ~/.claude/tcsm-session-map.json
jq '.accounts[] | select(.active) | .id' ~/.claude/accounts.json
```

### Session won't start
**Check:** Is the account active and project path valid?
```bash
validate_account "account-id"
ls -la /path/to/project
git -C /path/to/project rev-parse --is-inside-work-tree
```

### Orphaned Claude processes
**Check:** Kill manually or use cleanup features
```bash
ps aux | grep "claude --name"
pkill -f "claude.*--name project-name"
```

### Permission errors
**Check:** File permissions in ~/.claude/
```bash
ls -la ~/.claude/
chmod 755 ~/.claude/skills/tcsm.sh
```

## Workflow Tips

### 1. Use the Skill Directly

Always load and test functions interactively:
```bash
source ~/.claude/skills/tcsm.sh
tcsm-list
tcsm-status
```

### 2. Refer to Documentation

- `skills/tcsm.md` - Comprehensive behavior docs
- `README.md` - User-facing feature docs
- `CHANGELOG.md` - What's changed and when
- Inline code comments - Implementation details

### 3. Test Edge Cases

When adding features, test:
- Invalid input (wrong account, bad path, etc.)
- Missing files (no accounts.json, no sessions)
- Concurrent operations (multiple sessions)
- Error conditions (git not available, tmux not running)

### 4. Keep Logs Clean

Use `log_session()` with appropriate levels:
- `INFO` - Informational messages
- `OK` - Success messages
- `WARN` - Warning messages
- `ERROR` - Error conditions

### 5. Update CHANGELOG

Add entry for every change:
- Feature additions go in `### Added`
- Fixes go in `### Fixed`
- Breaking changes go in `### Changed`
- Removals go in `### Removed`

## Future Development

### Planned Features (see CHANGELOG.md)
- `tcsm-doctor` command for health checks
- Session diagnostics and orphaned process detection
- Automated cleanup of stale sessions
- Enhanced logging and troubleshooting

### Contributing Back

Bug fixes and improvements are periodically contributed back to:
https://github.com/craftzdog/tmux-claude-session-manager

## Getting Help

### Within Claude Code

Reference relevant documentation:
```bash
cat skills/tcsm.md           # How the skill works
cat README.md                # Feature overview
grep "function-name" skills/tcsm.sh  # Function implementation
```

### Debugging Claude Issues

Check Claude Code's official resources:
- GitHub issues: https://github.com/anthropics/claude-code
- Known bugs: See README.md "Known Issues" section
- Workspace trust: See troubleshooting in skills/tcsm.md

### Testing with Claude

This project is designed to be managed and developed using Claude Code:
1. Start a session: `tcsm-start tmux-claude-session-manager`
2. Ask Claude to help with development
3. Claude can read skills/tcsm.sh, modify it, run tests
4. Changes persist in your git working directory

---

**Last Updated:** 2026-07-25

For questions or contributions, see the main README.md and CHANGELOG.md.
