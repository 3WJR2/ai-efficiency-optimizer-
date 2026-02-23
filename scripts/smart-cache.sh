#!/usr/bin/env bash
# smart-cache.sh - Context-aware caching with recency, success rate, complexity
# Goes beyond simple similarity threshold
# Part of Phase 3B - High Impact Improvements

set -euo pipefail

SMART_CACHE_DATA="$HOME/.claude/data/smart-cache-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
LEARNING_DATA="$HOME/.claude/data/learning-data.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize smart cache data
initialize_smart_cache() {
  if [[ ! -f "$SMART_CACHE_DATA" ]]; then
    cat > "$SMART_CACHE_DATA" <<'EOF'
{
  "version": "1.0.0",
  "enabled": true,
  "weights": {
    "similarity": 0.5,
    "recency": 0.2,
    "success_rate": 0.2,
    "complexity": 0.1
  },
  "recency_decay_hours": 24,
  "min_similarity_threshold": 0.70,
  "complexity_analysis_enabled": true,
  "cache_entries": {},
  "access_history": [],
  "performance_metrics": {
    "smart_hits": 0,
    "smart_misses": 0,
    "traditional_hits": 0,
    "traditional_misses": 0
  }
}
EOF
  fi
}

# Calculate smart cache score
calculate_smart_score() {
  local query_hash="$1"
  local candidate_hash="$2"
  local similarity="$3"

  echo -e "${BLUE}Calculating smart cache score...${NC}"

  # Get cache entry data
  local entry=$(jq --arg hash "$candidate_hash" '.cache_entries[$hash] // {}' "$SMART_CACHE_DATA")

  if [[ "$entry" == "{}" ]]; then
    echo "0"
    return 0
  fi

  # Calculate score using Python
  local score=$(python3 <<PYEOF
import json
import time
from datetime import datetime, timezone

entry = json.loads('$entry')
similarity = $similarity

with open('/Users/wallonwalusayi/.claude/data/smart-cache-data.json') as f:
    config = json.load(f)

weights = config['weights']
recency_decay = config['recency_decay_hours']

# 1. Similarity score (already provided)
sim_score = similarity

# 2. Recency score (exponential decay)
last_accessed = entry.get('last_accessed')
if last_accessed:
    last_time = datetime.fromisoformat(last_accessed.replace('Z', '+00:00'))
    hours_ago = (datetime.now(timezone.utc) - last_time).total_seconds() / 3600
    recency_score = max(0, 1.0 - (hours_ago / recency_decay))
else:
    recency_score = 0.5

# 3. Success rate score
success_count = entry.get('success_count', 0)
total_accesses = entry.get('access_count', 1)
success_rate_score = success_count / total_accesses if total_accesses > 0 else 0.5

# 4. Complexity score (simpler queries cache better)
complexity = entry.get('complexity_score', 0.5)
complexity_score = 1.0 - complexity  # Invert: simpler is better

# Weighted composite score
smart_score = (
    weights['similarity'] * sim_score +
    weights['recency'] * recency_score +
    weights['success_rate'] * success_rate_score +
    weights['complexity'] * complexity_score
)

print(json.dumps({
    'smart_score': smart_score,
    'components': {
        'similarity': sim_score,
        'recency': recency_score,
        'success_rate': success_rate_score,
        'complexity': complexity_score
    }
}))
PYEOF
)

  local smart_score_val=$(echo "$score" | jq -r '.smart_score')

  echo "  Smart score: $(echo "$smart_score_val * 100" | bc | cut -d. -f1)%"
  echo "  Components:"
  echo "$score" | jq -r '.components | to_entries[] | "    \(.key): \(.value | . * 100 | floor)%"'

  echo "$smart_score_val"
}

# Should use cache based on smart scoring
should_use_cache() {
  local query_hash="$1"
  local candidate_hash="$2"
  local similarity="$3"

  local enabled=$(jq -r '.enabled' "$SMART_CACHE_DATA")

  if [[ "$enabled" != "true" ]]; then
    # Fall back to traditional threshold
    local threshold=$(jq -r '.similarity_threshold' "$CACHE_CONFIG")
    if [[ $(echo "$similarity >= $threshold" | bc -l) -eq 1 ]]; then
      echo "true"
    else
      echo "false"
    fi
    return 0
  fi

  # Calculate smart score
  local smart_score=$(calculate_smart_score "$query_hash" "$candidate_hash" "$similarity")

  # Check against minimum threshold
  local min_threshold=$(jq -r '.min_similarity_threshold' "$SMART_CACHE_DATA")

  if [[ $(echo "$smart_score >= $min_threshold" | bc -l) -eq 1 ]]; then
    echo "true"
    # Update metrics
    jq '.performance_metrics.smart_hits += 1' "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
    mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
  else
    echo "false"
    # Update metrics
    jq '.performance_metrics.smart_misses += 1' "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
    mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
  fi
}

