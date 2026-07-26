# TCSM (tmux-claude-session-manager) Skill

**Description**: Manage Claude CLI sessions in tmux windows for projects with support for local, elevated, and remote operations across infrastructure.

**Version**: 2.0.0  
**Type**: Session Management  
**Author**: Claude Code

## Overview

This skill provides unified Claude session management across:
- **Local projects** in tmux windows with interactive access
- **Elevated operations** for infrastructure/admin work with sudo
- **Remote sessions** via SSH to dev container (<remote-host-ip>)
- **Multi-project** support for organizing and managing multiple projects (backend, frontend, infrastructure, etc.)

Sessions run interactively in tmux windows (organized under the `tcsm` session) and auto-register with the Claude CLI for web UI integration. You can attach to any window to interact with Claude directly.

## Usage

### Basic Commands

```bash
# Start a Claude session for a project (uses primary account by default)
tcsm-start myproject

# Start with specific account
tcsm-start myproject --account primary

# Start with elevated permissions (sudo)
tcsm-start myproject --elevate

# Combine account and elevated
tcsm-start myproject --account primary --elevate

# Stop a running Claude session (graceful shutdown)
tcsm-stop myproject

# Restart a Claude session
tcsm-restart myproject

# List all active Claude sessions with account info
tcsm-list

# Show session health status and per-session account info
tcsm-status
```

### Account Management

TCSM sessions can be associated with specific Claude accounts for multi-account rate-limit tracking:

```bash
# Start session with primary account (default)
tcsm-start myproject

# Start session with specific account (if multiple accounts configured)
tcsm-start myproject --account secondary

# View account for each session
tcsm-list
# Shows: Project | Window | Status | Account | Rate Limit Tier | Path

tcsm-status
# Shows per-session account configuration
```

**Account Requirements:**
- Account must exist in `~/.claude/accounts.json`
- Account must be marked as `active: true`
- Rate limit tier is displayed from account configuration
- Default account is "primary" if not specified

**Example accounts.json:**
```json
{
  "accounts": [
    {
      "id": "primary",
      "email": "user@example.com",
      "active": true,
      "rate_limit_tier": "default_claude_max_5x"
    },
    {
      "id": "secondary",
      "email": "user@secondary.com",
      "active": false,
      "rate_limit_tier": "default_claude_max_5x"
    }
  ]
}
```

**Important Note:** The `--account` parameter is metadata-only. Claude CLI doesn't support account selection at launch time, so sessions use the default account configured in Claude Code. TCSM simply tracks and displays which account a session was *intended* to use for administrative and rate-limit tracking purposes.

#### Session Lifecycle

**Start (`tcsm-start`):**
- Creates tmux window under `tcsm` session
- Pre-trusts workspace to avoid confirmation dialogs
- Launches Claude CLI interactively
- Auto-registers with Claude (creates session file)
- Waits for Claude registration before returning

**Stop (`tcsm-stop`):**
- Gracefully terminates Claude process (SIGINT → SIGTERM → SIGKILL)
- Cleans up tmux window
- Removes session registration files
- Allows 5-second grace period for Claude to save state
- Falls back to force-kill if graceful shutdown times out

**Restart (`tcsm-restart`):**
- Stops the current session (see above)
- Waits briefly for cleanup
- Starts a fresh session (see above)
- Useful for config changes or recovery

### Remote Operations

```bash
# Start session on remote dev container
tcsm-start myproject --remote <remote-host-ip>

# Stop session on remote
tcsm-stop myproject --remote <remote-host-ip>

# Restart on remote
tcsm-restart myproject --remote <remote-host-ip>

# List sessions on remote
tcsm-list --remote <remote-host-ip>

# Shortcut for remote access
tcsm-remote <remote-host-ip> myproject

# Remote with elevated permissions
tcsm-remote <remote-host-ip> myproject --elevate
```

### Boot & Recovery

```bash
# Restore all mapped sessions (boot-time)
tcsm-restore

# Dry-run to see what would be restored
tcsm-restore --dry-run

# Remote restoration
tcsm-restore --remote <remote-host-ip>
```

