#!/usr/bin/env bash
################################################################################
# Dashboard - Phase C: Real Metrics & Effectiveness Reporting
# Interactive terminal dashboard showing real-time metrics
################################################################################

set -euo pipefail

# Directories
CLAUDE_DIR="$HOME/.claude"
DATA_DIR="$CLAUDE_DIR/data"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
METRICS_FILE="$DATA_DIR/metrics.json"
EFFECTIVENESS_FILE="$DATA_DIR/effectiveness.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# State
REFRESH_INTERVAL=10
AUTO_REFRESH=true
SHOW_MODE="overview" # overview, cache, parallel, learning, roi

# Initialize metrics if needed
init_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    echo "Initializing metrics..."
    "$SCRIPTS_DIR/metrics-collector.sh" collect >/dev/null 2>&1 || true
  fi
}

# Show header
show_header() {
  clear
  echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║${NC}        ${BOLD}Claude Adaptive Intelligence - Phase C Dashboard${NC}                 ${BOLD}${CYAN}║${NC}"
  echo -e "${BOLD}${CYAN}║${NC}        ${BOLD}Real Metrics & Effectiveness Reporting${NC}                          ${BOLD}${CYAN}║${NC}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BOLD}Last Updated:${NC} $(date '+%Y-%m-%d %H:%M:%S')    ${BOLD}Mode:${NC} $SHOW_MODE    ${BOLD}Auto-refresh:${NC} $AUTO_REFRESH (${REFRESH_INTERVAL}s)"
  echo ""
}

# Draw progress bar
draw_bar() {
  local pct=$1
  local width=${2:-30}
  local filled=$((pct * width / 100))
  local empty=$((width - filled))

  printf "["
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
  printf "] %3d%%" "$pct"
}

# Show system health
show_system_health() {
  if [[ ! -f "$METRICS_FILE" ]]; then
    echo -e "${YELLOW}⚠ No metrics data${NC}"
    return
  fi

  local overall=$(jq -r '.system_health.overall_status' "$METRICS_FILE")
  local status_icon="●"

  case "$overall" in
    healthy) status_icon="${GREEN}✓${NC}" ;;
    degraded) status_icon="${YELLOW}⚠${NC}" ;;
    critical) status_icon="${RED}✗${NC}" ;;
  esac

  echo -e "${BOLD}┌─ System Health ──────────────────────────────────────────────────────────┐${NC}"
  echo -e "│ Overall: $status_icon $(printf '%-60s' "$overall" | tr '[:lower:]' '[:upper:]') │"
  echo -e "${BOLD}├──────────────────────────────────────────────────────────────────────────┤${NC}"

  printf "│ %-25s " "  Cache System:"
  local cache_status=$(jq -r '.system_health.components.cache_system' "$METRICS_FILE")
  case "$cache_status" in
    healthy) echo -e "${GREEN}✓ healthy${NC}                                     │" ;;
    *) echo -e "${YELLOW}⚠ $cache_status${NC}$(printf '%*s' $((48 - ${#cache_status})) '') │" ;;
  esac

  printf "│ %-25s " "  Parallel Execution:"
  local parallel_status=$(jq -r '.system_health.components.parallel_execution' "$METRICS_FILE")
  case "$parallel_status" in
    healthy) echo -e "${GREEN}✓ healthy${NC}                                     │" ;;
    *) echo -e "${YELLOW}⚠ $parallel_status${NC}$(printf '%*s' $((48 - ${#parallel_status})) '') │" ;;
  esac

  printf "│ %-25s " "  Learning System:"
  local learning_status=$(jq -r '.system_health.components.learning_system' "$METRICS_FILE")
  case "$learning_status" in
    healthy) echo -e "${GREEN}✓ healthy${NC}                                     │" ;;
    *) echo -e "${YELLOW}⚠ $learning_status${NC}$(printf '%*s' $((48 - ${#learning_status})) '') │" ;;
  esac

  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show cache metrics