# Register cache entry
register_entry() {
  local query_hash="$1"
  local query_text="$2"
  local response_hash="$3"

  echo -e "${BLUE}Registering cache entry...${NC}"

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Calculate query complexity
  local complexity=$(python3 <<PYEOF
import json

query = '''$query_text'''

# Simple complexity heuristics
length_score = min(1.0, len(query) / 500.0)  # Longer = more complex
word_count = len(query.split())
word_score = min(1.0, word_count / 100.0)

# Special characters (code indicators)
special_chars = sum(1 for c in query if c in '{}[]()<>:;,.')
special_score = min(1.0, special_chars / 50.0)

# Average complexity
complexity = (length_score + word_score + special_score) / 3.0

print(complexity)
PYEOF
)

  # Check if entry exists
  local exists=$(jq --arg hash "$query_hash" '.cache_entries | has($hash)' "$SMART_CACHE_DATA")

  if [[ "$exists" == "true" ]]; then
    # Update existing entry
    jq --arg hash "$query_hash" \
       --arg ts "$now" \
       '.cache_entries[$hash].access_count += 1 |
        .cache_entries[$hash].last_accessed = $ts' \
       "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
    mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
    echo -e "${GREEN}✓ Updated existing entry${NC}"
  else
    # Create new entry
    jq --arg hash "$query_hash" \
       --arg response "$response_hash" \
       --arg ts "$now" \
       --argjson complexity "$complexity" \
       '.cache_entries[$hash] = {
         response_hash: $response,
         created_at: $ts,
         last_accessed: $ts,
         access_count: 1,
         success_count: 1,
         complexity_score: $complexity
       }' \
       "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
    mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
    echo -e "${GREEN}✓ Created new entry${NC}"
  fi

  echo "  Complexity: $(echo "$complexity * 100" | bc | cut -d. -f1)%"
}

# Record cache hit success/failure
record_feedback() {
  local query_hash="$1"
  local success="$2"  # true/false

  echo -e "${BLUE}Recording feedback for: $query_hash${NC}"

  local exists=$(jq --arg hash "$query_hash" '.cache_entries | has($hash)' "$SMART_CACHE_DATA")

  if [[ "$exists" != "true" ]]; then
    echo "Entry not found"
    return 1
  fi

  if [[ "$success" == "true" ]]; then
    jq --arg hash "$query_hash" \
       '.cache_entries[$hash].success_count += 1' \
       "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
    mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
    echo -e "${GREEN}✓ Success recorded${NC}"
  else
    # Failure: access count already incremented, just update access time
    echo -e "${YELLOW}Failure recorded${NC}"
  fi

  # Update access history
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg hash "$query_hash" \
     --arg ts "$now" \
     --argjson success "$([ "$success" == "true" ] && echo true || echo false)" \
     '.access_history += [{
       timestamp: $ts,
       query_hash: $hash,
       success: $success
     }] | .access_history = .access_history[-100:]' \
     "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
  mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"
}

# Show performance comparison
show_performance() {
  echo -e "${BLUE}=== Smart Cache Performance ===${NC}"
  echo

  local enabled=$(jq -r '.enabled' "$SMART_CACHE_DATA")
  echo "Status: $([ "$enabled" == "true" ] && echo "Enabled" || echo "Disabled")"
  echo

  local smart_hits=$(jq -r '.performance_metrics.smart_hits' "$SMART_CACHE_DATA")
  local smart_misses=$(jq -r '.performance_metrics.smart_misses' "$SMART_CACHE_DATA")
  local total_smart=$((smart_hits + smart_misses))

  if [[ $total_smart -gt 0 ]]; then
    local smart_hit_rate=$(echo "scale=2; $smart_hits / $total_smart * 100" | bc)
    echo "Smart Cache:"
    echo "  Hits: $smart_hits"
    echo "  Misses: $smart_misses"
    echo "  Hit rate: ${smart_hit_rate}%"
  else
    echo "Smart Cache: No data yet"
  fi
  echo

  local entry_count=$(jq '.cache_entries | length' "$SMART_CACHE_DATA")
  echo "Cache entries: $entry_count"

  if [[ $entry_count -gt 0 ]]; then
    echo
    echo "Top performing entries:"
    jq -r '.cache_entries | to_entries | sort_by(-.value.success_count / .value.access_count) | .[:5][] |
      "  \(.key[0:8])...: success=\(.value.success_count)/\(.value.access_count) (\(.value.success_count / .value.access_count * 100 | floor)%)"' \
      "$SMART_CACHE_DATA"
  fi
}

