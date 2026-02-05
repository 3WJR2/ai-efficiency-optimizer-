#!/usr/bin/env bash
# pattern-import-export.sh - Export and import learned patterns across machines
# Allows sharing of learning data and faster bootstrap on new systems

set -euo pipefail

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Export learned patterns to a portable file
export_patterns() {
  local output_file="${1:-}"

  if [[ -z "$output_file" ]]; then
    output_file="$HOME/claude-patterns-$(date +%Y%m%d-%H%M%S).json"
  fi

  echo -e "${BLUE}=== Exporting Learned Patterns ===${NC}"
  echo

  if [[ ! -f "$LEARNING_DATA" ]]; then
    echo -e "${RED}✗ No learning data found${NC}"
    echo "  Run the learning daemon first to collect data"
    return 1
  fi

  # Create export package
  local export_data=$(jq '{
    version: .version,
    exported_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    source_system: {
      hostname: env.HOSTNAME,
      user: env.USER,
      os: env.OSTYPE
    },
    learned_patterns: .learned_patterns,
    cache_outcomes: {
      samples: (.cache_outcomes.hit_rate_history | length),
      avg_hit_rate: (
        if (.cache_outcomes.hit_rate_history | length) > 0 then
          [.cache_outcomes.hit_rate_history[].hit_rate] | add / length
        else 0 end
      ),
      threshold_adjustments: .cache_outcomes.threshold_adjustments
    },
    parallel_outcomes: {
      samples: (.parallel_outcomes.execution_history | length),
      avg_success_rate: (
        if (.parallel_outcomes.success_rate_history | length) > 0 then
          [.parallel_outcomes.success_rate_history[].success_rate] | add / length
        else 0 end
      ),
      concurrent_adjustments: .parallel_outcomes.concurrent_adjustments
    },
    total_learning_cycles: .total_learning_cycles,
    current_configs: {
      cache_threshold: 0,
      max_concurrent: 0
    }
  }' "$LEARNING_DATA")

  # Add current config values
  local cache_threshold=$(jq -r '.similarity_threshold // 0' "$CACHE_CONFIG" 2>/dev/null || echo "0")
  local max_concurrent=$(jq -r '.max_concurrent_processes // 0' "$PARALLEL_CONFIG" 2>/dev/null || echo "0")

  export_data=$(echo "$export_data" | jq \
    --argjson threshold "$cache_threshold" \
    --argjson concurrent "$max_concurrent" \
    '.current_configs.cache_threshold = $threshold |
     .current_configs.max_concurrent = $concurrent')

  # Write to file
  echo "$export_data" | jq '.' > "$output_file"

  echo -e "${GREEN}✓ Export successful${NC}"
  echo
  echo "Export details:"
  echo "  File: $output_file"
  echo "  Size: $(du -h "$output_file" | awk '{print $1}')"
  echo
  echo "Summary:"
  echo "$export_data" | jq -r '
    "  Learning cycles: \(.total_learning_cycles)",
    "  Cache samples: \(.cache_outcomes.samples)",
    "  Parallel samples: \(.parallel_outcomes.samples)",
    "  Optimal cache threshold: \(.learned_patterns.optimal_cache_threshold // "not learned")",
    "  Optimal concurrent: \(.learned_patterns.optimal_concurrent_processes // "not learned")"
  '
  echo
  echo -e "${YELLOW}Share this file to transfer learning to another machine${NC}"
}

# Import learned patterns from file
import_patterns() {
  local import_file="$1"
  local merge_strategy="${2:-conservative}"  # conservative, aggressive, replace

  echo -e "${BLUE}=== Importing Learned Patterns ===${NC}"
  echo

  if [[ ! -f "$import_file" ]]; then
    echo -e "${RED}✗ Import file not found: $import_file${NC}"
    return 1
  fi

  # Validate import file
  if ! validate_import_file "$import_file"; then
    echo -e "${RED}✗ Invalid import file${NC}"
    return 1
  fi

  # Show import summary
  echo "Import file details:"
  jq -r '
    "  Exported: \(.exported_at)",
    "  Source: \(.source_system.hostname // "unknown")",
    "  Learning cycles: \(.total_learning_cycles)",
    "  Cache samples: \(.cache_outcomes.samples)",
    "  Parallel samples: \(.parallel_outcomes.samples)"
  ' "$import_file"
  echo

  # Merge patterns based on strategy
  case "$merge_strategy" in
    conservative)
      import_conservative "$import_file"
      ;;
    aggressive)
      import_aggressive "$import_file"
      ;;
    replace)
      import_replace "$import_file"
      ;;
    *)
      echo -e "${RED}✗ Unknown merge strategy: $merge_strategy${NC}"
      echo "  Valid options: conservative, aggressive, replace"
      return 1
      ;;
  esac
}