show_cache_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then return; fi

  local status=$(jq -r '.cache_metrics.current.status' "$METRICS_FILE")
  if [[ "$status" != "active" ]]; then
    echo -e "${BOLD}Cache System:${NC} ${YELLOW}$status${NC}"
    echo ""
    return
  fi

  local requests=$(jq -r '.cache_metrics.current.combined.total_requests' "$METRICS_FILE")
  local hits=$(jq -r '.cache_metrics.current.combined.total_hits' "$METRICS_FILE")
  local hit_rate=$(jq -r '.cache_metrics.current.combined.hit_rate' "$METRICS_FILE")
  local cost_saved=$(jq -r '.cache_metrics.current.combined.total_cost_saved_usd' "$METRICS_FILE")
  local latency_reduction=$(jq -r '.cache_metrics.current.performance.latency_reduction_pct' "$METRICS_FILE")

  local hit_rate_pct=$(echo "$hit_rate * 100" | bc | cut -d. -f1)
  local latency_pct=$(echo "$latency_reduction" | cut -d. -f1)

  echo -e "${BOLD}┌─ Cache System (✅ Real Metrics) ─────────────────────────────────────────┐${NC}"
  printf "│ %-30s %40s │\n" "  Requests:" "$requests"
  printf "│ %-30s %40s │\n" "  Hits:" "$hits"
  printf "│ %-30s " "  Hit Rate:"
  echo "$(draw_bar "$hit_rate_pct" 25) │"
  printf "│ %-30s %40s │\n" "  Cost Saved:" "\$$cost_saved"
  printf "│ %-30s %40s │\n" "  Latency Reduction:" "$latency_pct%"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show parallel metrics
show_parallel_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then return; fi

  local status=$(jq -r '.parallel_metrics.current.status' "$METRICS_FILE")
  if [[ "$status" != "active" ]]; then
    echo -e "${BOLD}Parallel Execution:${NC} ${YELLOW}$status${NC}"
    echo ""
    return
  fi

  local executions=$(jq -r '.parallel_metrics.current.executions' "$METRICS_FILE")
  local speedup=$(jq -r '.parallel_metrics.current.speedup_factor' "$METRICS_FILE")
  local success_rate=$(jq -r '.parallel_metrics.current.success_rate_pct' "$METRICS_FILE")
  local time_saved=$(jq -r '.parallel_metrics.current.time_saved_ms' "$METRICS_FILE")

  local success_pct=$(echo "$success_rate" | cut -d. -f1)

  echo -e "${BOLD}┌─ Parallel Execution (✅ Real Metrics) ───────────────────────────────────┐${NC}"
  printf "│ %-30s %40s │\n" "  Executions:" "$executions"
  printf "│ %-30s %40s │\n" "  Speedup Factor:" "${speedup}x"
  printf "│ %-30s " "  Success Rate:"
  echo "$(draw_bar "$success_pct" 25) │"
  printf "│ %-30s %40s │\n" "  Time Saved:" "$time_saved ms"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show learning metrics