### Health Checks & Diagnostics

**tcsm-doctor** performs comprehensive health checks and optional repairs:

```bash
# Run all health checks (read-only, default)
tcsm-doctor

# Verbose output with details
tcsm-doctor -v

# Check specific areas only
tcsm-doctor --check sessions      # Registry/Tmux consistency
tcsm-doctor --check git           # Git repo validation
tcsm-doctor --check accounts      # Account validity
tcsm-doctor --check orphans       # Orphaned processes/windows

# Preview fixes without applying
tcsm-doctor --fix --dry-run

# Auto-fix detected issues
tcsm-doctor --fix
tcsm-doctor --fix --force         # Skip confirmations
```

**Checks Performed:**

**Tier 1 (Critical):**
- Registry → Tmux: All sessions have active windows
- Tmux → Registry: All windows are registered
- Git validation: All session paths are git-controlled
- Duplicate detection: No duplicate session names

**Tier 2 (Account/Process):**
- Account validity: Sessions use active accounts
- Rate limit consistency: Tiers match configuration
- Orphaned processes: Find abandoned Claude processes
- File permissions: ~/.claude/ is readable/writable

**Tier 3 (Data Quality):**
- Log file health: Size and readability
- Map integrity: Valid JSON and schema compliance

**Example Output:**
```
=== Critical Registry/Tmux Checks ===
  ✓ Registry → Tmux (8 sessions have windows)
  ✗ Tmux → Registry (1 orphaned window: stale-project)
  ✓ Git validation (8 paths are git-controlled)
  ✓ No duplicate session names

=== Account/Process Integrity ===
  ✓ Account validity (all sessions use active accounts)
  ⚠ Orphaned processes (1 abandoned Claude process)
  ✓ File permissions OK (~/.claude/ is 700)

=== Data Quality ===
  ✓ Log file healthy (1.2MB)
  ✓ Session map integrity OK

Status: ⚠ WARNING (1 warning, 0 critical issues)
```

**Exit Codes:**
- `0` - OK (all checks passed)
- `1` - ERROR (critical issues found)
- `2` - WARNING (non-critical issues found)

## Configuration

### Session Mapping (`~/.claude/tcsm-session-map.json`)
Maps projects to Claude session IDs and tmux windows:
```json
{
  "sessions": {
    "myproject": {
      "id": "session_1721234567_1234",
      "path": "/home/your-user/src/myproject",
      "window": "myproject",
      "created": 1721234567.890
    }
  }
}
```

### Project Paths (`~/.claude/tcsm-projects.json`)
Override default project directory resolution:
```json
{
  "sessions": {
    "myproject": {
      "path": "/custom/path/to/myproject"
    }
  }
}
```

### Git-Aware Project Discovery
When `tcsm-start` resolves a project directory, it checks if that directory is under git control. If not, it automatically searches for a git-controlled directory with the same name in the configured search roots and uses that instead (silently, or with a log message if no match is found).

This is useful for projects that exist as configuration stubs before their actual source repositories are cloned. For example, if you run `tcsm-start my-project` but `~/.config/projects/my-project` is just a stub directory without `.git`, the skill will look for `my-project` in other search roots and switch to that if found.

**Search roots** are configured via the `TCSM_SEARCH_ROOTS` environment variable (space-separated paths):
```bash
# Default (can be overridden):
TCSM_SEARCH_ROOTS="$HOME/src $HOME/projects"

# Example: add a custom root
export TCSM_SEARCH_ROOTS="$HOME/src $HOME/projects /opt/projects"
tcsm-start myproject
```

## Prerequisites

- `tmux` - Terminal multiplexer for session management
- `jq` - JSON processor for mapping files
- `claude` - Claude CLI installed in PATH (`~/.local/bin/claude`)
- SSH access to remote hosts (for remote operations)

## Session Registration

Sessions are registered automatically by the Claude CLI when started with `--bg` flag:

