#!/usr/bin/env bash
# TCSM (tmux-claude-session-manager) Skill
# Manages Claude CLI sessions in tmux windows for projects with remote support
# Usage: source this file or call functions directly
#
# Functions:
#   tcsm-start <project> [--elevate] [--remote <host>]
#   tcsm-stop <project> [--remote <host>]
#   tcsm-restart <project> [--elevate] [--remote <host>]
#   tcsm-list [--remote <host>]
#   tcsm-restore [--remote <host>] [--dry-run]
#   tcsm-status [--remote <host>]
#   tcsm-remote <host> <project> [--elevate]
#
# Configuration (via environment variables):
#   TCSM_SEARCH_ROOTS - Space-separated paths to search for git-controlled project dirs
#                       (default: $HOME/src $HOME/.flamelet/tenant)

set -uo pipefail

# Configuration
CLAUDE_HOME="${CLAUDE_HOME:-.claude}"
TCSM_SESSION_MAP="$HOME/$CLAUDE_HOME/tcsm-session-map.json"
TCSM_PROJECT_MAP="$HOME/$CLAUDE_HOME/tcsm-projects.json"
TCSM_LOG_FILE="$HOME/$CLAUDE_HOME/tcsm.log"
TCSM_SEARCH_ROOTS="${TCSM_SEARCH_ROOTS:-$HOME/src $HOME/.flamelet/tenant}"

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
  echo -e "${msg}" | tee -a "$TCSM_LOG_FILE" 2>/dev/null || echo -e "${msg}"
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

