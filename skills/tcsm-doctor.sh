#!/usr/bin/env bash
# TCSM Doctor - Health check and cleanup utility for TCSM sessions
# Performs comprehensive validation and optional auto-repair of session registry

set -uo pipefail

# Configuration (inherited from parent tcsm.sh if sourced)
CLAUDE_HOME="${CLAUDE_HOME:-.claude}"
TCSM_SESSION_MAP="$HOME/$CLAUDE_HOME/tcsm-session-map.json"
TCSM_PROJECT_MAP="$HOME/$CLAUDE_HOME/tcsm-projects.json"
ACCOUNTS_FILE="$HOME/$CLAUDE_HOME/accounts.json"
TCSM_LOG_FILE="$HOME/$CLAUDE_HOME/tcsm.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State
VERBOSE=0
FIX_MODE=false
DRY_RUN=false
FORCE_FIX=false
CHECKS_FILTER=""
ISSUES_FOUND=0
WARNINGS_FOUND=0

# Helper functions
log_check() {
  local status="$1" msg="$2"
  case "$status" in
    PASS) echo -e "  ${GREEN}✓${NC} $msg" ;;
    FAIL) echo -e "  ${RED}✗${NC} $msg"; ((ISSUES_FOUND++)) ;;
    WARN) echo -e "  ${YELLOW}⚠${NC} $msg"; ((WARNINGS_FOUND++)) ;;
    INFO) [[ $VERBOSE -gt 0 ]] && echo -e "  ${BLUE}ℹ${NC} $msg" ;;
  esac
}

# Tier 1: Critical Registry/Tmux Mismatch Checks

check_registry_to_tmux() {
  [[ ! -f "$TCSM_SESSION_MAP" ]] && return 2

  local count=0 missing=0
  while IFS= read -r session; do
    ((count++))
    if ! tmux list-windows -t "tcsm:$session" &>/dev/null 2>&1; then
      ((missing++))
      log_check "FAIL" "Registry entry has no tmux window: $session"
    fi
  done < <(jq -r '.sessions | keys[]' "$TCSM_SESSION_MAP" 2>/dev/null || true)

  if [[ $missing -eq 0 ]]; then
    log_check "PASS" "Registry → Tmux ($count sessions have windows)"
    return 0
  else
    log_check "FAIL" "Registry → Tmux ($missing/$count missing windows)"
    return 1
  fi
}

check_tmux_to_registry() {
  local count=0 orphaned=0 orphaned_list=""
  while IFS= read -r window; do
    ((count++))
    if ! jq -e ".sessions | has(\"$window\")" "$TCSM_SESSION_MAP" &>/dev/null 2>/dev/null; then
      ((orphaned++))
      orphaned_list="$orphaned_list $window"
    fi
  done < <(tmux list-windows -t tcsm -F "#{window_name}" 2>/dev/null || true)

  if [[ $orphaned -eq 0 ]]; then
    log_check "PASS" "Tmux → Registry ($count windows tracked)"
    return 0
  else
    log_check "FAIL" "Tmux → Registry ($orphaned orphaned windows)"
    for w in $orphaned_list; do
      log_check "INFO" "  Orphaned window: tcsm:$w"
    done
    return 1
  fi
}

check_git_validation() {
  [[ ! -f "$TCSM_SESSION_MAP" ]] && return 2

  local count=0 invalid=0
  while IFS= read -r path; do
    ((count++))
    if ! git -C "$path" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
      ((invalid++))
      log_check "FAIL" "Path not under git control: $path"
    fi
  done < <(jq -r '.sessions[] | .path' "$TCSM_SESSION_MAP" 2>/dev/null || true)

  if [[ $invalid -eq 0 ]]; then
    log_check "PASS" "Git validation ($count paths are git-controlled)"
    return 0
  else
    log_check "FAIL" "Git validation ($invalid/$count not git-controlled)"
    return 1
  fi
}

