#!/bin/bash
#
# SE Demo Preparation CLI
# Quick interface for gathering customer context and preparing demos
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATIONS_DIR="${SCRIPT_DIR}/integrations"
CONFIG_FILE="${INTEGRATIONS_DIR}/config.json"
DATA_DIR="${HOME}/.claude/data/customer-contexts"
AGGREGATOR="${INTEGRATIONS_DIR}/customer_context_aggregator.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

# Check dependencies
check_dependencies() {
    local missing=0

    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found"
        missing=1
    fi

    if ! python3 -c "import requests" &> /dev/null; then
        log_error "Python 'requests' library not found"
        echo "  Install with: pip3 install requests"
        missing=1
    fi

    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "Config file not found: ${CONFIG_FILE}"
        missing=1
    fi

    if [ ! -f "${AGGREGATOR}" ]; then
        log_error "Aggregator script not found: ${AGGREGATOR}"
        missing=1
    fi

    return $missing
}

# Test connections
test_connections() {
    print_header "Testing Connections"

    cd "${INTEGRATIONS_DIR}"

    for client in gong_client.py hubspot_client.py github_client.py qodo_client.py; do
        if [ -f "$client" ]; then
            log_info "Testing ${client%.py}..."
            python3 "$client" "${CONFIG_FILE}" 2>&1 | tail -n 3
        fi
    done
}

# Gather context
gather_context() {
    local company="$1"
    local github_org="${2:-}"
    local github_repo="${3:-}"

    print_header "Gathering Context: $company"

    cd "${INTEGRATIONS_DIR}"

    local cmd="python3 ${AGGREGATOR} ${CONFIG_FILE} \"${company}\""

    if [ -n "$github_org" ]; then
        cmd="$cmd \"${github_org}\""
    fi

    if [ -n "$github_repo" ]; then
        cmd="$cmd \"${github_repo}\""
    fi

    eval "$cmd"
}

# View saved context
view_context() {
    local company="$1"
    local filename="${company// /-}"
    filename="${filename,,}"  # lowercase
    local context_file="${DATA_DIR}/${filename}.json"

    if [ ! -f "$context_file" ]; then
        log_error "Context not found for: $company"
        echo "  Expected: $context_file"
        echo ""
        log_info "Available contexts:"
        list_contexts
        return 1
    fi

    print_header "Customer Context: $company"

    if command -v jq &> /dev/null; then
        cat "$context_file" | jq .
    else
        cat "$context_file"
    fi
}

