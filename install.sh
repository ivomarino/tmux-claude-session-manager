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

# Step 1: Migrate old deployed copies if they exist
if [[ -f "$SKILLS_DEST/claude-project-sessions.sh" ]] && [[ ! -f "$SKILLS_DEST/tcsm.sh" ]]; then
  log "Migrating old skill file: claude-project-sessions.sh → tcsm.sh"
  mv "$SKILLS_DEST/claude-project-sessions.sh" "$SKILLS_DEST/tcsm.sh" && \
  log "✓ Skill file migrated"
fi

if [[ -f "$CONFIG_DEST/project-sessions.json" ]] && [[ ! -f "$CONFIG_DEST/tcsm-projects.json" ]]; then
  log "Migrating old config: project-sessions.json → tcsm-projects.json"
  mv "$CONFIG_DEST/project-sessions.json" "$CONFIG_DEST/tcsm-projects.json" && \
  log "✓ Project config migrated"
fi

if [[ -f "$CONFIG_DEST/session-restore-map.json" ]] && [[ ! -f "$CONFIG_DEST/tcsm-session-map.json" ]]; then
  log "Migrating old session map: session-restore-map.json → tcsm-session-map.json"
  mv "$CONFIG_DEST/session-restore-map.json" "$CONFIG_DEST/tcsm-session-map.json" && \
  log "✓ Session map migrated"
fi

if [[ -f "$CONFIG_DEST/project-sessions.log" ]] && [[ ! -f "$CONFIG_DEST/tcsm.log" ]]; then
  log "Migrating old log: project-sessions.log → tcsm.log"
  mv "$CONFIG_DEST/project-sessions.log" "$CONFIG_DEST/tcsm.log" && \
  log "✓ Log file migrated"
fi

# Step 1: Install skills
log "Installing skills to $SKILLS_DEST..."
mkdir -p "$SKILLS_DEST"
cp "$REPO_PATH/skills/tcsm.sh" "$SKILLS_DEST/" || error "Failed to copy skill"
chmod +x "$SKILLS_DEST/tcsm.sh"
log "✓ Skill installed"

# Step 2: Install configuration templates
log "Installing config templates to $CONFIG_DEST..."
mkdir -p "$CONFIG_DEST"

# Map old template names to new ones for migration
declare -A template_map=(
  ["tcsm-projects.json"]="tcsm-projects.json"
  ["accounts.json"]="accounts.json"
)

for new_name in "${!template_map[@]}"; do
  if [[ ! -f "$CONFIG_DEST/$new_name" ]]; then
    cp "$REPO_PATH/config/${new_name}.template" "$CONFIG_DEST/$new_name" && \
    log "✓ Created $CONFIG_DEST/$new_name (from template)"
  else
    log "⚠ $CONFIG_DEST/$new_name already exists (skipped)"
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

# Step 4: Optional systemd unit installation
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-0}"
if [[ "$INSTALL_SYSTEMD" == "1" ]]; then
  log "Installing systemd unit for automatic session restoration on boot..."
  mkdir -p "$HOME/.config/systemd/user"
  cp "$REPO_PATH/systemd/tcsm-restore.service" "$HOME/.config/systemd/user/tcsm-restore.service" || \
    error "Failed to install systemd unit"
  systemctl --user daemon-reload
  log "✓ Systemd unit installed"
  log "Enabling automatic restoration on boot..."
  systemctl --user enable --now tcsm-restore.service || \
    error "Failed to enable systemd unit"
  log "✓ Systemd unit enabled and started"
else
  log "Skipped systemd unit installation (INSTALL_SYSTEMD=0)"
  log "To enable boot-time session restoration, run:"
  log "  INSTALL_SYSTEMD=1 bash install.sh"
  log "Or enable manually:"
  log "  cp systemd/tcsm-restore.service ~/.config/systemd/user/"
  log "  systemctl --user daemon-reload"
  log "  systemctl --user enable --now tcsm-restore.service"
fi

# Step 5: Display completion message
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
echo "   source ~/.claude/skills/tcsm.sh"
echo ""
echo "3. Start managing Claude sessions:"
echo "   tcsm-start myproject"
echo "   tcsm-stop myproject"
echo "   tcsm-restart myproject"
echo "   tcsm-list"
echo "   tcsm-status"
echo "   tmux attach -t tcsm:myproject"
echo ""
echo "Configuration:"
echo "  - Edit ~/.claude/tcsm-projects.json for project paths"
echo "  - Edit ~/.claude/accounts.json for account settings"
echo ""
echo "Environment variables:"
echo "  TENANT=staging ./install.sh          # Creates staging-tcsm"
echo "  SKILLS_DEST=/custom/path bash install.sh"
echo "  INSTALL_SYSTEMD=1 bash install.sh   # Auto-restore on boot"
echo ""

log "Installation finished successfully"
