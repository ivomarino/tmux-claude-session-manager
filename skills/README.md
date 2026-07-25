# TCSM Session Manager Skill

Unified Claude CLI session management for local development environments using TCSM (tmux-claude-session-manager).

## Files

- **`tcsm.sh`** - Main skill script with all session management functions
- **`tcsm-doctor.sh`** - Health check and cleanup utility for sessions
- **`tcsm.md`** - Comprehensive documentation
- **`USAGE.txt`** - Quick reference card

## Features

- **Interactive sessions** in tmux windows
- **Auto-registration** with Claude CLI
- **Web UI integration** via bridgeSessionId
- **Workspace trust** pre-configured (no startup dialogs)
- **Project path resolution** from configuration
- **Local and elevated** (sudo) support
- **Multi-project support** for different codebases
- **Multi-account support** with rate-limit tracking
- **Graceful shutdown** with signal escalation
- **Git-aware discovery** auto-fallback to real repos
- **Health diagnostics** via tcsm-doctor command

## Installation

```bash
# Copy to Claude skills directory
mkdir -p ~/.claude/skills
cp tcsm.sh ~/.claude/skills/
```

## Quick Start

```bash
source ~/.claude/skills/tcsm.sh

# Start a session
tcsm-start myproject

# Start with specific account
tcsm-start myproject --account secondary

# Stop a session
tcsm-stop myproject

# Restart a session
tcsm-restart myproject

# List all sessions  
tcsm-list

# Check system health
tcsm-status

# Run health diagnostics
tcsm-doctor

# Attach to a project
tmux attach -t tcsm:myproject
```

## Health & Diagnostics

**tcsm-doctor** provides comprehensive health checks:

```bash
# Check all systems
tcsm-doctor

# Verbose output with details
tcsm-doctor -v

# Check specific areas
tcsm-doctor --check accounts
tcsm-doctor --check git,orphans

# Preview fixes without applying
tcsm-doctor --fix --dry-run

# Auto-fix issues
tcsm-doctor --fix
```

**Checks performed:**
- Registry ↔ Tmux consistency
- Git repository validation
- Account validity and rate limits
- Orphaned processes and windows
- File permissions and data integrity

## Configuration

Edit `~/.claude/tcsm-projects.json` to customize project paths:

```json
{
  "sessions": {
    "myproject": {"path": "/home/user/src/myproject"},
    "flamelet-iwf": {"path": "/home/user/.flamelet/tenant/flamelet-iwf"}
  }
}
```

See `tcsm.md` for full documentation.
