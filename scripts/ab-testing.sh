#!/usr/bin/env bash
# ab-testing.sh - Statistical A/B testing framework for configurations
# Provides confidence levels for configuration changes
# Part of Phase 3B - High Impact Improvements

set -euo pipefail

AB_TEST_DATA="$HOME/.claude/data/ab-test-data.json"
LEARNING_DATA="$HOME/.claude/data/learning-data.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Initialize A/B test data
initialize_ab_test() {
  if [[ ! -f "$AB_TEST_DATA" ]]; then
    cat > "$AB_TEST_DATA" <<'EOF'
{
  "version": "1.0.0",
  "active_tests": [],
  "completed_tests": [],
  "min_samples_per_variant": 20,
  "significance_level": 0.05,
  "minimum_effect_size": 0.05
}
EOF
  fi
}

# Create new A/B test
create_test() {
  local test_name="$1"
  local variant_a_cache="$2"
  local variant_a_concurrent="$3"
  local variant_b_cache="$4"
  local variant_b_concurrent="$5"

  echo -e "${BLUE}Creating A/B test: $test_name${NC}"

  local test_id="test_$(date +%s)"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Create test structure
  local test=$(jq -n \
    --arg id "$test_id" \
    --arg name "$test_name" \
    --arg ts "$now" \
    --argjson a_cache "$variant_a_cache" \
    --argjson a_concurrent "$variant_a_concurrent" \
    --argjson b_cache "$variant_b_cache" \
    --argjson b_concurrent "$variant_b_concurrent" \
    '{
      test_id: $id,
      test_name: $name,
      created_at: $ts,
      status: "running",
      variant_a: {
        name: "control",
        config: {cache_threshold: $a_cache, max_concurrent: $a_concurrent},
        samples: [],
        metrics: {hit_rate: [], success_rate: [], latency: []}
      },
      variant_b: {
        name: "treatment",
        config: {cache_threshold: $b_cache, max_concurrent: $b_concurrent},
        samples: [],
        metrics: {hit_rate: [], success_rate: [], latency: []}
      },
      current_variant: "a",
      results: null
    }')

  # Add to active tests
  jq --argjson test "$test" '.active_tests += [$test]' "$AB_TEST_DATA" > "$AB_TEST_DATA.tmp"
  mv "$AB_TEST_DATA.tmp" "$AB_TEST_DATA"

  echo -e "${GREEN}✓ Test created: $test_id${NC}"
  echo "  Variant A (control): cache=$variant_a_cache, concurrent=$variant_a_concurrent"
  echo "  Variant B (treatment): cache=$variant_b_cache, concurrent=$variant_b_concurrent"
  echo
  echo "Apply variant A with: $0 apply-variant $test_id a"
}

# Apply variant configuration
apply_variant() {
  local test_id="$1"
  local variant="$2"

  echo -e "${BLUE}Applying variant $variant for test: $test_id${NC}"

  # Get variant config
  local config=$(jq -r --arg id "$test_id" --arg v "$variant" \
    '.active_tests[] | select(.test_id == $id) | .variant_' + "$variant" + '.config' \
    "$AB_TEST_DATA")

  if [[ "$config" == "null" ]] || [[ -z "$config" ]]; then
    echo -e "${RED}Test not found or invalid variant${NC}"
    return 1
  fi

  local cache_threshold=$(echo "$config" | jq -r '.cache_threshold')
  local max_concurrent=$(echo "$config" | jq -r '.max_concurrent')

  # Apply configuration
  jq --argjson threshold "$cache_threshold" '.similarity_threshold = $threshold' "$CACHE_CONFIG" > "$CACHE_CONFIG.tmp"
  mv "$CACHE_CONFIG.tmp" "$CACHE_CONFIG"

  jq --argjson concurrent "$max_concurrent" '.max_concurrent_processes = $concurrent' "$PARALLEL_CONFIG" > "$PARALLEL_CONFIG.tmp"
  mv "$PARALLEL_CONFIG.tmp" "$PARALLEL_CONFIG"

  # Update current variant
  jq --arg id "$test_id" --arg v "$variant" \
     '(.active_tests[] | select(.test_id == $id) | .current_variant) = $v' \
     "$AB_TEST_DATA" > "$AB_TEST_DATA.tmp"
  mv "$AB_TEST_DATA.tmp" "$AB_TEST_DATA"

  echo -e "${GREEN}✓ Variant $variant applied${NC}"
  echo "  Cache threshold: $cache_threshold"
  echo "  Max concurrent: $max_concurrent"
}

