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

# Step 3: Initialize session map and create main tcsm session
log "Initializing TCSM infrastructure..."

# Create session map if it doesn't exist
mkdir -p "$CONFIG_DEST"
if [[ ! -f "$CONFIG_DEST/tcsm-session-map.json" ]]; then
  echo '{"sessions": {}}' > "$CONFIG_DEST/tcsm-session-map.json"
  log "✓ Session map initialized"
fi

# Create main tmux session (always called 'tcsm')
log "Creating main tmux session: tcsm..."
if ! tmux has-session -t tcsm 2>/dev/null; then
  if ! tmux new-session -d -s tcsm -c "$HOME"; then
    error "Failed to create main tmux session"
  fi
  log "✓ Main session created: tcsm"
fi

# Create the critical self-hosted TCSM management session in window 0
log "Creating critical management window: $TENANT..."
source "$SKILLS_DEST/tcsm.sh" || error "Failed to load tcsm skill"

# Set environment for critical session
export TCSM_TENANT="$TENANT"
export TCSM_SESSION="tcsm"  # Main session is always 'tcsm'
export TCSM_CRITICAL_WINDOW="${TENANT}-tcsm"  # Critical window named after tenant
export TCSM_CRITICAL_PATH="$REPO_PATH"

# Determine default account: use default_account from accounts.json, fallback to first active, then primary, then secondary
if [[ -f "$CONFIG_DEST/accounts.json" ]]; then
  export TCSM_CRITICAL_ACCOUNT=$(jq -r '.default_account // empty' "$CONFIG_DEST/accounts.json" 2>/dev/null)
  if [[ -z "$TCSM_CRITICAL_ACCOUNT" ]]; then
    export TCSM_CRITICAL_ACCOUNT=$(jq -r '.accounts[] | select(.active==true) | .id' "$CONFIG_DEST/accounts.json" 2>/dev/null | head -1)
  fi
fi
export TCSM_CRITICAL_ACCOUNT="${TCSM_CRITICAL_ACCOUNT:-primary}"  # Primary fallback
if ! jq -e ".accounts[] | select(.id==\"$TCSM_CRITICAL_ACCOUNT\")" "$CONFIG_DEST/accounts.json" &>/dev/null 2>&1; then
  export TCSM_CRITICAL_ACCOUNT="secondary"  # Secondary fallback
fi

if tcsm-start "$TENANT" --account "$TCSM_CRITICAL_ACCOUNT" --priority critical; then
  log "✓ Critical management window created: ${TENANT}-tcsm"
else
  error "Failed to create critical management window"
fi

# Step 4: Optional systemd unit installation
INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-0}"
if [[ "$INSTALL_SYSTEMD" == "1" ]]; then
  log "Installing systemd units for automatic session restoration and supervision..."
  mkdir -p "$HOME/.config/systemd/user"

  # Install restore service (runs once on boot)
  cp "$REPO_PATH/systemd/tcsm-restore.service" "$HOME/.config/systemd/user/tcsm-restore.service" || \
    error "Failed to install tcsm-restore service"
  log "✓ tcsm-restore.service installed"

  # Install watch service (runs continuously to monitor critical sessions)
  cp "$REPO_PATH/systemd/tcsm-watch.service" "$HOME/.config/systemd/user/tcsm-watch.service" || \
    error "Failed to install tcsm-watch service"
  log "✓ tcsm-watch.service installed"

  systemctl --user daemon-reload

  log "Enabling automatic restoration and supervision on boot..."
  systemctl --user enable --now tcsm-restore.service || \
    error "Failed to enable tcsm-restore service"
  systemctl --user enable --now tcsm-watch.service || \
    error "Failed to enable tcsm-watch service"
  log "✓ Systemd units enabled and started"
else
  log "Skipped systemd unit installation (INSTALL_SYSTEMD=0)"
  log "To enable boot-time session restoration and supervision, run:"
  log "  INSTALL_SYSTEMD=1 bash install.sh"
  log "Or enable manually:"
  log "  cp systemd/tcsm-*.service ~/.config/systemd/user/"
  log "  systemctl --user daemon-reload"
  log "  systemctl --user enable --now tcsm-restore.service tcsm-watch.service"
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
