#!/usr/bin/env bash
# performance-profiling.sh - Detailed performance breakdown
# Track where time is spent in the system

set -euo pipefail

PROFILE_DATA="$HOME/.claude/data/performance-profile.json"

# Initialize profiling
init_profiling() {
  if [[ ! -f "$PROFILE_DATA" ]]; then
    cat > "$PROFILE_DATA" <<'EOF'
{
  "version": "1.0.0",
  "cache_operations": {
    "embedding_generation_ms": [],
    "redis_lookup_ms": [],
    "similarity_calculation_ms": [],
    "total_operation_ms": []
  },
  "parallel_operations": {
    "task_spawn_ms": [],
    "queue_lock_ms": [],
    "dependency_resolution_ms": [],
    "total_execution_ms": []
  },
  "enabled": true
}
EOF
  fi
}

# Profile cache operation
profile_cache() {
  local operation="$1"
  local duration_ms="$2"

  jq --argjson duration "$duration_ms" \
     ".cache_operations.${operation}_ms += [\$duration] | 
      .cache_operations.${operation}_ms = .cache_operations.${operation}_ms[-100:]" \
     "$PROFILE_DATA" > "$PROFILE_DATA.tmp"
  mv "$PROFILE_DATA.tmp" "$PROFILE_DATA"
}

# Show cache profiling
show_cache_profile() {
  echo "=== Cache Performance Profile ==="
  echo

  python3 <<'EOF'
import json
from statistics import mean

with open('/Users/wallonwalusayi/.claude/data/performance-profile.json') as f:
    data = json.load(f)

cache = data['cache_operations']
for op, times in cache.items():
    if times:
        avg_time = mean(times)
        min_time = min(times)
        max_time = max(times)
        print(f"{op.replace('_', ' ').title()}:")
        print(f"  Avg: {avg_time:.2f}ms")
        print(f"  Min: {min_time:.2f}ms")
        print(f"  Max: {max_time:.2f}ms")
        print(f"  Samples: {len(times)}")
        print()
EOF
}

# Show parallel profiling
show_parallel_profile() {
  echo "=== Parallel Execution Performance Profile ==="
  echo

  python3 <<'EOF'
import json
from statistics import mean

with open('/Users/wallonwalusayi/.claude/data/performance-profile.json') as f:
    data = json.load(f)

parallel = data['parallel_operations']
for op, times in parallel.items():
    if times:
        avg_time = mean(times)
        print(f"{op.replace('_', ' ').title()}: {avg_time:.2f}ms avg ({len(times)} samples)")
EOF
}

# Show breakdown
show_breakdown() {
  echo "=== Performance Breakdown ===" 
  echo
  show_cache_profile
  show_parallel_profile
}

# Main
case "${1:-}" in
  init) init_profiling; echo "✓ Profiling initialized" ;;
  profile-cache) profile_cache "$2" "$3" ;;
  show) init_profiling; show_breakdown ;;
  cache) init_profiling; show_cache_profile ;;
  parallel) init_profiling; show_parallel_profile ;;
  *) echo "Usage: $0 {init|profile-cache|show|cache|parallel}"; exit 1 ;;
esac