# Configure weights
set_weights() {
  local similarity="$1"
  local recency="$2"
  local success_rate="$3"
  local complexity="$4"

  echo -e "${BLUE}Updating smart cache weights...${NC}"

  # Normalize to sum to 1.0
  local total=$(python3 -c "print($similarity + $recency + $success_rate + $complexity)")

  local norm_sim=$(python3 -c "print($similarity / $total)")
  local norm_rec=$(python3 -c "print($recency / $total)")
  local norm_succ=$(python3 -c "print($success_rate / $total)")
  local norm_comp=$(python3 -c "print($complexity / $total)")

  jq --argjson sim "$norm_sim" \
     --argjson rec "$norm_rec" \
     --argjson succ "$norm_succ" \
     --argjson comp "$norm_comp" \
     '.weights = {
       similarity: $sim,
       recency: $rec,
       success_rate: $succ,
       complexity: $comp
     }' \
     "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp"
  mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA"

  echo -e "${GREEN}✓ Weights updated and normalized${NC}"
  jq '.weights | to_entries[] | "  \(.key): \(.value | . * 100 | floor)%"' "$SMART_CACHE_DATA"
}

# Show configuration
show_config() {
  echo -e "${BLUE}=== Smart Cache Configuration ===${NC}"
  echo

  jq -r '
    "Enabled: \(.enabled)",
    "",
    "Weights:",
    "  Similarity: \(.weights.similarity | . * 100 | floor)%",
    "  Recency: \(.weights.recency | . * 100 | floor)%",
    "  Success Rate: \(.weights.success_rate | . * 100 | floor)%",
    "  Complexity: \(.weights.complexity | . * 100 | floor)%",
    "",
    "Thresholds:",
    "  Min similarity: \(.min_similarity_threshold)",
    "  Recency decay: \(.recency_decay_hours) hours",
    "",
    "Features:",
    "  Complexity analysis: \(.complexity_analysis_enabled)"
  ' "$SMART_CACHE_DATA"
}

# Main
case "${1:-}" in
  init) initialize_smart_cache && echo -e "${GREEN}✓ Smart cache initialized${NC}" ;;
  calculate-score) initialize_smart_cache && calculate_smart_score "$2" "$3" "$4" ;;
  should-use) initialize_smart_cache && should_use_cache "$2" "$3" "$4" ;;
  register) initialize_smart_cache && register_entry "$2" "$3" "$4" ;;
  feedback) initialize_smart_cache && record_feedback "$2" "$3" ;;
  performance) initialize_smart_cache && show_performance ;;
  config) initialize_smart_cache && show_config ;;
  set-weights) initialize_smart_cache && set_weights "$2" "$3" "$4" "$5" ;;
  enable) initialize_smart_cache && jq '.enabled = true' "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp" && mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA" && echo -e "${GREEN}✓ Smart cache enabled${NC}" ;;
  disable) initialize_smart_cache && jq '.enabled = false' "$SMART_CACHE_DATA" > "$SMART_CACHE_DATA.tmp" && mv "$SMART_CACHE_DATA.tmp" "$SMART_CACHE_DATA" && echo -e "${YELLOW}Smart cache disabled${NC}" ;;
  *)
    echo "Usage: $0 {init|calculate-score|should-use|register|feedback|performance|config|set-weights|enable|disable}"
    echo
    echo "Commands:"
    echo "  calculate-score <query> <candidate> <similarity> - Calculate smart score"
    echo "  should-use <query> <candidate> <similarity>      - Check if should use cache"
    echo "  register <hash> <query> <response>               - Register cache entry"
    echo "  feedback <hash> <true|false>                     - Record success/failure"
    echo "  performance                                      - Show performance metrics"
    echo "  config                                           - Show configuration"
    echo "  set-weights <sim> <rec> <succ> <comp>           - Set component weights"
    echo "  enable                                           - Enable smart caching"
    echo "  disable                                          - Disable smart caching"
    exit 1
    ;;
esac
