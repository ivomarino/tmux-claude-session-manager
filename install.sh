#!/usr/bin/env bash
# Installation script for tmux-claude-session-manager fork
# Sets up the plugin, skills, configuration, and default session

set -euo pipefail

# Configuration
REPO_PATH="${REPO_PATH:-.}"
TENANT="${TENANT:-dev}"
SESSION_NAME="${SESSION_NAME:-$TENANT-tcsm}"
SKILLS_DEST="${SKILLS_DEST:-$HOME/.claude/skills}"
CONFIG_DEST="${CONFIG_DEST:-$HOME/.claude}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { log "ERROR: $*" >&2; exit 1; }

log "Installing tmux-claude-session-manager fork"
log "Tenant: $TENANT"
log "Session: $SESSION_NAME"
log "Repository: $REPO_PATH"

# Step 1: Install skills
log "Installing skills to $SKILLS_DEST..."
mkdir -p "$SKILLS_DEST"
cp "$REPO_PATH/skills/claude-project-sessions.sh" "$SKILLS_DEST/" || error "Failed to copy skill"
chmod +x "$SKILLS_DEST/claude-project-sessions.sh"
log "✓ Skill installed"

# Step 2: Install configuration templates
log "Installing config templates to $CONFIG_DEST..."
mkdir -p "$CONFIG_DEST"

for template in project-sessions.json accounts.json; do
  if [ ! -f "$CONFIG_DEST/$template" ]; then
    cp "$REPO_PATH/config/${template}.template" "$CONFIG_DEST/$template" && \
    log "✓ Created $CONFIG_DEST/$template (from template)"
  else
    log "⚠ $CONFIG_DEST/$template already exists (skipped)"
  fi
done

# Step 3: Create default session
log "Creating tmux session: $SESSION_NAME..."
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  log "⚠ Session $SESSION_NAME already exists"
else
  if ! tmux new-session -d -s "$SESSION_NAME" -c "$REPO_PATH"; then
    error "Failed to create tmux session"
  fi
  log "✓ Session created"
fi

# Step 4: Display completion message
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Installation Complete!                               ║"
echo "║  Session: $SESSION_NAME"
echo "║  Directory: $REPO_PATH"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "1. Attach to your session:"
echo "   tmux attach -t $SESSION_NAME"
echo ""
echo "2. Source the skill:"
echo "   source ~/.claude/skills/claude-project-sessions.sh"
echo ""
echo "3. Start managing Claude sessions:"
echo "   start-claude-project myproject"
echo "   list-claude-sessions"
echo "   tmux attach -t claude-myproject"
echo ""
echo "Configuration:"
echo "  - Edit ~/.claude/project-sessions.json for project paths"
echo "  - Edit ~/.claude/accounts.json for account settings"
echo ""
echo "Environment variables:"
echo "  TENANT=staging ./install.sh          # Creates staging-tcsm"
echo "  CLAUDE_SKILLS_DIR=/custom/path bash install.sh"
echo ""

log "Installation finished successfully"
