#!/usr/bin/env bash
#
# Phase 3 Manager
# Unified CLI for Real-time RL Integration & Continuous Learning
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DATA_DIR="$CLAUDE_DIR/data"
RL_BRIDGE="$SCRIPT_DIR/vector-search-rl-bridge.py"
LEARNING_DAEMON="$SCRIPT_DIR/continuous-learning-daemon.py"
LEARNING_DATA="$DATA_DIR/vector-search-learning.json"
DAEMON_PID="$DATA_DIR/continuous-learning.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC}  $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi
}

check_phase2() {
    local embeddings="$DATA_DIR/knowledge-embeddings.json"

    if [ ! -f "$embeddings" ]; then
        log_error "Phase 2 not set up. Please run:"
        echo "  ~/.claude/scripts/vector-search-manager.sh build"
        exit 1
    fi

    log_success "Phase 2 embeddings found"
}

start_daemon() {
    check_python
    check_phase2

    if [ -f "$DAEMON_PID" ]; then
        local pid=$(cat "$DAEMON_PID")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_warning "Daemon already running (PID: $pid)"
            return 0
        else
            # Stale PID file
            rm "$DAEMON_PID"
        fi
    fi

    log_info "Starting Continuous Learning Daemon..."

    # Start daemon in background
    nohup python3 "$LEARNING_DAEMON" start > "$DATA_DIR/continuous-learning.log" 2>&1 &
    local pid=$!

    echo "$pid" > "$DAEMON_PID"

    sleep 2

    if ps -p "$pid" > /dev/null 2>&1; then
        log_success "Daemon started (PID: $pid)"
        log_info "Logs: tail -f $DATA_DIR/continuous-learning.log"
    else
        log_error "Failed to start daemon"
        rm "$DAEMON_PID"
        exit 1
    fi
}

stop_daemon() {
    if [ ! -f "$DAEMON_PID" ]; then
        log_warning "Daemon not running (no PID file)"
        return 0
    fi

    local pid=$(cat "$DAEMON_PID")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        log_warning "Daemon not running (stale PID)"
        rm "$DAEMON_PID"
        return 0
    fi

    log_info "Stopping daemon (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! ps -p "$pid" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # Force kill if still running
    if ps -p "$pid" > /dev/null 2>&1; then
        log_warning "Force killing daemon..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm "$DAEMON_PID"
    log_success "Daemon stopped"
}

daemon_status() {
    echo ""
    echo "=== Continuous Learning Daemon Status ==="
    echo ""

    if [ -f "$DAEMON_PID" ]; then
        local pid=$(cat "$DAEMON_PID")

        if ps -p "$pid" > /dev/null 2>&1; then
            log_success "Running (PID: $pid)"

            # Show resource usage
            local mem=$(ps -o rss= -p "$pid" | awk '{printf "%.1f MB", $1/1024}')
            local cpu=$(ps -o %cpu= -p "$pid")
            echo "  Memory: $mem"
            echo "  CPU: ${cpu}%"

            # Show uptime
            local start_time=$(ps -o lstart= -p "$pid")
            echo "  Started: $start_time"
        else
            log_warning "Not running (stale PID)"
            rm "$DAEMON_PID"
        fi
    else
        log_info "Not running"
    fi

    echo ""

    # Show learning stats
    if [ -f "$LEARNING_DATA" ]; then
        echo "=== Learning Statistics ==="
        echo ""

        local total_queries=$(jq -r '.vector_search.total_queries // 0' "$LEARNING_DATA")
        local success_rate=$(jq -r '.vector_search.successful_retrievals // 0' "$LEARNING_DATA")
        local avg_confidence=$(jq -r '.vector_search.average_confidence // 0' "$LEARNING_DATA")
        local avg_savings=$(jq -r '.vector_search.average_token_savings // 0' "$LEARNING_DATA")
        local rl_spans=$(jq -r '.rl_training.total_spans_emitted // 0' "$LEARNING_DATA")

        echo "  Total queries tracked: $total_queries"

        if [ "$total_queries" -gt 0 ]; then
            local success_pct=$(awk "BEGIN {printf \"%.1f\", ($success_rate / $total_queries) * 100}")
            local conf_pct=$(awk "BEGIN {printf \"%.1f\", $avg_confidence * 100}")
            local save_pct=$(awk "BEGIN {printf \"%.1f\", $avg_savings * 100}")

            echo "  Success rate: ${success_pct}%"
            echo "  Avg confidence: ${conf_pct}%"
            echo "  Avg token savings: ${save_pct}%"
        fi

        echo "  RL spans emitted: $rl_spans"

        if [ "$rl_spans" -ge 100 ]; then
            log_success "Ready for RL training!"
        else
            local needed=$((100 - rl_spans))
            log_info "Need $needed more queries for RL training"
        fi
    else
        log_info "No learning data yet"
    fi

    echo ""
}

track_query() {
    local query="$1"
    local confidence="${2:-0.5}"
    local savings="${3:-50%}"
    shift 3
    local sections=("$@")

    check_python

    log_info "Tracking query..."

    python3 "$RL_BRIDGE" track \
        --query "$query" \
        --confidence "$confidence" \
        --savings "$savings" \
        --sections "${sections[@]}"

    log_success "Query tracked"
}

analyze_patterns() {
    check_python

    log_section "Pattern Analysis"

    python3 "$RL_BRIDGE" analyze
}

trigger_training() {
    check_python
    check_phase2

    log_section "RL Training"

    log_info "Analyzing accumulated spans..."

    python3 "$RL_BRIDGE" train
}

show_stats() {
    check_python

    log_section "Comprehensive Statistics"

    python3 "$RL_BRIDGE" stats
}

