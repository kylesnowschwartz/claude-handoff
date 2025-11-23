#!/usr/bin/env bash
# logging.sh - Centralized logging module for claude-handoff hooks
#
# USAGE:
#   # At top of your hook script:
#   source "${BASH_SOURCE%/*}/../lib/logging.sh"
#   init_logging "hook-name"
#
#   # Then use throughout script:
#   log "Your message here"
#   log "Variables: foo=$foo bar=$bar"
#
# TOGGLE LOGGING:
#   Change LOGGING_ENABLED below to control ALL hook logging from one place.
#   Can also set environment variable: export LOGGING_ENABLED=false
#   Environment variable takes precedence if set.
#
# WHERE LOGS GO:
#   /tmp/handoff-<hook-name>.log (fresh file on each hook invocation)
# ============================================================================

LOGGING_ENABLED=false # Set to false to disable all logging

# Log file will be set by init_logging
LOG_FILE=""

# Initialize logging for a hook
# Usage: init_logging "hook-name"
init_logging() {
  local hook_name="${1:-unknown}"

  # Environment variable takes precedence
  local enabled="${LOGGING_ENABLED:-true}"

  if [[ "$enabled" != "true" ]]; then
    # Logging disabled - create no-op log function
    log() { :; }
    return
  fi

  # Setup log file
  LOG_FILE="/tmp/handoff-${hook_name}.log"

  # Fresh log file for each invocation
  : >"$LOG_FILE"

  # Redirect stderr to log file
  exec 2>>"$LOG_FILE"

  # Enable bash tracing
  set -x

  # Create real log function
  log() {
    echo "[$(date -Iseconds)] $*" >>"$LOG_FILE"
  }

  # Log initialization
  log "=== ${hook_name} hook started ==="
}

# Export for use in sourcing scripts
export -f init_logging 2>/dev/null || true