# Collect sample for current variant
collect_sample() {
  local test_id="$1"

  echo -e "${BLUE}Collecting sample for test: $test_id${NC}"

  [[ ! -f "$LEARNING_DATA" ]] && { echo "No learning data"; return 1; }

  # Get current variant
  local variant=$(jq -r --arg id "$test_id" \
    '.active_tests[] | select(.test_id == $id) | .current_variant' \
    "$AB_TEST_DATA")

  if [[ "$variant" == "null" ]] || [[ -z "$variant" ]]; then
    echo -e "${RED}Test not found${NC}"
    return 1
  fi

  # Get recent metrics
  local metrics=$(python3 <<'PYEOF'
import json

with open('/Users/wallonwalusayi/.claude/data/learning-data.json') as f:
    data = json.load(f)

cache_history = data.get('cache_outcomes', {}).get('hit_rate_history', [])
latency_history = data.get('cache_outcomes', {}).get('latency_history', [])
success_history = data.get('parallel_outcomes', {}).get('success_rate_history', [])

if cache_history and success_history:
    hit_rate = cache_history[-1].get('hit_rate', 0)
    latency = latency_history[-1].get('avg_latency_ms', 0) if latency_history else 0
    success_rate = success_history[-1].get('success_rate', 0) / 100.0

    print(json.dumps({
        'hit_rate': hit_rate,
        'latency': latency,
        'success_rate': success_rate
    }))
else:
    print(json.dumps({'hit_rate': 0, 'latency': 0, 'success_rate': 0}))
PYEOF
)

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Add sample to variant
  jq --arg id "$test_id" \
     --arg v "$variant" \
     --arg ts "$now" \
     --argjson metrics "$metrics" \
     '(.active_tests[] | select(.test_id == $id) | .variant_' + "$v" + '.samples) += [{timestamp: $ts, metrics: $metrics}] |
      (.active_tests[] | select(.test_id == $id) | .variant_' + "$v" + '.metrics.hit_rate) += [$metrics.hit_rate] |
      (.active_tests[] | select(.test_id == $id) | .variant_' + "$v" + '.metrics.latency) += [$metrics.latency] |
      (.active_tests[] | select(.test_id == $id) | .variant_' + "$v" + '.metrics.success_rate) += [$metrics.success_rate]' \
     "$AB_TEST_DATA" > "$AB_TEST_DATA.tmp"
  mv "$AB_TEST_DATA.tmp" "$AB_TEST_DATA"

  echo -e "${GREEN}✓ Sample collected for variant $variant${NC}"
  echo "  Hit rate: $(echo "$metrics" | jq -r '.hit_rate | . * 100 | floor')%"
  echo "  Latency: $(echo "$metrics" | jq -r '.latency | floor')ms"
  echo "  Success rate: $(echo "$metrics" | jq -r '.success_rate | . * 100 | floor')%"
}

# Analyze test results
analyze_test() {
  local test_id="$1"

  echo -e "${BLUE}Analyzing test: $test_id${NC}"

  local test=$(jq --arg id "$test_id" '.active_tests[] | select(.test_id == $id)' "$AB_TEST_DATA")

  if [[ "$test" == "null" ]] || [[ -z "$test" ]]; then
    echo -e "${RED}Test not found${NC}"
    return 1
  fi

  # Check minimum samples
  local min_samples=$(jq -r '.min_samples_per_variant' "$AB_TEST_DATA")
  local a_samples=$(echo "$test" | jq '.variant_a.samples | length')
  local b_samples=$(echo "$test" | jq '.variant_b.samples | length')

  if [[ $a_samples -lt $min_samples ]] || [[ $b_samples -lt $min_samples ]]; then
    echo -e "${YELLOW}Not enough samples yet${NC}"
    echo "  Variant A: $a_samples / $min_samples"
    echo "  Variant B: $b_samples / $min_samples"
    return 1
  fi

  # Perform statistical analysis using Python
  local analysis=$(echo "$test" | python3 <<'PYEOF'
import json
import sys
import math

test = json.load(sys.stdin)
alpha = 0.05  # 95% confidence

def t_test(samples_a, samples_b):
    """Perform Welch's t-test"""
    n_a, n_b = len(samples_a), len(samples_b)
    mean_a = sum(samples_a) / n_a
    mean_b = sum(samples_b) / n_b

    var_a = sum((x - mean_a) ** 2 for x in samples_a) / (n_a - 1)
    var_b = sum((x - mean_b) ** 2 for x in samples_b) / (n_b - 1)

    se = math.sqrt(var_a / n_a + var_b / n_b)
    if se == 0:
        return {'significant': False, 'p_value': 1.0, 'effect_size': 0}

    t_stat = (mean_b - mean_a) / se
    df = ((var_a / n_a + var_b / n_b) ** 2) / \
         ((var_a / n_a) ** 2 / (n_a - 1) + (var_b / n_b) ** 2 / (n_b - 1))

    # Approximate p-value (simplified)
    p_value = 2 * (1 - 0.5 * (1 + math.erf(abs(t_stat) / math.sqrt(2))))

    effect_size = (mean_b - mean_a) / mean_a if mean_a > 0 else 0

    return {
        'significant': p_value < alpha,
        'p_value': p_value,
        'effect_size': effect_size,
        'mean_a': mean_a,
        'mean_b': mean_b
    }

# Test each metric
results = {}
for metric in ['hit_rate', 'latency', 'success_rate']:
    samples_a = test['variant_a']['metrics'][metric]
    samples_b = test['variant_b']['metrics'][metric]

    if samples_a and samples_b:
        results[metric] = t_test(samples_a, samples_b)

# Overall recommendation
significant_improvements = sum(1 for r in results.values() if r['significant'] and r['effect_size'] > 0)
significant_regressions = sum(1 for r in results.values() if r['significant'] and r['effect_size'] < 0)

if significant_improvements > significant_regressions:
    recommendation = 'adopt_b'
elif significant_regressions > significant_improvements:
    recommendation = 'keep_a'
else:
    recommendation = 'inconclusive'

print(json.dumps({
    'results': results,
    'recommendation': recommendation,
    'confidence': 'high' if max(r['p_value'] for r in results.values()) < 0.01 else 'medium'
}))
PYEOF
)

  # Display results
  echo
  echo -e "${GREEN}=== Test Results ===${NC}"
  echo

  echo "$analysis" | jq -r '
    "Recommendation: \(.recommendation | ascii_upcase)",
    "Confidence: \(.confidence)",
    "",
    "Metric Analysis:",
    (.results | to_entries[] |
      "  \(.key):",
      "    Variant A: \(.value.mean_a | . * 100 | floor)%",
      "    Variant B: \(.value.mean_b | . * 100 | floor)%",
      "    Effect: \(.value.effect_size | . * 100 | floor)%",
      "    Significant: \(.value.significant)",
      "    P-value: \(.value.p_value)",
      ""
    )'

  # Update test with results
  jq --arg id "$test_id" \
     --argjson analysis "$analysis" \
     '(.active_tests[] | select(.test_id == $id) | .results) = $analysis' \
     "$AB_TEST_DATA" > "$AB_TEST_DATA.tmp"
  mv "$AB_TEST_DATA.tmp" "$AB_TEST_DATA"
}