show_learning_metrics() {
  if [[ ! -f "$METRICS_FILE" ]]; then return; fi

  local status=$(jq -r '.learning_metrics.current.status' "$METRICS_FILE")
  if [[ "$status" != "active" ]]; then
    echo -e "${BOLD}Learning System:${NC} ${YELLOW}$status${NC}"
    echo ""
    return
  fi

  local cache_samples=$(jq -r '.learning_metrics.current.samples.cache_outcomes' "$METRICS_FILE")
  local parallel_samples=$(jq -r '.learning_metrics.current.samples.parallel_outcomes' "$METRICS_FILE")
  local adaptations=$(jq -r '.learning_metrics.current.adaptations.total_count' "$METRICS_FILE")
  local confidence=$(jq -r '.learning_metrics.current.learned_patterns.confidence' "$METRICS_FILE")

  local confidence_pct=$(echo "$confidence * 100" | bc | cut -d. -f1)

  echo -e "${BOLD}┌─ Learning System (✅ Real Metrics) ──────────────────────────────────────┐${NC}"
  printf "│ %-30s %40s │\n" "  Cache Samples:" "$cache_samples"
  printf "│ %-30s %40s │\n" "  Parallel Samples:" "$parallel_samples"
  printf "│ %-30s %40s │\n" "  Total Adaptations:" "$adaptations"
  printf "│ %-30s " "  Confidence:"
  echo "$(draw_bar "$confidence_pct" 25) │"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show ROI summary
show_roi() {
  if [[ ! -f "$EFFECTIVENESS_FILE" ]]; then
    echo -e "${BOLD}ROI Summary:${NC} ${YELLOW}No data yet${NC}"
    echo ""
    return
  fi

  local total=$(jq -r '.roi_metrics.total_adaptations' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")
  local successful=$(jq -r '.roi_metrics.successful_adaptations' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")
  local avg_improvement=$(jq -r '.roi_metrics.avg_improvement_pct' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")
  local cost_saved=$(jq -r '.roi_metrics.total_cost_savings_usd' "$EFFECTIVENESS_FILE" 2>/dev/null || echo "0")

  local success_pct=0
  if [[ $total -gt 0 ]]; then
    success_pct=$(echo "scale=0; $successful * 100 / $total" | bc)
  fi

  echo -e "${BOLD}┌─ ROI Summary (✅ Real Metrics) ──────────────────────────────────────────┐${NC}"
  printf "│ %-30s %40s │\n" "  Total Adaptations:" "$total"
  printf "│ %-30s %40s │\n" "  Successful:" "$successful"
  printf "│ %-30s " "  Success Rate:"
  if [[ $total -gt 0 ]]; then
    echo "$(draw_bar "$success_pct" 25) │"
  else
    echo "N/A                              │"
  fi
  printf "│ %-30s %40s │\n" "  Avg Improvement:" "$avg_improvement%"
  printf "│ %-30s %40s │\n" "  Total Cost Saved:" "\$$cost_saved"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show data quality indicators
show_data_quality() {
  echo -e "${BOLD}┌─ Data Quality Indicators ────────────────────────────────────────────────┐${NC}"
  echo -e "│ ${GREEN}✅ Real:${NC} Cache hit rates, latency, cost savings                         │"
  echo -e "│ ${GREEN}✅ Real:${NC} Parallel speedup, execution times                              │"
  echo -e "│ ${GREEN}✅ Real:${NC} Learning samples, adaptation counts                            │"
  echo -e "│ ${YELLOW}⚠ Limited:${NC} Session quality (needs user feedback)                        │"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Show quick actions
show_actions() {
  echo -e "${BOLD}┌─ Quick Actions ──────────────────────────────────────────────────────────┐${NC}"
  echo -e "│ ${BOLD}[c]${NC} Collect Metrics   ${BOLD}[r]${NC} Daily Report    ${BOLD}[w]${NC} Weekly Report   ${BOLD}[e]${NC} Effectiveness │"
  echo -e "│ ${BOLD}[t]${NC} Show Trends       ${BOLD}[a]${NC} Adaptations     ${BOLD}[p]${NC} Pause/Resume    ${BOLD}[q]${NC} Quit         │"
  echo -e "${BOLD}└──────────────────────────────────────────────────────────────────────────┘${NC}"
}

# Main display
display_dashboard() {
  show_header
  show_system_health
  show_cache_metrics
  show_parallel_metrics
  show_learning_metrics
  show_roi
  show_data_quality
  show_actions
}

# Handle input
handle_input() {
  if read -t 1 -n 1 key 2>/dev/null; then
    case "$key" in
      c|C)
        echo ""
        echo "Collecting metrics..."
        "$SCRIPTS_DIR/metrics-collector.sh" collect
        sleep 2
        ;;
      r|R)
        echo ""
        echo "Generating daily report..."
        "$SCRIPTS_DIR/report-generator.sh" daily
        echo "Report saved to ~/.claude/reports/"
        sleep 2
        ;;
      w|W)
        echo ""
        echo "Generating weekly report..."
        "$SCRIPTS_DIR/report-generator.sh" weekly
        echo "Report saved to ~/.claude/reports/"
        sleep 2
        ;;
      e|E)
        echo ""
        echo "Generating effectiveness report..."
        "$SCRIPTS_DIR/report-generator.sh" learning
        echo "Report saved to ~/.claude/reports/"
        sleep 2
        ;;
      t|T)
        clear
        echo "=== Quality Trends ==="
        "$SCRIPTS_DIR/effectiveness-tracker.sh" trends 2>/dev/null || echo "No trend data yet"
        echo ""
        echo "Press any key to return..."
        read -n 1
        ;;
      a|A)
        clear
        echo "=== Recent Adaptations ==="
        "$SCRIPTS_DIR/effectiveness-tracker.sh" adaptations 10 2>/dev/null || echo "No adaptations yet"
        echo ""
        echo "Press any key to return..."
        read -n 1
        ;;
      p|P)
        if [[ "$AUTO_REFRESH" == "true" ]]; then
          AUTO_REFRESH=false
          echo ""
          echo "Auto-refresh paused"
          sleep 1
        else
          AUTO_REFRESH=true
          echo ""
          echo "Auto-refresh resumed"
          sleep 1
        fi
        ;;
      q|Q)
        clear
        echo "Dashboard stopped."
        exit 0
        ;;
    esac
  fi
}

# Main loop
main() {
  init_metrics

  trap 'clear; echo "Dashboard stopped."; exit 0' INT TERM

  while true; do
    display_dashboard

    if [[ "$AUTO_REFRESH" == "true" ]]; then
      for ((i=0; i<REFRESH_INTERVAL; i++)); do
        handle_input
      done
      "$SCRIPTS_DIR/metrics-collector.sh" collect >/dev/null 2>&1 || true
    else
      handle_input
    fi
  done
}

main "$@"