```bash
claude --model haiku \
  --permission-mode bypassPermissions \
  --remote-control \
  --name <project> \
  --bg
```

Session metadata is stored in `~/.claude/sessions/` and synced to Claude web UI via `bridgeSessionId`.

View active sessions:
```bash
ls ~/.claude/sessions/*.json
jq '.name' ~/.claude/sessions/*.json
```

## SSH Configuration

Remote operations use SSH key-based auth to your-user user:
```bash
# SSH as your-user to dev container
ssh your-user@<remote-host-ip>

# SSH to remote project servers
ssh your-user@app-server.example.com         # app server
ssh your-user@infra-server.example.com       # infrastructure
ssh your-user@10.0.0.1                       # datacenter
ssh your-user@storage-server.example.com     # storage
```

## Permission Model

- **Local**: No escalation needed for normal projects
- **Elevated**: `sudo` prefix for privileged operations
- **Remote**: SSH key auth via ~/.ssh/your-user/id_rsa-*
- **Bypass**: SSH agent forwarding (-A) for infrastructure access

## Examples

### Start session for MyProject infrastructure
```bash
tcsm-start myproject
# Creates: tcsm:myproject tmux window
# Path: /home/your-user/src/myproject
# Flags: claude --model haiku --permission-mode bypassPermissions --remote-control --name myproject
# Attach: tmux attach -t tcsm:myproject
```

### Start elevated session for system administration
```bash
tcsm-start myproject --elevate
# Creates: tcsm:myproject tmux window (elevated)
# Runs: sudo claude --model haiku ... --name myproject
# Attach: tmux attach -t tcsm:myproject (runs with elevated permissions)
```

### Attach to existing session
```bash
# View available windows
tmux list-windows -t tcsm

# Attach to a session
tmux attach -t tcsm:myproject
tmux attach -t tcsm:infrastructure
```

### Restore all sessions after container restart
```bash
tcsm-restore --remote <remote-host-ip>
# Restores all mapped sessions on dev container
# Useful after: pct restart 251
```

## Launch Parameters

Sessions are started interactively in tmux windows with consistent flags:

```bash
claude \
  --model haiku                     # Use Claude Haiku
  --permission-mode bypassPermissions  # Allow all tools without prompting
  --remote-control                  # Enable remote session management
  --name <project>                  # Session name (appears in web UI)
```

Sessions run in tmux windows allowing you to:
- Attach to the window: `tmux attach -t claude:<project>`
- Interact with Claude directly
- Auto-register session metadata in `~/.claude/sessions/`
- Sync to web UI via `bridgeSessionId`

For unattended background sessions (no interaction), add `--bg` flag.

## Logging

All operations are logged to `~/.claude/tcsm.log`:
```bash
tail -f ~/.claude/tcsm.log
```

Log entries include:
- Session starts/stops
- Remote connections
- Permission escalations
- Mapping file updates
- Errors and warnings

## Advanced

### Manual Session Mapping

Add custom mappings to `tcsm-session-map.json`:
```bash
jq '.sessions["custom-project"] = {
  id: "manual_session",
  path: "/path/to/project",
  window: "custom",
  created: now
}' ~/.claude/tcsm-session-map.json > /tmp/map.json && \
mv /tmp/map.json ~/.claude/tcsm-session-map.json
```

### Boot-time Auto-restore

Add to startup script or systemd service:
```bash
tcsm-restore
```

## Troubleshooting

### Quick Diagnostics

Start with **tcsm-doctor** to diagnose system health:

```bash
# Run automatic checks
tcsm-doctor

# Verbose output with details
tcsm-doctor -v

# Check specific areas
tcsm-doctor --check accounts    # Check account configuration
tcsm-doctor --check git         # Validate git repositories
tcsm-doctor --check orphans     # Find orphaned processes
```

This will identify:
- Registry/Tmux mismatches
- Account validity issues
- Orphaned processes or windows
- File permission problems
- Data integrity issues