check_duplicates() {
  [[ ! -f "$TCSM_SESSION_MAP" ]] && return 2

  local dupes=$(jq -r '.sessions | keys[]' "$TCSM_SESSION_MAP" 2>/dev/null | sort | uniq -d | wc -l)

  if [[ $dupes -eq 0 ]]; then
    log_check "PASS" "No duplicate session names"
    return 0
  else
    log_check "FAIL" "Found $dupes duplicate session names"
    jq -r '.sessions | keys[]' "$TCSM_SESSION_MAP" 2>/dev/null | sort | uniq -d | while read -r dup; do
      log_check "INFO" "  Duplicate: $dup"
    done
    return 1
  fi
}

# Tier 2: Account/Process Integrity Checks

check_account_validity() {
  [[ ! -f "$TCSM_SESSION_MAP" || ! -f "$ACCOUNTS_FILE" ]] && return 2

  local count=0 invalid=0
  while IFS=$'\t' read -r session account; do
    ((count++))
    if ! jq -e ".accounts[] | select(.id == \"$account\" and .active == true)" "$ACCOUNTS_FILE" &>/dev/null 2>/dev/null; then
      ((invalid++))
      log_check "WARN" "Session uses invalid/inactive account: $session (account: $account)"
    fi
  done < <(jq -r '.sessions | to_entries[] | "\(.key)\t\(.value.account // "primary")"' "$TCSM_SESSION_MAP" 2>/dev/null)

  if [[ $invalid -eq 0 ]]; then
    log_check "PASS" "Account validity ($count sessions use active accounts)"
    return 0
  else
    log_check "WARN" "Account validity ($invalid/$count use inactive accounts)"
    return 2
  fi
}

check_orphaned_processes() {
  local count=0 orphaned=0 orphaned_list=""
  while IFS= read -r name; do
    ((count++))
    if ! jq -e ".sessions | has(\"$name\")" "$TCSM_SESSION_MAP" &>/dev/null 2>/dev/null; then
      ((orphaned++))
      local pid
      pid=$(ps aux | grep "claude.*--name $name" | grep -v grep | awk '{print $2}')
      if [[ -n "$pid" ]]; then
        orphaned_list="$orphaned_list $pid:$name"
        log_check "WARN" "Orphaned Claude process: $name (PID $pid)"
      fi
    fi
  done < <(ps aux | grep "claude.*--name" | grep -v grep | grep -o "\-\-name [^ ]*" | awk '{print $2}')

  if [[ $orphaned -eq 0 ]]; then
    log_check "PASS" "No orphaned Claude processes"
    return 0
  else
    log_check "WARN" "Found $orphaned orphaned processes"
    return 2
  fi
}

check_file_permissions() {
  [[ ! -d "$HOME/$CLAUDE_HOME" ]] && return 2

  local perms
  perms=$(stat -c '%a' "$HOME/$CLAUDE_HOME" 2>/dev/null || stat -f '%A' "$HOME/$CLAUDE_HOME" 2>/dev/null)

  if [[ "$perms" == "750" || "$perms" == "755" || "$perms" == "700" ]]; then
    log_check "PASS" "File permissions OK (~/.claude/ is $perms)"
    return 0
  else
    log_check "WARN" "File permissions may be too restrictive (~/.claude/ is $perms)"
    return 2
  fi
}

# Tier 3: Data Quality Checks

check_log_file() {
  [[ ! -f "$TCSM_LOG_FILE" ]] && return 2

  local size_bytes
  size_bytes=$(stat -c %s "$TCSM_LOG_FILE" 2>/dev/null || stat -f %z "$TCSM_LOG_FILE" 2>/dev/null)
  local size_mb=$((size_bytes / 1024 / 1024))

  if [[ $size_mb -lt 10 ]]; then
    log_check "PASS" "Log file healthy ($size_mb MB)"
    return 0
  else
    log_check "WARN" "Log file is large ($size_mb MB, consider rotation)"
    return 2
  fi
}