# Clean up orphaned session files (files with no corresponding tmux window)
cleanup_orphaned_sessions() {
  local cleaned=0
  [[ ! -d "$HOME/$CLAUDE_HOME/sessions" ]] && return 0

  for sessfile in "$HOME/$CLAUDE_HOME/sessions"/*.json; do
    [[ ! -f "$sessfile" ]] && continue

    local name=$(jq -r '.name // empty' "$sessfile" 2>/dev/null)
    [[ -z "$name" ]] && continue

    local window_name="${name//\//-}"
    # Check if corresponding tmux window exists
    if ! tmux list-windows -t "tcsm:$window_name" &>/dev/null 2>&1; then
      rm -f "$sessfile"
      ((cleaned++))
    fi
  done

  [[ $cleaned -gt 0 ]] && log_session "INFO" "Cleaned up $cleaned orphaned session file(s)"
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

  if [[ ! -f "$TCSM_SESSION_MAP" ]]; then
    cat > "$TCSM_SESSION_MAP" << 'EOF'
{
  "sessions": {},
  "lastUpdated": null
}
EOF
    log_session "INFO" "Created session map: $TCSM_SESSION_MAP"
  fi

  if [[ ! -f "$TCSM_PROJECT_MAP" ]]; then
    cat > "$TCSM_PROJECT_MAP" << 'EOF'
{
  "sessions": {}
}
EOF
    log_session "INFO" "Created project map: $TCSM_PROJECT_MAP"
  fi
}

# Validate that an account exists and is active
validate_account() {
  local account_id="$1"
  local accounts_file="$HOME/$CLAUDE_HOME/accounts.json"

  [[ ! -f "$accounts_file" ]] && return 1

  # Check if account exists and is active
  jq -e ".accounts[] | select(.id == \"$account_id\" and .active == true)" "$accounts_file" &>/dev/null
  return $?
}

# Get rate limit tier for an account
get_rate_limit_tier() {
  local account_id="$1"
  local accounts_file="$HOME/$CLAUDE_HOME/accounts.json"

  [[ ! -f "$accounts_file" ]] && echo "unknown" && return 0

  jq -r ".accounts[] | select(.id == \"$account_id\") | .rate_limit_tier // \"unknown\"" "$accounts_file" 2>/dev/null || echo "unknown"
}

# Get account display info (label from metadata.organization)
get_account_display() {
  local account_id="$1"
  local accounts_file="$HOME/$CLAUDE_HOME/accounts.json"

  [[ ! -f "$accounts_file" ]] && echo "$account_id" && return 0

  jq -r ".accounts[] | select(.id == \"$account_id\") | .metadata.organization // .id" "$accounts_file" 2>/dev/null || echo "$account_id"
}

# Search TCSM_SEARCH_ROOTS for a git-controlled directory exactly named $1
tcsm-find-git-dir() {
  local project="$1" root candidate
  for root in $TCSM_SEARCH_ROOTS; do
    candidate="$root/$project"
    if [[ -d "$candidate" ]] && git -C "$candidate" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Start a Claude session for a project
tcsm-start() {
  local project="${1:?Project name required}"
  local elevate=false
  local remote=""
  local account="primary"

  # Parse options
  while [[ $# -gt 1 ]]; do
    case "$2" in
      --elevate) elevate=true ;;
      --remote) remote="$3"; shift ;;
      --account) account="$3"; shift ;;
      *) echo "Unknown option: $2" >&2; return 1 ;;
    esac
    shift
  done

  # If remote, delegate to remote host (pass account through)
  if [[ -n "$remote" ]]; then
    tcsm-remote "$remote" "$project" $([ "$elevate" = true ] && echo "--elevate") --account "$account"
    return $?
  fi

  # Validate account
  if ! validate_account "$account"; then
    log_session "ERROR" "Invalid or inactive account: $account"
    echo -e "${RED}✗${NC} Account not found or inactive: ${YELLOW}$account${NC}"
    return 1
  fi

  check_prerequisites || return 1
  init_mapping_files

  local project_dir
  # Try to resolve from tcsm-projects.json first
  if [[ -f "$TCSM_PROJECT_MAP" ]]; then
    project_dir=$(jq -r ".sessions[\"$project\"].path // empty" "$TCSM_PROJECT_MAP" 2>/dev/null)
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
      # Last resort: search TCSM_SEARCH_ROOTS for any matching directory
      local root candidate
      for root in $TCSM_SEARCH_ROOTS; do
        candidate="$root/$project"
        if [[ -d "$candidate" ]]; then
          project_dir="$candidate"
          break
        fi
      done

      if [[ -z "$project_dir" ]]; then
        log_session "ERROR" "Project directory not found: $project"
        return 1
      fi
    fi
  fi

  # Enforce: project directory must be under git control
  if ! git -C "$project_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    local git_dir
    if git_dir=$(tcsm-find-git-dir "$project"); then
      log_session "INFO" "'$project_dir' is not under git control; using git-controlled source instead: $git_dir"
      project_dir="$git_dir"
    else
      log_session "ERROR" "Project '$project' is not under git control: $project_dir"
      log_session "ERROR" "Searched TCSM_SEARCH_ROOTS ($TCSM_SEARCH_ROOTS) but found no git-controlled version"
      log_session "ERROR" "All TCSM sessions must be in git-controlled directories"
      echo -e "${RED}✗${NC} Project not under git control: ${BLUE}$project${NC}"
      echo -e "  Path:  ${YELLOW}$project_dir${NC}"
      echo -e "  Searched: ${YELLOW}${TCSM_SEARCH_ROOTS}${NC}"
      return 1
    fi
  fi

  # Resolve window name from project
  local window_name="${project//\//-}"

  # Check if tmux window exists
  if tmux list-windows -t "tcsm:$window_name" &>/dev/null 2>&1; then
    log_session "INFO" "Window already exists: tcsm:$window_name"
  else
    # Create window in tcsm session
    if ! tmux new-window -t tcsm -n "$window_name" -c "$project_dir"; then
      log_session "ERROR" "Failed to create tmux window: $window_name"
      return 1
    fi
    log_session "OK" "Created tmux window: tcsm:$window_name"
  fi

  # Pre-trust workspace to avoid trust dialog on startup
  ensure_workspace_trusted "$project_dir"

  # Additional step: explicitly set trust via claude config to work around
  # a known issue where the trust dialog still appears even when hasTrustDialogAccepted
  # is set in ~/.claude.json (see: https://github.com/anthropics/claude-code/issues/9113)
  claude config set "workspaceTrustSettings.\"$project_dir\".hasTrustDialogAccepted" true 2>/dev/null || true

  # Start Claude session interactively in tmux window
  # Interactive mode auto-registers session and allows attaching
  local claude_cmd="claude --model haiku --permission-mode bypassPermissions --remote-control --name $project"
  [[ "$elevate" = true ]] && claude_cmd="sudo $claude_cmd"

  # Get rate limit tier for account
  local rate_limit_tier
  rate_limit_tier=$(get_rate_limit_tier "$account")

  # Send Claude command to tmux window (runs interactively)
  if tmux send-keys -t "tcsm:$window_name" "$claude_cmd" Enter; then
    # Update session map with account and rate limit info
    jq --arg proj "$project" --arg path "$project_dir" --arg acct "$account" --arg tier "$rate_limit_tier" \
      '.sessions[$proj] = {id: $proj, path: $path, window: $proj, account: $acct, rate_limit_tier: $tier, created: now}' \
      "$TCSM_SESSION_MAP" > "${TCSM_SESSION_MAP}.tmp" && mv "${TCSM_SESSION_MAP}.tmp" "$TCSM_SESSION_MAP"

    # Wait for Claude to register the session (creates ~/.claude/sessions/*.json)
    # This is critical: the session file must exist before we return for web UI integration
    local wait_count=0
    while [[ $wait_count -lt 50 ]]; do  # 5 seconds max (50 * 0.1s)
      if grep -l "\"$project\"" "$HOME/$CLAUDE_HOME/sessions"/*.json 2>/dev/null | grep -q .; then
        break
      fi
      sleep 0.1
      ((wait_count++))
    done

    if [[ $wait_count -ge 50 ]]; then
      log_session "WARN" "Session file not created within 5s: $project (may still be starting)"
    else
      log_session "INFO" "Session registered after $((wait_count * 100))ms"
    fi

    log_session "OK" "Started Claude session: $project"
    echo -e "${GREEN}✓${NC} Claude session started for ${BLUE}$project${NC}"
    echo -e "  Window:  ${YELLOW}tcsm:$window_name${NC}"
    echo -e "  Path:    ${YELLOW}$project_dir${NC}"
    echo -e "  Attach:  ${YELLOW}tmux attach -t tcsm:$window_name${NC}"
    return 0
  else
    log_session "ERROR" "Failed to send command to tmux window"
    return 1
  fi
}

# Stop a Claude session for a project
tcsm-stop() {
  local project="${1:?Project name required}"
  local remote="${2:-}"

  # Parse options
  while [[ $# -gt 1 ]]; do
    case "$2" in
      --remote) remote="$3"; shift ;;
      *) echo "Unknown option: $2" >&2; return 1 ;;
    esac
    shift
  done

  # If remote, delegate to remote host
  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/tcsm.sh && tcsm-stop '$project'"
    return $?
  fi

  check_prerequisites || return 1

  local window_name="${project//\//-}"

  # Check if tmux window exists
  if tmux list-windows -t "tcsm:$window_name" &>/dev/null 2>&1; then
    # Get the pane PID before anything else
    local pane_pid=$(tmux display-message -t "tcsm:$window_name" -p '#{pane_pid}' 2>/dev/null)

    # Graceful shutdown: signal escalation with timeouts
    if [[ -n "$pane_pid" ]]; then
      # Step 1: Send Ctrl-C (SIGINT) - ask Claude to exit gracefully
      log_session "INFO" "Sending SIGINT (Ctrl-C) to process $pane_pid"
      tmux send-keys -t "tcsm:$window_name" C-c

      # Step 2: Wait up to 5 seconds for graceful exit
      local wait_count=0
      while [[ $wait_count -lt 50 ]]; do
        if ! kill -0 "$pane_pid" 2>/dev/null; then
          log_session "OK" "Process $pane_pid exited gracefully"
          break
        fi
        sleep 0.1
        ((wait_count++))
      done

      # Step 3: If still running, escalate to SIGTERM
      if kill -0 "$pane_pid" 2>/dev/null; then
        log_session "INFO" "Process didn't exit; sending SIGTERM to $pane_pid"
        kill -TERM "$pane_pid" 2>/dev/null || true
        sleep 2
      fi

      # Step 4: Final resort - SIGKILL
      if kill -0 "$pane_pid" 2>/dev/null; then
        log_session "WARN" "Process still running; forcing SIGKILL on $pane_pid"
        kill -KILL "$pane_pid" 2>/dev/null || true
      fi
    fi

    # Kill any remaining claude processes for this project (cleanup)
    pkill -f "claude.*--name $project" 2>/dev/null || true

    # Clean up the tmux window
    tmux kill-window -t "tcsm:$window_name" 2>/dev/null || true

    # Clean up Claude session files to force fresh registration on restart
    # Remove ONLY session files where name EXACTLY matches this project (via jq)
    for sessfile in "$HOME/.claude/sessions"/*.json; do
      if [[ -f "$sessfile" ]]; then
        # Only delete if name matches EXACTLY
        if jq -e ".name == \"$project\"" "$sessfile" &>/dev/null; then
          rm -f "$sessfile"
          log_session "INFO" "Cleaned session file: $(basename $sessfile)"
        fi
      fi
    done

    log_session "OK" "Stopped Claude session: $project"
    echo -e "${GREEN}✓${NC} Claude session stopped for ${BLUE}$project${NC}"
    return 0
  else
    log_session "INFO" "Session not running: $project"
    echo -e "${YELLOW}ℹ${NC} Session not running: ${BLUE}$project${NC}"
    return 0
  fi
}

# Restart a Claude session for a project
tcsm-restart() {
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
    ssh -q "your-user@$remote" "source ~/.claude/skills/tcsm.sh && tcsm-restart '$project' $([ "$elevate" = true ] && echo "--elevate")"
    return $?
  fi

  log_session "INFO" "Restarting Claude session: $project"
  echo -e "${BLUE}⟲${NC} Restarting Claude session for ${BLUE}$project${NC}..."

  # Stop the session (ignore errors if not running)
  tcsm-stop "$project" >/dev/null 2>&1 || true

  sleep 1

  # Start the session again
  tcsm-start "$project" $([ "$elevate" = true ] && echo "--elevate")
}

# List all Claude sessions
tcsm-list() {
  local remote="${1:-}"

  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/tcsm.sh && tcsm-list"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files
  cleanup_orphaned_sessions

  echo -e "${BLUE}=== TCSM Project Sessions ===${NC}\n"

  if [[ ! -f "$TCSM_SESSION_MAP" ]] || ! jq -e '.sessions | length > 0' "$TCSM_SESSION_MAP" &>/dev/null; then
    echo -e "${YELLOW}No sessions configured${NC}"
    return 0
  fi

  echo -e "${BLUE}Project${NC:25} ${BLUE}Window${NC:18} ${BLUE}Status${NC:12} ${BLUE}Account${NC:15} ${BLUE}Rate Limit${NC:20} ${BLUE}Path${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  jq -r '.sessions | to_entries[] |
    "\(.key)\t\(.value.window)\t\(.value.account // "primary")\t\(.value.rate_limit_tier // "unknown")\t\(.value.path)"' "$TCSM_SESSION_MAP" | \
  while IFS=$'\t' read -r project window account rate_limit path; do
    # Check if window exists in tmux
    local status="inactive"
    if tmux list-windows -t "tcsm:$window" &>/dev/null 2>&1; then
      status="${GREEN}active${NC}"
    fi

    # Get account display name
    local account_display
    account_display=$(get_account_display "$account")

    # Format rate limit (abbreviated for display)
    local rate_display="${rate_limit//default_claude_/}"
    rate_display="${rate_display//default_/}"

    printf "%-25s %-18s %-12b %-15s %-20s %s\n" \
      "${BLUE}$project${NC}" \
      "${YELLOW}$window${NC}" \
      "$status" \
      "$account_display" \
      "$rate_display" \
      "$path"
  done

  echo ""
}

# Restore all Claude sessions (boot-time)
tcsm-restore() {
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
    ssh -q "your-user@$remote" "source ~/.claude/skills/tcsm.sh && tcsm-restore $([ "$dry_run" = true ] && echo "--dry-run")"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files

  log_session "INFO" "Starting session restoration..."

  if [[ ! -f "$TCSM_SESSION_MAP" ]] || ! jq -e '.sessions | length > 0' "$TCSM_SESSION_MAP" &>/dev/null; then
    log_session "INFO" "No sessions to restore"
    return 0
  fi

  local restored=0
  jq -r '.sessions | to_entries[] | "\(.key)\t\(.value.path)\t\(.value.window)"' "$TCSM_SESSION_MAP" | \
  while IFS=$'\t' read -r project path window; do
    if [[ "$dry_run" == "true" ]]; then
      log_session "DRY-RUN" "Would restore: $project → $window"
    else
      if tcsm-start "$project" &>/dev/null; then
        ((restored++))
      fi
    fi
  done

  log_session "OK" "Restoration complete ($restored sessions)"
}

# Show session status
tcsm-status() {
  local remote="${1:-}"

  if [[ -n "$remote" ]]; then
    ssh -q "your-user@$remote" "source ~/.claude/skills/tcsm.sh && tcsm-status"
    return $?
  fi

  check_prerequisites || return 1
  init_mapping_files
  cleanup_orphaned_sessions

  echo -e "${BLUE}=== TCSM Session Status ===${NC}\n"

  # Check tmux sessions
  local tmux_sessions=$(tmux list-sessions 2>/dev/null | grep -c "tcsm:" || echo "0")
  echo -e "Tmux Sessions:        ${GREEN}$tmux_sessions${NC}"

  # Check mapped sessions
  local mapped=$(jq '.sessions | length' "$TCSM_SESSION_MAP" 2>/dev/null || echo "0")
  echo -e "Mapped Sessions:      ${YELLOW}$mapped${NC}"

  # Check claude CLI availability
  if command -v claude &>/dev/null; then
    echo -e "Claude CLI:           ${GREEN}available${NC}"
  else
    echo -e "Claude CLI:           ${RED}not found${NC}"
  fi

  # Check log file
  if [[ -f "$TCSM_LOG_FILE" ]]; then
    local log_size=$(du -h "$TCSM_LOG_FILE" | awk '{print $1}')
    echo -e "Log File:             ${YELLOW}$TCSM_LOG_FILE${NC} ($log_size)"
  fi

  echo ""

  # Show per-session account and rate limit info
  if [[ $mapped -gt 0 ]]; then
    echo -e "${BLUE}=== Session Account Info ===${NC}"
    jq -r '.sessions | to_entries[] |
      "\(.key)\t\(.value.account // "primary")\t\(.value.rate_limit_tier // "unknown")"' "$TCSM_SESSION_MAP" | \
    while IFS=$'\t' read -r project account rate_limit; do
      local account_display
      account_display=$(get_account_display "$account")
      local rate_display="${rate_limit//default_claude_/}"
      rate_display="${rate_display//default_/}"
      printf "  %-25s %-15s %s\n" "$project" "$account_display" "$rate_display"
    done
    echo ""
  fi
}

# Connect to remote host and start Claude session
tcsm-remote() {
  local host="${1:?Remote host required}"
  local project="${2:?Project name required}"
  local elevate=false

  [[ "$3" == "--elevate" ]] && elevate=true

  log_session "INFO" "Connecting to remote: $host"

  local cmd="source ~/.claude/skills/tcsm.sh && tcsm-start '$project'"
  [[ "$elevate" = true ]] && cmd="$cmd --elevate"

  ssh -q "your-user@$host" "$cmd"
}

# Main entry point for skill invocation
main() {
  local action="${1:-help}"
  shift || true

  case "$action" in
    start)
      tcsm-start "$@"
      ;;
    stop)
      tcsm-stop "$@"
      ;;
    restart)
      tcsm-restart "$@"
      ;;
    list)
      tcsm-list "$@"
      ;;
    restore)
      tcsm-restore "$@"
      ;;
    status)
      tcsm-status "$@"
      ;;
    remote)
      tcsm-remote "$@"
      ;;
    *)
      cat << 'EOF'
TCSM (tmux-claude-session-manager) Skill

USAGE:
  start <project> [--elevate] [--remote HOST]   Start Claude session for project
  stop <project> [--remote HOST]                 Stop a running Claude session
  restart <project> [--elevate] [--remote HOST] Restart Claude session for project
  list [--remote HOST]                           List all sessions
  restore [--remote HOST] [--dry-run]            Restore all mapped sessions
  status [--remote HOST]                         Show session status
  remote <HOST> <PROJECT> [--elevate]            Remote connection shortcut

EXAMPLES:
  tcsm-start myproject
  tcsm-start myproject --elevate
  tcsm-start myproject --remote <remote-host>

  tcsm-stop myproject
  tcsm-stop myproject --remote <remote-host>

  tcsm-restart myproject
  tcsm-restart myproject --elevate

  tcsm-list
  tcsm-list --remote <remote-host>

  tcsm-remote <remote-host> floads
  tcsm-remote <remote-host> infrastructure-project --elevate

CONFIGURATION:
  Session mappings: $HOME/.claude/tcsm-session-map.json
  Project paths:    $HOME/.claude/tcsm-projects.json
  Log file:         $HOME/.claude/tcsm.log

ENVIRONMENT VARIABLES:
  TCSM_SEARCH_ROOTS - Space-separated directories to search for git-controlled project folders
                      (default: \$HOME/src \$HOME/.flamelet/tenant)
                      When tcsm-start resolves a project directory that isn't under git control,
                      it searches these roots for a matching folder that is, and uses that instead.
EOF
      ;;
  esac
}

# Only run main if this script is invoked directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