# Conservative merge: Only import if better than current
import_conservative() {
  local import_file="$1"

  echo -e "${YELLOW}Merge strategy: Conservative (only import if better)${NC}"
  echo

  local imported_cache_threshold=$(jq -r '.learned_patterns.optimal_cache_threshold // null' "$import_file")
  local imported_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // null' "$import_file")
  local current_cache_threshold=$(jq -r '.learned_patterns.optimal_cache_threshold // null' "$LEARNING_DATA")
  local current_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // null' "$LEARNING_DATA")

  local changes=0

  # Import cache threshold if we don't have one or imported is better
  if [[ "$imported_cache_threshold" != "null" ]]; then
    local imported_samples=$(jq -r '.cache_outcomes.samples' "$import_file")
    local current_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")

    if [[ "$current_cache_threshold" == "null" ]] || [[ $imported_samples -gt $current_samples ]]; then
      jq --argjson threshold "$imported_cache_threshold" \
         '.learned_patterns.optimal_cache_threshold = $threshold' \
         "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
      mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

      echo -e "${GREEN}✓ Imported cache threshold: $imported_cache_threshold${NC}"
      echo "  Reason: $([ "$current_cache_threshold" == "null" ] && echo "No local value" || echo "More samples ($imported_samples > $current_samples)")"
      changes=$((changes + 1))
    else
      echo "○ Skipped cache threshold (local is better)"
    fi
  fi

  # Import concurrent limit if we don't have one or imported is better
  if [[ "$imported_concurrent" != "null" ]]; then
    local imported_samples=$(jq -r '.parallel_outcomes.samples' "$import_file")
    local current_samples=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")

    if [[ "$current_concurrent" == "null" ]] || [[ $imported_samples -gt $current_samples ]]; then
      jq --argjson concurrent "$imported_concurrent" \
         '.learned_patterns.optimal_concurrent_processes = $concurrent' \
         "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
      mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"

      echo -e "${GREEN}✓ Imported concurrent limit: $imported_concurrent${NC}"
      echo "  Reason: $([ "$current_concurrent" == "null" ] && echo "No local value" || echo "More samples ($imported_samples > $current_samples)")"
      changes=$((changes + 1))
    else
      echo "○ Skipped concurrent limit (local is better)"
    fi
  fi

  # Import adjustment history (append)
  local imported_cache_adjustments=$(jq '.cache_outcomes.threshold_adjustments' "$import_file")
  if [[ "$imported_cache_adjustments" != "null" ]] && [[ "$imported_cache_adjustments" != "[]" ]]; then
    jq --argjson adjustments "$imported_cache_adjustments" \
       '.cache_outcomes.threshold_adjustments += $adjustments' \
       "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
    mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"
    echo -e "${GREEN}✓ Merged adjustment history${NC}"
    changes=$((changes + 1))
  fi

  echo
  echo -e "${GREEN}Import complete: $changes changes applied${NC}"
}

