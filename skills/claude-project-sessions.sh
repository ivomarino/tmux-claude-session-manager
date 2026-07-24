#!/usr/bin/env bash
# Claude Project Session Manager Skill
# Manages Claude CLI sessions in tmux windows for projects with remote support
# Usage: source this file or call functions directly
#
# Functions:
#   start-claude-project <project> [--elevate] [--remote <host>]
#   list-claude-sessions [--remote <host>]
#   restore-claude-sessions [--remote <host>] [--dry-run]
#   claude-session-status [--remote <host>]
#   remote-claude-session <host> <project> [--elevate]

set -uo pipefail

# Configuration
CLAUDE_HOME="${CLAUDE_HOME:-.claude}"
SESSION_MAP="$HOME/$CLAUDE_HOME/session-restore-map.json"
PROJECT_MAP="$HOME/$CLAUDE_HOME/project-sessions.json"
LOG_FILE="$HOME/$CLAUDE_HOME/project-sessions.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_session() {
  local level="$1"
  shift
  local msg="[$level] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo -e "${msg}" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${msg}"
}

# Check prerequisites
check_prerequisites() {
  local missing=()
  [[ -x "$(command -v tmux)" ]] || missing+=("tmux")
  [[ -x "$(command -v jq)" ]] || missing+=("jq")
  [[ -x "$(command -v claude)" ]] || missing+=("claude")

  if (( ${#missing[@]} )); then
    log_session "ERROR" "Missing: ${missing[*]}"
    return 1
  fi
  return 0
}

# Ensure workspace is trusted to avoid trust dialog on startup
ensure_workspace_trusted() {
  local project_dir="$1"
  local claude_config="$HOME/.claude.json"

  [[ ! -d "$project_dir" ]] && return 0

  # Create config file if it doesn't exist
  if [[ ! -f "$claude_config" ]]; then
    echo '{"workspaceTrustSettings": {}}' > "$claude_config"
  fi

  # Add this directory to trusted workspaces
  jq --arg dir "$project_dir" \
    '.workspaceTrustSettings[$dir] = {"hasTrustDialogAccepted": true}' \
    "$claude_config" > "${claude_config}.tmp" 2>/dev/null && \
    mv "${claude_config}.tmp" "$claude_config" || true
}

# Initialize mapping files if needed
init_mapping_files() {
  mkdir -p "$HOME/$CLAUDE_HOME"

  if [[ ! -f "$SESSION_MAP" ]]; then
    cat > "$SESSION_MAP" << 'EOF'
{
  "sessions": {},
  "lastUpdated": null
}
EOF
    log_session "INFO" "Created session map: $SESSION_MAP"
  fi

  if [[ ! -f "$PROJECT_MAP" ]]; then
    cat > "$PROJECT_MAP" << 'EOF'
{
  "sessions": {}
}
EOF
    log_session "INFO" "Created project map: $PROJECT_MAP"
  fi
}

# Start a Claude session for a project
start-claude-project() {
  local project="${1:?Project name required}"
  local elevate=false
  local remote=""

  # Parse options
  while [[ $# -gt 1 ]]; do
    case "$2" in
      --elevate) elevate=true ;;
      --remote) remote="$3"; shift ;;
      *) echo "Unknown option: $2" >&2; return 1 ;;
    esac
    shift
  done

  # If remote, delegate to remote host
  if [[ -n "$remote" ]]; then
    remote-claude-session "$remote" "$project" $([ "$elevate" = true ] && echo "--elevate")
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files

  local project_dir
  # Try to resolve from project-sessions.json first
  if [[ -f "$PROJECT_MAP" ]]; then
    project_dir=$(jq -r ".sessions[\"$project\"].path // empty" "$PROJECT_MAP" 2>/dev/null)
  fi

  # Fall back to standard locations
  if [[ -z "$project_dir" ]]; then
    if [[ -d "$(pwd)/$project" ]]; then
      project_dir="$(pwd)/$project"
    elif [[ -d "$HOME/src/$project" ]]; then
      project_dir="$HOME/src/$project"
    elif [[ -d "$project" ]]; then
      project_dir="$project"
    else
      log_session "ERROR" "Project directory not found: $project"
      return 1
    fi
  fi

  # Resolve window name from project
  local window_name="${project//\//-}"

  # Check if tmux window exists
  if tmux list-windows -t "claude:$window_name" &>/dev/null 2>&1; then
    log_session "INFO" "Window already exists: claude:$window_name"
  else
    # Create window in claude session
    if ! tmux new-window -t claude -n "$window_name" -c "$project_dir"; then
      log_session "ERROR" "Failed to create tmux window: $window_name"
      return 1
    fi
    log_session "OK" "Created tmux window: claude:$window_name"
  fi

  # Pre-trust workspace to avoid trust dialog on startup
  ensure_workspace_trusted "$project_dir"

  # Start Claude session interactively in tmux window
  # Interactive mode auto-registers session and allows attaching
  local claude_cmd="claude --model haiku --permission-mode bypassPermissions --remote-control --name $project"
  [[ "$elevate" = true ]] && claude_cmd="sudo $claude_cmd"

  # Send Claude command to tmux window (runs interactively)
  if tmux send-keys -t "claude:$window_name" "$claude_cmd" Enter; then
    # Update session map
    jq --arg proj "$project" --arg path "$project_dir" \
      '.sessions[$proj] = {id: $proj, path: $path, window: $proj, created: now}' \
      "$SESSION_MAP" > "${SESSION_MAP}.tmp" && mv "${SESSION_MAP}.tmp" "$SESSION_MAP"

    log_session "OK" "Started Claude session: $project"
    echo -e "${GREEN}✓${NC} Claude session started for ${BLUE}$project${NC}"
    echo -e "  Window:  ${YELLOW}claude:$window_name${NC}"
    echo -e "  Path:    ${YELLOW}$project_dir${NC}"
    echo -e "  Attach:  ${YELLOW}tmux attach -t claude:$window_name${NC}"
    return 0
  else
    log_session "ERROR" "Failed to send command to tmux window"
    return 1
  fi
}

# List all Claude sessions
list-claude-sessions() {
  local remote="${1:-}"

  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/claude-project-sessions.sh && list-claude-sessions"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files

  echo -e "${BLUE}=== Claude Project Sessions ===${NC}\n"

  if [[ ! -f "$SESSION_MAP" ]] || ! jq -e '.sessions | length > 0' "$SESSION_MAP" &>/dev/null; then
    echo -e "${YELLOW}No sessions configured${NC}"
    return 0
  fi

  echo -e "${BLUE}Project${NC:30} ${BLUE}Window${NC:20} ${BLUE}Status${NC:15} ${BLUE}Path${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  jq -r '.sessions | to_entries[] |
    "\(.key)\t\(.value.window)\t\(.value.id | .[0:8])\t\(.value.path)"' "$SESSION_MAP" | \
  while IFS=$'\t' read -r project window id path; do
    # Check if window exists in tmux
    local status="inactive"
    if tmux list-windows -t "claude:$window" &>/dev/null 2>&1; then
      status="${GREEN}active${NC}"
    fi

    printf "%-30s %-20s %-15b %s\n" \
      "${BLUE}$project${NC}" \
      "${YELLOW}$window${NC}" \
      "$status" \
      "$path"
  done

  echo ""
}

# Restore all Claude sessions (boot-time)
restore-claude-sessions() {
  local dry_run=false
  local remote=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --remote) remote="$2"; shift ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/claude-project-sessions.sh && restore-claude-sessions $([ "$dry_run" = true ] && echo "--dry-run")"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files

  log_session "INFO" "Starting session restoration..."

  if [[ ! -f "$SESSION_MAP" ]] || ! jq -e '.sessions | length > 0' "$SESSION_MAP" &>/dev/null; then
    log_session "INFO" "No sessions to restore"
    return 0
  fi

  local restored=0
  jq -r '.sessions | to_entries[] | "\(.key)\t\(.value.path)\t\(.value.window)"' "$SESSION_MAP" | \
  while IFS=$'\t' read -r project path window; do
    if [[ "$dry_run" == "true" ]]; then
      log_session "DRY-RUN" "Would restore: $project → $window"
    else
      if start-claude-project "$project" &>/dev/null; then
        ((restored++))
      fi
    fi
  done

  log_session "OK" "Restoration complete ($restored sessions)"
}

# Show session status
claude-session-status() {
  local remote="${1:-}"

  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/claude-project-sessions.sh && claude-session-status"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files

  echo -e "${BLUE}=== Claude Session Status ===${NC}\n"

  # Check tmux sessions
  local tmux_sessions=$(tmux list-sessions 2>/dev/null | grep -c "claude:" || echo "0")
  echo -e "Tmux Sessions:        ${GREEN}$tmux_sessions${NC}"

  # Check mapped sessions
  local mapped=$(jq '.sessions | length' "$SESSION_MAP" 2>/dev/null || echo "0")
  echo -e "Mapped Sessions:      ${YELLOW}$mapped${NC}"

  # Check claude CLI availability
  if command -v claude &>/dev/null; then
    echo -e "Claude CLI:           ${GREEN}available${NC}"
  else
    echo -e "Claude CLI:           ${RED}not found${NC}"
  fi

  # Check log file
  if [[ -f "$LOG_FILE" ]]; then
    local log_size=$(du -h "$LOG_FILE" | awk '{print $1}')
    echo -e "Log File:             ${YELLOW}$LOG_FILE${NC} ($log_size)"
  fi

  echo ""
}

# Connect to remote host and start Claude session
remote-claude-session() {
  local host="${1:?Remote host required}"
  local project="${2:?Project name required}"
  local elevate=false

  [[ "$3" == "--elevate" ]] && elevate=true

  log_session "INFO" "Connecting to remote: $host"

  local cmd="source ~/.claude/skills/claude-project-sessions.sh && start-claude-project '$project'"
  [[ "$elevate" = true ]] && cmd="$cmd --elevate"

  ssh -q "your-user@$host" "$cmd"
}

# Main entry point for skill invocation
main() {
  local action="${1:-help}"
  shift || true

  case "$action" in
    start)
      start-claude-project "$@"
      ;;
    list)
      list-claude-sessions "$@"
      ;;
    restore)
      restore-claude-sessions "$@"
      ;;
    status)
      claude-session-status "$@"
      ;;
    remote)
      remote-claude-session "$@"
      ;;
    *)
      cat << 'EOF'
Claude Project Session Manager Skill

USAGE:
  start <project> [--elevate] [--remote HOST]   Start Claude session for project
  list [--remote HOST]                           List all sessions
  restore [--remote HOST] [--dry-run]            Restore all mapped sessions
  status [--remote HOST]                         Show session status
  remote <HOST> <PROJECT> [--elevate]            Remote connection shortcut

EXAMPLES:
  start-claude-project myproject
  start-claude-project myproject --elevate
  start-claude-project myproject --remote <remote-host>

  list-claude-sessions
  list-claude-sessions --remote <remote-host>

  remote-claude-session <remote-host> floads
  remote-claude-session <remote-host> infrastructure-project --elevate

CONFIGURATION:
  Session mappings: $HOME/.claude/session-restore-map.json
  Project paths:    $HOME/.claude/project-sessions.json
  Log file:         $HOME/.claude/project-sessions.log
EOF
      ;;
  esac
}

# Only run main if this script is invoked directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
