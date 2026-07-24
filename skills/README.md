# TCSM Session Manager Skill

Unified Claude CLI session management for local development environments using TCSM (tmux-claude-session-manager).

## Files

- **`tcsm.sh`** - Main skill script with all session management functions
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

# Stop a session
tcsm-stop myproject

# Restart a session
tcsm-restart myproject

# List all sessions  
tcsm-list

# Attach to a project
tmux attach -t tcsm:myproject
```

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
