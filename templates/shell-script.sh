#!/usr/bin/env bash
# Quick shell script template
# Optimized for reliability and safety

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RESET='\033[0m'

# Functions
log_info() {
  echo -e "${BLUE}ℹ${RESET} $*"
}

log_success() {
  echo -e "${GREEN}✓${RESET} $*"
}

log_warning() {
  echo -e "${YELLOW}⚠${RESET} $*"
}

log_error() {
  echo -e "${RED}✗${RESET} $*" >&2
}

# Main
main() {
  log_info "Script starting..."

  # Your code here

  log_success "Done"
}

main "$@"
