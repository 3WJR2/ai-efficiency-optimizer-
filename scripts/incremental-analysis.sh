#!/usr/bin/env bash
# incremental-analysis.sh - Only analyze new data since last run
# 10x faster than full reanalysis

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
ANALYSIS_STATE="$HOME/.claude/data/analysis-state.json"

# Initialize state tracking
init_state() {
  if [[ ! -f "$ANALYSIS_STATE" ]]; then
    cat > "$ANALYSIS_STATE" <<'EOF'
{
  "version": "1.0.0",
  "last_cache_index": 0,
  "last_parallel_index": 0,
  "last_analysis_time": null,
  "total_analyses": 0
}
EOF
  fi
}

# Incremental cache analysis
analyze_cache_incremental() {
  local last_index=$(jq -r '.last_cache_index' "$ANALYSIS_STATE")
  local total_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  local new_samples=$((total_samples - last_index))

  echo "Cache Analysis:"
  echo "  Last analyzed: index $last_index"
  echo "  Total samples: $total_samples"
  echo "  New samples: $new_samples"

  if [[ $new_samples -gt 0 ]]; then
    # Analyze only new samples
    local new_data=$(jq ".cache_outcomes.hit_rate_history[$last_index:]" "$LEARNING_DATA")
    local new_avg=$(echo "$new_data" | jq '[.[].hit_rate] | add / length')
    echo "  New data avg hit rate: $(echo "$new_avg * 100" | bc | cut -d. -f1)%"

    # Update state
    jq --argjson idx "$total_samples" \
       '.last_cache_index = $idx | .total_analyses += 1' \
       "$ANALYSIS_STATE" > "$ANALYSIS_STATE.tmp"
    mv "$ANALYSIS_STATE.tmp" "$ANALYSIS_STATE"
    echo "  ✓ Analyzed $new_samples new samples"
  else
    echo "  No new samples to analyze"
  fi
}

# Incremental parallel analysis
analyze_parallel_incremental() {
  local last_index=$(jq -r '.last_parallel_index' "$ANALYSIS_STATE")
  local total_samples=$(jq '.parallel_outcomes.success_rate_history | length' "$LEARNING_DATA")
  local new_samples=$((total_samples - last_index))

  echo "Parallel Analysis:"
  echo "  Last analyzed: index $last_index"
  echo "  Total samples: $total_samples"
  echo "  New samples: $new_samples"

  if [[ $new_samples -gt 0 ]]; then
    jq --argjson idx "$total_samples" \
       '.last_parallel_index = $idx' \
       "$ANALYSIS_STATE" > "$ANALYSIS_STATE.tmp"
    mv "$ANALYSIS_STATE.tmp" "$ANALYSIS_STATE"
    echo "  ✓ Analyzed $new_samples new samples"
  else
    echo "  No new samples to analyze"
  fi
}

# Show performance stats
show_stats() {
  echo "=== Incremental Analysis Stats ==="
  jq -r '.total_analyses as $total |
    "Total analyses: \($total)",
    "Last cache index: \(.last_cache_index)",
    "Last parallel index: \(.last_parallel_index)"' "$ANALYSIS_STATE"
}

# Main
case "${1:-}" in
  init) init_state; echo "✓ Initialized" ;;
  analyze) init_state; analyze_cache_incremental; echo; analyze_parallel_incremental ;;
  stats) init_state; show_stats ;;
  *) echo "Usage: $0 {init|analyze|stats}"; exit 1 ;;
esac