# Aggressive merge: Import everything, overwrite local
import_aggressive() {
  local import_file="$1"

  echo -e "${YELLOW}Merge strategy: Aggressive (overwrite local with imported)${NC}"
  echo

  local imported_cache_threshold=$(jq -r '.learned_patterns.optimal_cache_threshold // null' "$import_file")
  local imported_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // null' "$import_file")

  local changes=0

  if [[ "$imported_cache_threshold" != "null" ]]; then
    jq --argjson threshold "$imported_cache_threshold" \
       '.learned_patterns.optimal_cache_threshold = $threshold' \
       "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
    mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"
    echo -e "${GREEN}✓ Imported cache threshold: $imported_cache_threshold${NC}"
    changes=$((changes + 1))
  fi

  if [[ "$imported_concurrent" != "null" ]]; then
    jq --argjson concurrent "$imported_concurrent" \
       '.learned_patterns.optimal_concurrent_processes = $concurrent' \
       "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
    mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"
    echo -e "${GREEN}✓ Imported concurrent limit: $imported_concurrent${NC}"
    changes=$((changes + 1))
  fi

  # Import adjustment history (replace)
  local imported_cache_adjustments=$(jq '.cache_outcomes.threshold_adjustments' "$import_file")
  if [[ "$imported_cache_adjustments" != "null" ]]; then
    jq --argjson adjustments "$imported_cache_adjustments" \
       '.cache_outcomes.threshold_adjustments = $adjustments' \
       "$LEARNING_DATA" > "$LEARNING_DATA.tmp"
    mv "$LEARNING_DATA.tmp" "$LEARNING_DATA"
    echo -e "${GREEN}✓ Replaced adjustment history${NC}"
    changes=$((changes + 1))
  fi

  echo
  echo -e "${GREEN}Import complete: $changes changes applied${NC}"
}

# Replace: Complete replacement of local learning data
import_replace() {
  local import_file="$1"

  echo -e "${RED}Merge strategy: Replace (DESTRUCTIVE - will replace all local learning)${NC}"
  echo

  # Backup current data
  local backup_file="$LEARNING_DATA.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$LEARNING_DATA" "$backup_file"
  echo -e "${YELLOW}✓ Backed up current data to: $backup_file${NC}"
  echo

  # Extract and apply learned patterns
  jq '{
    version: .version,
    initialized_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
    cache_outcomes: {
      hit_rate_history: [],
      similarity_score_history: [],
      latency_history: [],
      threshold_adjustments: .cache_outcomes.threshold_adjustments
    },
    parallel_outcomes: {
      execution_history: [],
      success_rate_history: [],
      parallelism_history: [],
      concurrent_adjustments: .parallel_outcomes.concurrent_adjustments
    },
    learned_patterns: .learned_patterns,
    adaptation_log: [],
    last_analysis: null,
    total_learning_cycles: 0
  }' "$import_file" > "$LEARNING_DATA"

  echo -e "${GREEN}✓ Replaced learning data${NC}"
  echo -e "${YELLOW}Note: Only learned patterns imported, fresh data collection will start${NC}"
}

# Validate import file structure
validate_import_file() {
  local import_file="$1"

  # Check if valid JSON
  if ! jq empty "$import_file" 2>/dev/null; then
    echo "  Invalid JSON format"
    return 1
  fi

  # Check required fields
  local has_version=$(jq -e '.version' "$import_file" >/dev/null 2>&1 && echo "yes" || echo "no")
  local has_patterns=$(jq -e '.learned_patterns' "$import_file" >/dev/null 2>&1 && echo "yes" || echo "no")
  local has_cache=$(jq -e '.cache_outcomes' "$import_file" >/dev/null 2>&1 && echo "yes" || echo "no")

  if [[ "$has_version" == "no" ]] || [[ "$has_patterns" == "no" ]] || [[ "$has_cache" == "no" ]]; then
    echo "  Missing required fields"
    return 1
  fi

  return 0
}