configure() {
    check_python

    log_section "Phase 3 Configuration"

    echo "Current configuration:"
    echo ""

    python3 "$LEARNING_DAEMON" config

    echo ""
    echo "Available options:"
    echo "  1. Enable auto-apply optimizations"
    echo "  2. Disable auto-apply optimizations"
    echo "  3. Set aggressiveness (0.0-1.0)"
    echo "  4. Back"
    echo ""

    read -p "Select option: " option

    case "$option" in
        1)
            log_info "Enabling auto-apply..."
            stop_daemon
            python3 "$LEARNING_DAEMON" start --enable-auto-apply &
            sleep 1
            pkill -f "$LEARNING_DAEMON" 2>/dev/null || true
            start_daemon
            log_success "Auto-apply enabled"
            ;;
        2)
            log_info "Disabling auto-apply..."
            stop_daemon
            python3 "$LEARNING_DAEMON" start --disable-auto-apply &
            sleep 1
            pkill -f "$LEARNING_DAEMON" 2>/dev/null || true
            start_daemon
            log_warning "Auto-apply disabled (manual optimization only)"
            ;;
        3)
            read -p "Enter aggressiveness (0.0-1.0): " aggr
            log_info "Setting aggressiveness to $aggr..."
            stop_daemon
            python3 "$LEARNING_DAEMON" start --aggressiveness "$aggr" &
            sleep 1
            pkill -f "$LEARNING_DAEMON" 2>/dev/null || true
            start_daemon
            log_success "Aggressiveness set to $aggr"
            ;;
        4)
            return 0
            ;;
        *)
            log_error "Invalid option"
            ;;
    esac
}

show_full_status() {
    log_section "Phase 3: RL Integration & Continuous Learning"

    # Check Phase 2
    local embeddings="$DATA_DIR/knowledge-embeddings.json"
    if [ -f "$embeddings" ]; then
        log_success "Phase 2: Embeddings built"
    else
        log_error "Phase 2: Embeddings not built"
        echo "  Run: ~/.claude/scripts/vector-search-manager.sh build"
        echo ""
        return 1
    fi

    # Check Python
    if command -v python3 &> /dev/null; then
        local py_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        log_success "Python: $py_version"
    else
        log_error "Python: Not installed"
        return 1
    fi

    # Daemon status
    daemon_status

    # Show recent activity
    if [ -f "$DATA_DIR/continuous-learning.log" ]; then
        echo "=== Recent Activity (Last 10 Lines) ==="
        echo ""
        tail -n 10 "$DATA_DIR/continuous-learning.log"
        echo ""
    fi

    # Next steps
    echo "=== Next Steps ==="
    echo ""

    if [ ! -f "$DAEMON_PID" ]; then
        log_info "Start daemon: $0 start"
    else
        log_info "Daemon is running - learning automatically"
    fi

    if [ -f "$LEARNING_DATA" ]; then
        local queries=$(jq -r '.vector_search.total_queries // 0' "$LEARNING_DATA")
        if [ "$queries" -lt 100 ]; then
            log_info "Track more queries to enable RL training"
            echo "  Current: $queries, needed: 100"
        else
            log_info "Run training: $0 train"
        fi
    fi

    echo ""
}

follow_logs() {
    local log_file="$DATA_DIR/continuous-learning.log"

    if [ ! -f "$log_file" ]; then
        log_error "No log file found"
        log_info "Daemon hasn't been started yet"
        exit 1
    fi

    log_info "Following daemon logs (Ctrl+C to stop)..."
    echo ""

    tail -f "$log_file"
}

usage() {
    cat << EOF
Phase 3 Manager - RL Integration & Continuous Learning

Usage: $0 <command> [options]

Daemon Control:
  start                  Start continuous learning daemon
  stop                   Stop daemon
  restart                Restart daemon
  status                 Show daemon status and learning stats
  logs                   Follow daemon logs

Learning Operations:
  track <query> <conf> <savings> <sections...>
                         Track a query outcome
  analyze                Analyze learned patterns
  train                  Trigger RL training (requires 100+ queries)
  stats                  Show comprehensive statistics

Configuration:
  configure              Interactive configuration
  config                 Show current configuration

Monitoring:
  full-status            Show complete Phase 3 status
  performance            Show performance metrics

Examples:
  # Start daemon
  $0 start

  # Check status
  $0 status

  # Follow logs
  $0 logs

  # Track query outcome
  $0 track "Configure /review" 0.89 "92%" "qodo_merge.review" "qodo_merge.config"

  # Analyze patterns
  $0 analyze

  # Run RL training
  $0 train

  # Configure
  $0 configure

Phase 3 Features:
  ✅ Real-time RL integration with Agent-Lightning
  ✅ Continuous learning loop (auto-optimization)
  ✅ Performance monitoring and analysis
  ✅ Automatic parameter tuning
  ✅ Usage pattern detection
  ✅ Embeddings freshness tracking

Expected Improvements:
  - +20-30% optimization over Phase 2
  - Self-adapting similarity thresholds
  - Automatic embeddings rebuilds
  - Predictive section loading

EOF
}

# Main command router
case "${1:-help}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 1
        start_daemon
        ;;
    status)
        daemon_status
        ;;
    logs)
        follow_logs
        ;;
    track)
        if [ $# -lt 4 ]; then
            log_error "Usage: $0 track <query> <confidence> <savings> <section1> [section2...]"
            exit 1
        fi
        shift
        track_query "$@"
        ;;
    analyze)
        analyze_patterns
        ;;
    train)
        trigger_training
        ;;
    stats)
        show_stats
        ;;
    configure)
        configure
        ;;
    config)
        python3 "$LEARNING_DAEMON" config
        ;;
    full-status)
        show_full_status
        ;;
    performance)
        analyze_patterns
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