check_map_integrity() {
  [[ ! -f "$TCSM_SESSION_MAP" ]] && return 2

  if jq empty "$TCSM_SESSION_MAP" 2>/dev/null; then
    local schemas_ok=true
    jq -e '.sessions | to_entries[] | select(.value | has("id", "path", "window")) | .key' "$TCSM_SESSION_MAP" &>/dev/null || schemas_ok=false

    if $schemas_ok; then
      log_check "PASS" "Session map integrity OK"
      return 0
    else
      log_check "FAIL" "Session map has schema violations"
      return 1
    fi
  else
    log_check "FAIL" "Session map is invalid JSON"
    return 1
  fi
}

# Main doctor function

show_summary() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"

  local status="OK"
  if [[ $ISSUES_FOUND -gt 0 ]]; then
    status="ERROR"
  elif [[ $WARNINGS_FOUND -gt 0 ]]; then
    status="WARNING"
  fi

  case "$status" in
    OK)
      echo -e "Status: ${GREEN}✓ OK${NC} (all checks passed)"
      ;;
    WARNING)
      echo -e "Status: ${YELLOW}⚠ WARNING${NC} ($WARNINGS_FOUND warnings, no critical issues)"
      ;;
    ERROR)
      echo -e "Status: ${RED}✗ ERROR${NC} ($ISSUES_FOUND critical issues, $WARNINGS_FOUND warnings)"
      ;;
  esac

  if [[ $FIX_MODE == true ]]; then
    echo "Mode: $([[ $DRY_RUN == true ]] && echo "DRY-RUN" || echo "FIX")"
  fi

  echo "════════════════════════════════════════════════════════════════"
}

run_checks() {
  echo -e "${BLUE}=== Critical Registry/Tmux Checks ===${NC}"
  check_registry_to_tmux
  check_tmux_to_registry
  check_git_validation
  check_duplicates

  echo ""
  echo -e "${BLUE}=== Account/Process Integrity ===${NC}"
  check_account_validity
  check_orphaned_processes
  check_file_permissions

  echo ""
  echo -e "${BLUE}=== Data Quality ===${NC}"
  check_log_file
  check_map_integrity

  show_summary
}

# Usage
tcsm_doctor_usage() {
  cat << 'EOF'
TCSM Doctor - Session health check and repair

Usage: tcsm-doctor [options]

Options:
  -v, --verbose         Verbose output
  --fix                 Fix issues (requires confirmation for destructive ops)
  --fix-orphans         Only fix orphaned processes and windows
  --dry-run             Show what would be fixed without making changes
  --force               Skip confirmations
  --check TYPE          Run specific check (sessions,git,accounts,orphans)
  -h, --help            Show this help

Examples:
  tcsm-doctor                    # Check only, report issues
  tcsm-doctor -v                 # Verbose report
  tcsm-doctor --check accounts   # Check specific area
  tcsm-doctor --fix --dry-run    # Show fixes without applying
  tcsm-doctor --fix --force      # Auto-fix all issues without confirmation

EOF
}

# Main
main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose) VERBOSE=$((VERBOSE + 1)) ;;
      --fix) FIX_MODE=true ;;
      --dry-run) DRY_RUN=true ;;
      --force) FORCE_FIX=true ;;
      --check) CHECKS_FILTER="$2"; shift ;;
      -h|--help) tcsm_doctor_usage; exit 0 ;;
      *) echo "Unknown option: $1"; tcsm_doctor_usage; exit 1 ;;
    esac
    shift
  done

  run_checks

  # Exit code reflects status
  if [[ $ISSUES_FOUND -gt 0 ]]; then
    exit 1
  elif [[ $WARNINGS_FOUND -gt 0 ]]; then
    exit 2
  else
    exit 0
  fi
}

main "$@"