# Show comparison between local and imported patterns
compare_patterns() {
  local import_file="$1"

  echo -e "${BLUE}=== Pattern Comparison ===${NC}"
  echo

  if [[ ! -f "$import_file" ]]; then
    echo -e "${RED}✗ Import file not found: $import_file${NC}"
    return 1
  fi

  echo "Local vs Imported:"
  echo

  # Cache threshold comparison
  local local_cache=$(jq -r '.learned_patterns.optimal_cache_threshold // "not learned"' "$LEARNING_DATA")
  local import_cache=$(jq -r '.learned_patterns.optimal_cache_threshold // "not learned"' "$import_file")
  local local_cache_samples=$(jq '.cache_outcomes.hit_rate_history | length' "$LEARNING_DATA")
  local import_cache_samples=$(jq -r '.cache_outcomes.samples' "$import_file")

  echo "Cache Threshold:"
  echo "  Local:    $local_cache (from $local_cache_samples samples)"
  echo "  Imported: $import_cache (from $import_cache_samples samples)"
  if [[ "$local_cache" != "$import_cache" ]]; then
    echo -e "  ${YELLOW}⚠ Different values${NC}"
  else
    echo -e "  ${GREEN}✓ Same value${NC}"
  fi
  echo

  # Concurrent limit comparison
  local local_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // "not learned"' "$LEARNING_DATA")
  local import_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // "not learned"' "$import_file")
  local local_parallel_samples=$(jq '.parallel_outcomes.execution_history | length' "$LEARNING_DATA")
  local import_parallel_samples=$(jq -r '.parallel_outcomes.samples' "$import_file")

  echo "Concurrent Processes:"
  echo "  Local:    $local_concurrent (from $local_parallel_samples samples)"
  echo "  Imported: $import_concurrent (from $import_parallel_samples samples)"
  if [[ "$local_concurrent" != "$import_concurrent" ]]; then
    echo -e "  ${YELLOW}⚠ Different values${NC}"
  else
    echo -e "  ${GREEN}✓ Same value${NC}"
  fi
  echo

  # Learning cycles comparison
  local local_cycles=$(jq -r '.total_learning_cycles' "$LEARNING_DATA")
  local import_cycles=$(jq -r '.total_learning_cycles' "$import_file")

  echo "Learning Experience:"
  echo "  Local:    $local_cycles cycles"
  echo "  Imported: $import_cycles cycles"
  echo
}

# Apply imported patterns to live configs
apply_imported_patterns() {
  echo -e "${BLUE}=== Applying Imported Patterns to Live Configs ===${NC}"
  echo

  local optimal_cache=$(jq -r '.learned_patterns.optimal_cache_threshold // null' "$LEARNING_DATA")
  local optimal_concurrent=$(jq -r '.learned_patterns.optimal_concurrent_processes // null' "$LEARNING_DATA")

  local changes=0

  if [[ "$optimal_cache" != "null" ]]; then
    jq --argjson threshold "$optimal_cache" \
       '.similarity_threshold = $threshold' \
       "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
    mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"
    echo -e "${GREEN}✓ Applied cache threshold: $optimal_cache${NC}"
    changes=$((changes + 1))
  fi

  if [[ "$optimal_concurrent" != "null" ]]; then
    jq --argjson concurrent "$optimal_concurrent" \
       '.max_concurrent_processes = $concurrent' \
       "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
    mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"
    echo -e "${GREEN}✓ Applied concurrent limit: $optimal_concurrent${NC}"
    changes=$((changes + 1))
  fi

  echo
  if [[ $changes -gt 0 ]]; then
    echo -e "${GREEN}Applied $changes configuration changes${NC}"
    echo -e "${YELLOW}Restart the learning daemon to use new configs${NC}"
  else
    echo "No patterns to apply"
  fi
}

# Main command dispatcher
case "${1:-}" in
  export)
    export_patterns "${2:-}"
    ;;
  import)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 import <file> [strategy]"
      echo "  strategy: conservative (default), aggressive, replace"
      exit 1
    fi
    import_patterns "$2" "${3:-conservative}"
    ;;
  compare)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: $0 compare <file>"
      exit 1
    fi
    compare_patterns "$2"
    ;;
  apply)
    apply_imported_patterns
    ;;
  *)
    echo "Usage: $0 {export|import|compare|apply} [args]"
    echo
    echo "Commands:"
    echo "  export [file]              - Export learned patterns to file"
    echo "  import <file> [strategy]   - Import patterns from file"
    echo "    strategy: conservative (default), aggressive, replace"
    echo "  compare <file>             - Compare local vs imported patterns"
    echo "  apply                      - Apply imported patterns to live configs"
    echo
    echo "Examples:"
    echo "  $0 export                          # Export to default file"
    echo "  $0 export ~/patterns.json          # Export to specific file"
    echo "  $0 compare ~/patterns.json         # Compare before importing"
    echo "  $0 import ~/patterns.json          # Conservative merge"
    echo "  $0 import ~/patterns.json aggressive  # Overwrite local"
    echo "  $0 apply                           # Apply to live configs"
    exit 1
    ;;
esac