# List saved contexts
list_contexts() {
    print_header "Saved Customer Contexts"

    if [ ! -d "$DATA_DIR" ]; then
        log_warning "No contexts directory found"
        return
    fi

    local count=0
    for file in "${DATA_DIR}"/*.json; do
        if [ -f "$file" ]; then
            local basename=$(basename "$file" .json)
            local company="${basename//-/ }"
            company="${company^}"  # capitalize first letter

            # Get summary if jq available
            if command -v jq &> /dev/null; then
                local readiness=$(jq -r '.executive_summary.demo_readiness_score // "Unknown"' "$file")
                local insights=$(jq -r '.executive_summary.key_insights | length' "$file")
                echo "  • ${company} - ${readiness} (${insights} insights)"
            else
                echo "  • ${company}"
            fi

            ((count++))
        fi
    done

    if [ $count -eq 0 ]; then
        log_warning "No saved contexts found"
    else
        echo ""
        log_success "Total: $count contexts"
    fi
}

# Generate demo script
generate_demo_script() {
    local company="$1"
    local filename="${company// /-}"
    filename="${filename,,}"
    local context_file="${DATA_DIR}/${filename}.json"

    if [ ! -f "$context_file" ]; then
        log_error "Context not found for: $company"
        echo "  Run: $0 gather \"$company\" first"
        return 1
    fi

    print_header "Demo Script: $company"

    if ! command -v jq &> /dev/null; then
        log_error "jq is required for demo script generation"
        return 1
    fi

    # Extract demo script
    local script=$(cat "$context_file" | jq '.demo_script.script')

    echo "$script" | jq -r '
        "INTRODUCTION (" + .introduction.duration + ")",
        "─────────────────────────────────────────────────────────",
        (.introduction.talking_points | map("  • " + .) | join("\n")),
        "",
        "PAIN POINT REVIEW (" + .pain_point_review.duration + ")",
        "─────────────────────────────────────────────────────────",
        (.pain_point_review.talking_points | map("  • " + .) | join("\n")),
        "",
        "SOLUTION DEMO (" + .solution_demo.duration + ")",
        "─────────────────────────────────────────────────────────",
        (.solution_demo.products | map(
            "  Product: " + .product,
            "  Why: " + .why_relevant,
            "  Demo Flow:",
            (.demo_flow | map("    " + (tostring | split(". ")[1] // .)) | join("\n")),
            ""
        ) | join("\n")),
        "ROI DISCUSSION (" + .roi_discussion.duration + ")",
        "─────────────────────────────────────────────────────────",
        (.roi_discussion.talking_points | map("  • " + .) | join("\n")),
        "",
        "NEXT STEPS (" + .next_steps.duration + ")",
        "─────────────────────────────────────────────────────────",
        (.next_steps.talking_points | map("  • " + .) | join("\n"))
    '

    echo ""
    log_success "Demo script ready"
}

# Show recommendations
show_recommendations() {
    local company="$1"
    local filename="${company// /-}"
    filename="${filename,,}"
    local context_file="${DATA_DIR}/${filename}.json"

    if [ ! -f "$context_file" ]; then
        log_error "Context not found for: $company"
        return 1
    fi

    print_header "Product Recommendations: $company"

    if ! command -v jq &> /dev/null; then
        log_error "jq is required"
        return 1
    fi

    cat "$context_file" | jq -r '.qodo_recommendations.recommendations[] |
        "Product: " + .product_name,
        "Reason: " + .reason,
        "Tech Fit: " + .tech_fit,
        "Key Features:",
        (.details.capabilities[0:3] | map("  • " + .) | join("\n")),
        "────────────────────────────────────────────────────────",
        ""
    '
}

# Show usage
usage() {
    cat << EOF
SE Demo Preparation CLI

Usage:
  $0 <command> [arguments]

Commands:
  test                          Test connections to all data sources
  gather <company> [org] [repo] Gather customer context
  list                          List saved customer contexts
  view <company>                View saved context (JSON)
  script <company>              Generate demo script
  recommendations <company>     Show product recommendations
  help                          Show this help message

Examples:
  # Test connections
  $0 test

  # Gather context for a company
  $0 gather "Acme Corp"
  $0 gather "TechCo" techco-org
  $0 gather "StartupInc" startupinc-org backend-api

  # List all saved contexts
  $0 list

  # View context
  $0 view "Acme Corp"

  # Generate demo script
  $0 script "Acme Corp"

  # Show recommendations
  $0 recommendations "Acme Corp"

Setup:
  1. Configure integrations in: ${CONFIG_FILE}
  2. Add credentials to: ~/.claude/credentials/
     - gong.json, hubspot.json, github.json, qodo.json
  3. Install dependencies: pip3 install requests

Files:
  Config: ${CONFIG_FILE}
  Data: ${DATA_DIR}
  Scripts: ${INTEGRATIONS_DIR}

EOF
}

# Main
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        test)
            check_dependencies || exit 1
            test_connections
            ;;

        gather)
            if [ $# -eq 0 ]; then
                log_error "Company name required"
                echo "Usage: $0 gather <company> [github_org] [github_repo]"
                exit 1
            fi
            check_dependencies || exit 1
            gather_context "$@"
            ;;

        list)
            list_contexts
            ;;

        view)
            if [ $# -eq 0 ]; then
                log_error "Company name required"
                exit 1
            fi
            view_context "$1"
            ;;

        script)
            if [ $# -eq 0 ]; then
                log_error "Company name required"
                exit 1
            fi
            generate_demo_script "$1"
            ;;

        recommendations|recs)
            if [ $# -eq 0 ]; then
                log_error "Company name required"
                exit 1
            fi
            show_recommendations "$1"
            ;;

        help|--help|-h)
            usage
            ;;

        *)
            log_error "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
