# Claude Session Manager Skill

Unified Claude CLI session management for local development environments.

## Files

- **`claude-project-sessions.sh`** - Main skill script with all session management functions
- **`claude-sessions.md`** - Comprehensive documentation
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
cp claude-project-sessions.sh ~/.claude/skills/
```

## Quick Start

```bash
source ~/.claude/skills/claude-project-sessions.sh

# Start a session
start-claude-project myproject

# List all sessions  
list-claude-sessions

# Attach to a project
tmux attach -t claude-myproject
```

## Configuration

Edit `~/.claude/project-sessions.json` to customize project paths:

```json
{
  "sessions": {
    "myproject": {"path": "/home/user/src/myproject"},
    "flamelet-iwf": {"path": "/home/user/.flamelet/tenant/flamelet-iwf"}
  }
}
```

See `claude-sessions.md` for full documentation.