# Complete test
complete_test() {
  local test_id="$1"

  echo -e "${BLUE}Completing test: $test_id${NC}"

  # Move from active to completed
  local test=$(jq --arg id "$test_id" '.active_tests[] | select(.test_id == $id)' "$AB_TEST_DATA")

  if [[ "$test" == "null" ]] || [[ -z "$test" ]]; then
    echo -e "${RED}Test not found${NC}"
    return 1
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg id "$test_id" \
     --arg ts "$now" \
     '.active_tests = [.active_tests[] | select(.test_id != $id)] |
      .completed_tests += [(. | {test_id: $id, completed_at: $ts} + ($test | del(.current_variant)))]' \
     "$AB_TEST_DATA" > "$AB_TEST_DATA.tmp"
  mv "$AB_TEST_DATA.tmp" "$AB_TEST_DATA"

  echo -e "${GREEN}✓ Test completed${NC}"
}

# List active tests
list_tests() {
  echo -e "${BLUE}=== Active A/B Tests ===${NC}"
  echo

  local count=$(jq '.active_tests | length' "$AB_TEST_DATA")

  if [[ $count -eq 0 ]]; then
    echo "No active tests"
    return 0
  fi

  jq -r '.active_tests[] |
    "ID: \(.test_id)",
    "Name: \(.test_name)",
    "Created: \(.created_at)",
    "Status: \(.status)",
    "Variant A samples: \(.variant_a.samples | length)",
    "Variant B samples: \(.variant_b.samples | length)",
    ""' \
    "$AB_TEST_DATA"
}

# Main
case "${1:-}" in
  init) initialize_ab_test && echo -e "${GREEN}✓ A/B testing initialized${NC}" ;;
  create) initialize_ab_test && create_test "$2" "$3" "$4" "$5" "$6" ;;
  apply-variant) initialize_ab_test && apply_variant "$2" "$3" ;;
  collect-sample) initialize_ab_test && collect_sample "$2" ;;
  analyze) initialize_ab_test && analyze_test "$2" ;;
  complete) initialize_ab_test && complete_test "$2" ;;
  list) initialize_ab_test && list_tests ;;
  status)
    initialize_ab_test
    echo -e "${BLUE}=== A/B Testing Status ===${NC}"
    echo
    echo "Active tests: $(jq '.active_tests | length' "$AB_TEST_DATA")"
    echo "Completed tests: $(jq '.completed_tests | length' "$AB_TEST_DATA")"
    echo "Min samples per variant: $(jq -r '.min_samples_per_variant' "$AB_TEST_DATA")"
    echo "Significance level: $(jq -r '.significance_level' "$AB_TEST_DATA")"
    ;;
  *)
    echo "Usage: $0 {init|create|apply-variant|collect-sample|analyze|complete|list|status}"
    echo
    echo "Commands:"
    echo "  create <name> <a_cache> <a_conc> <b_cache> <b_conc> - Create test"
    echo "  apply-variant <test_id> <a|b>     - Apply variant config"
    echo "  collect-sample <test_id>          - Collect performance sample"
    echo "  analyze <test_id>                 - Analyze test results"
    echo "  complete <test_id>                - Complete and archive test"
    echo "  list                              - List active tests"
    echo "  status                            - Show status"
    exit 1
    ;;
esac