### Session not appearing
1. Run **tcsm-doctor** to identify issues
2. Check prerequisites: `claude`, `tmux`, `jq`
3. Verify mapping: `jq . ~/.claude/tcsm-session-map.json`
4. Check logs: `tail ~/.claude/tcsm.log`
5. Test tmux: `tmux list-sessions`

### Remote connection fails
1. Test SSH: `ssh your-user@<remote-host-ip> echo ok`
2. Check keys: `ls ~/.ssh/your-user/id_rsa-*`
3. Verify permissions: `ls -la ~/.ssh/`
4. Check remote prerequisites: `ssh your-user@<remote-host-ip> which claude tmux jq`

### Permission denied with --elevate
1. Check sudoers: `sudo -l`
2. Verify claude binary in sudoers: `sudo /root/.local/bin/claude --version`
3. Add to sudoers if needed (with `visudo`)

### Path display issue for self-hosted GitLab
**Issue:** Claude Code web UI shows GitLab organization/namespace instead of project name  
**Example:** For `git@git.example.com:infrastructure/my-project.git`, displays "infrastructure" instead of "my-project"

**Root cause:** Claude Code parses the git remote URL and extracts the organization namespace. This is technically correct for standard GitLab URLs (`git@gitlab.com:org/project`) but shows the wrong value when the organization/namespace doesn't match the project name.

**Workaround:** This is a Claude Code limitation, not a tcsm issue. The session still works correctly; only the path display in the web UI is affected.

**Mitigation options:**
1. Use HTTPS remotes instead of SSH (may change display but not guaranteed)
2. File an issue with Claude Code for better namespace handling
3. Accept the display limitation (functionality is unaffected)

## Performance

- Session creation: < 1 second
- Remote connection: 1-3 seconds (depending on SSH latency)
- Session restoration: 100ms per session + parallel startup
- Mapping file: < 50ms for updates

## What's New in v2.0

### Multi-Account Support
- Start sessions with specific accounts: `tcsm-start project --account secondary`
- View account per session in `tcsm-list` output
- Rate limit tier tracking and display
- Account validation and inactive account detection

### Graceful Shutdown
- `tcsm-stop` now gracefully terminates Claude (SIGINT → SIGTERM → SIGKILL)
- 5-second grace period for Claude to save state
- Intelligent escalation prevents orphaned processes

### Health Diagnostics
- New `tcsm-doctor` command for comprehensive checks
- Detects registry/tmux mismatches
- Validates git repositories and accounts
- Identifies orphaned processes and windows
- Optional auto-fix capability with `--fix` flag

### Enhanced Display
- `tcsm-list` shows Account and Rate Limit Tier columns
- `tcsm-status` displays per-session account information
- Color-coded output for better readability

### Other Improvements
- Git-aware project discovery auto-fallback
- Improved logging with `log_session()` function
- Session registration wait ensures web UI sync
- Backward compatible with v1.x configurations

## Workspace Trust

The skill automatically pre-trusts all project directories to avoid the workspace trust dialog on startup. This is configured in `~/.claude.json`:

```json
{
  "workspaceTrustSettings": {
    "/home/your-user/src/myproject": {"hasTrustDialogAccepted": true},
    "/home/your-user/projects/infrastructure": {"hasTrustDialogAccepted": true},
    ...
  }
}
```

The `ensure_workspace_trusted` function automatically adds new project directories as they're started.

## Security Notes

- SSH keys stored in ~/.ssh/your-user/id_rsa-*
- Elevated operations use sudo (password-less if configured)
- Session IDs are internal tracking only
- Logs contain full paths (may have sensitive info)
- Remote operations use direct SSH, no jump hosts by default
- Workspace trust settings avoid interactive dialogs while maintaining safety

## Compatibility

- Linux: ✓ Tested on Debian/Ubuntu
- macOS: ✓ Works with tmux from Homebrew
- Windows: Requires WSL or native tmux
- Requires: bash 4+, jq 1.6+, tmux 3.0+

## Related Skills

- `tmux-claude-session-manager` - Low-level tmux plugin
- `claude-startup-simple.sh` - Boot-time startup script
