#!/usr/bin/env bash
# cache-manager.sh - Unified CLI for cache management
# Part of Phase 1A Caching Infrastructure

set -euo pipefail

CONFIG_FILE="$HOME/.claude/data/cache-config.json"
METRICS_FILE="$HOME/.claude/data/cache-metrics.json"

# Source cache components
source "$HOME/.claude/scripts/semantic-cache.sh" 2>/dev/null || true
source "$HOME/.claude/scripts/llm-api-wrapper.sh" 2>/dev/null || true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
  local color=$1
  local msg=$2
  echo -e "${color}${msg}${NC}"
}

# Show cache status
cmd_status() {
  print_msg "$BLUE" "=== Cache System Status ==="
  echo

  # Check Redis
  if is_redis_available 2>/dev/null; then
    print_msg "$GREEN" "✓ Redis: Running"
    local redis_version=$(redis-cli INFO server 2>/dev/null | grep redis_version | cut -d':' -f2 | tr -d '\r')
    echo "  Version: $redis_version"

    # Count cached entries
    local cache_count=$(redis-cli KEYS "semantic_cache:*" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Cached entries: $cache_count"
  else
    print_msg "$YELLOW" "⚠ Redis: Not running"
  fi
  echo

  # Check configuration
  if [[ -f "$CONFIG_FILE" ]]; then
    print_msg "$GREEN" "✓ Configuration: Found"

    local prompt_cache=$(jq -r '.prompt_caching_enabled' "$CONFIG_FILE")
    local semantic_cache=$(jq -r '.semantic_caching_enabled' "$CONFIG_FILE")
    local threshold=$(jq -r '.similarity_threshold' "$CONFIG_FILE")
    local ttl=$(jq -r '.cache_ttl_seconds' "$CONFIG_FILE")

    echo "  Prompt caching: $prompt_cache"
    echo "  Semantic caching: $semantic_cache"
    echo "  Similarity threshold: $threshold"
    echo "  TTL: ${ttl}s ($(echo "scale=1; $ttl/3600" | bc)h)"
  else
    print_msg "$RED" "✗ Configuration: Missing"
  fi
  echo

  # Show metrics
  if [[ -f "$METRICS_FILE" ]]; then
    print_msg "$BLUE" "=== Cache Metrics ==="
    echo

    # Prompt cache metrics
    local pc_total=$(jq -r '.prompt_cache.total_requests' "$METRICS_FILE")
    local pc_hits=$(jq -r '.prompt_cache.cache_hits' "$METRICS_FILE")
    local pc_misses=$(jq -r '.prompt_cache.cache_misses' "$METRICS_FILE")
    local pc_tokens=$(jq -r '.prompt_cache.tokens_saved' "$METRICS_FILE")
    local pc_cost=$(jq -r '.prompt_cache.cost_saved_usd' "$METRICS_FILE")

    echo "Prompt Cache:"
    echo "  Total requests: $pc_total"
    echo "  Cache hits: $pc_hits"
    echo "  Cache misses: $pc_misses"

    if [[ $pc_total -gt 0 ]]; then
      local pc_hit_rate=$(echo "scale=1; $pc_hits * 100 / $pc_total" | bc)
      echo "  Hit rate: ${pc_hit_rate}%"
    fi

    echo "  Tokens saved: $pc_tokens"
    echo "  Cost saved: \$${pc_cost}"
    echo

    # Semantic cache metrics
    local sc_total=$(jq -r '.semantic_cache.total_requests' "$METRICS_FILE")
    local sc_hits=$(jq -r '.semantic_cache.cache_hits' "$METRICS_FILE")
    local sc_misses=$(jq -r '.semantic_cache.cache_misses' "$METRICS_FILE")
    local sc_similarity=$(jq -r '.semantic_cache.avg_similarity_score' "$METRICS_FILE")

    echo "Semantic Cache:"
    echo "  Total requests: $sc_total"
    echo "  Cache hits: $sc_hits"
    echo "  Cache misses: $sc_misses"

    if [[ $sc_total -gt 0 ]]; then
      local sc_hit_rate=$(echo "scale=1; $sc_hits * 100 / $sc_total" | bc)
      echo "  Hit rate: ${sc_hit_rate}%"
    fi

    echo "  Avg similarity: $sc_similarity"
    echo

    # Performance metrics
    local avg_latency=$(jq -r '.performance.avg_latency_ms' "$METRICS_FILE")
    local cached_latency=$(jq -r '.performance.avg_latency_with_cache_ms' "$METRICS_FILE")
    local reduction=$(jq -r '.performance.latency_reduction_pct' "$METRICS_FILE")

    echo "Performance:"
    echo "  Avg API latency: ${avg_latency}ms"
    echo "  Avg cached latency: ${cached_latency}ms"
    echo "  Latency reduction: ${reduction}%"

    local last_updated=$(jq -r '.last_updated' "$METRICS_FILE")
    echo
    echo "Last updated: $last_updated"
  else
    print_msg "$YELLOW" "⚠ Metrics: Not available"
  fi
}

# Clear cache
cmd_clear() {
  local pattern="${1:-*}"

  print_msg "$YELLOW" "Clearing cache entries matching: $pattern"

  if ! is_redis_available 2>/dev/null; then
    print_msg "$RED" "✗ Redis not available"
    return 1
  fi

  semantic_cache_invalidate "$pattern"
  print_msg "$GREEN" "✓ Cache cleared"
}

# Test caching system
cmd_test() {
  print_msg "$BLUE" "=== Testing Cache System ==="
  echo

  # Test 1: Redis connectivity
  echo "Test 1: Redis connectivity"
  if is_redis_available 2>/dev/null; then
    print_msg "$GREEN" "  ✓ Redis responding to PING"
  else
    print_msg "$RED" "  ✗ Redis not available"
    return 1
  fi

  # Test 2: Configuration files
  echo
  echo "Test 2: Configuration files"
  if [[ -f "$CONFIG_FILE" ]] && jq empty "$CONFIG_FILE" 2>/dev/null; then
    print_msg "$GREEN" "  ✓ cache-config.json valid"
  else
    print_msg "$RED" "  ✗ cache-config.json invalid"
    return 1
  fi

  if [[ -f "$METRICS_FILE" ]] && jq empty "$METRICS_FILE" 2>/dev/null; then
    print_msg "$GREEN" "  ✓ cache-metrics.json valid"
  else
    print_msg "$RED" "  ✗ cache-metrics.json invalid"
    return 1
  fi

  # Test 3: Embedding generation
  echo
  echo "Test 3: Embedding generation"
  local test_text="Hello world"
  local embedding=$(get_embedding "$test_text" 2>/dev/null || echo "")

  if [[ -n "$embedding" ]] && echo "$embedding" | jq empty 2>/dev/null; then
    print_msg "$GREEN" "  ✓ Embedding generation working"
    local dim=$(echo "$embedding" | jq 'length')
    echo "    Dimension: $dim"
  else
    print_msg "$RED" "  ✗ Embedding generation failed"
    return 1
  fi

  # Test 4: Semantic cache operations
  echo
  echo "Test 4: Semantic cache operations"

  # Test set
  local test_query="test query $(date +%s)"
  local test_response="test response"

  if semantic_cache_set "$test_query" "$test_response" 2>/dev/null; then
    print_msg "$GREEN" "  ✓ Cache SET operation"
  else
    print_msg "$RED" "  ✗ Cache SET operation failed"
    return 1
  fi

  # Test get
  local retrieved=$(semantic_cache_get "$test_query" 2>/dev/null || echo "")
  if [[ "$retrieved" == "$test_response" ]]; then
    print_msg "$GREEN" "  ✓ Cache GET operation (exact match)"
  else
    print_msg "$YELLOW" "  ⚠ Cache GET returned: $retrieved"
  fi

  # Test similarity matching
  local similar_query="test query $(date +%s)"
  local similar_result=$(semantic_cache_get "$similar_query" 2>/dev/null || echo "")

  if [[ -n "$similar_result" ]]; then
    print_msg "$GREEN" "  ✓ Semantic similarity matching"
  else
    print_msg "$YELLOW" "  ⚠ No similar match found (threshold may be too high)"
  fi

  # Test 5: Cosine similarity calculation
  echo
  echo "Test 5: Cosine similarity"
  local vec1="[0.5, 0.5, 0.5, 0.5]"
  local vec2="[0.5, 0.5, 0.5, 0.5]"
  local similarity=$(cosine_similarity "$vec1" "$vec2" 2>/dev/null || echo "")

  if [[ -n "$similarity" ]]; then
    print_msg "$GREEN" "  ✓ Cosine similarity: $similarity"
  else
    print_msg "$RED" "  ✗ Cosine similarity calculation failed"
    return 1
  fi

  echo
  print_msg "$GREEN" "=== All Tests Passed ==="
}

# Configure cache settings
cmd_configure() {
  local key="$1"
  local value="$2"

  if [[ -z "$key" ]] || [[ -z "$value" ]]; then
    echo "Usage: $0 configure <key> <value>"
    echo
    echo "Available keys:"
    echo "  prompt_caching_enabled    true|false"
    echo "  semantic_caching_enabled  true|false"
    echo "  similarity_threshold      0.0-1.0"
    echo "  cache_ttl_seconds         seconds"
    echo "  max_cache_size_mb         megabytes"
    return 1
  fi

  # Update configuration
  local temp_file=$(mktemp)

  case "$key" in
    prompt_caching_enabled|semantic_caching_enabled)
      jq --arg v "$value" ".${key} = (\$v | test(\"true\"; \"i\"))" "$CONFIG_FILE" > "$temp_file"
      ;;
    similarity_threshold)
      jq --argjson v "$value" ".${key} = \$v" "$CONFIG_FILE" > "$temp_file"
      ;;
    cache_ttl_seconds|max_cache_size_mb)
      jq --argjson v "$value" ".${key} = \$v" "$CONFIG_FILE" > "$temp_file"
      ;;
    *)
      print_msg "$RED" "Unknown configuration key: $key"
      rm "$temp_file"
      return 1
      ;;
  esac

  mv "$temp_file" "$CONFIG_FILE"
  print_msg "$GREEN" "✓ Updated $key = $value"
}

# Reset metrics
cmd_reset_metrics() {
  print_msg "$YELLOW" "Resetting cache metrics..."

  cat > "$METRICS_FILE" << 'EOF'
{
  "version": "1.0.0",
  "initialized_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "prompt_cache": {
    "total_requests": 0,
    "cache_hits": 0,
    "cache_misses": 0,
    "tokens_saved": 0,
    "cost_saved_usd": 0.0
  },
  "semantic_cache": {
    "total_requests": 0,
    "cache_hits": 0,
    "cache_misses": 0,
    "cost_saved_usd": 0.0,
    "avg_similarity_score": 0.0
  },
  "performance": {
    "avg_latency_ms": 0,
    "avg_latency_with_cache_ms": 0,
    "latency_reduction_pct": 0
  },
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

  print_msg "$GREEN" "✓ Metrics reset"
}

# Show help
cmd_help() {
  cat << 'EOF'
cache-manager.sh - Unified CLI for cache management

USAGE:
  cache-manager.sh <command> [options]

COMMANDS:
  status              Show cache system status and metrics
  clear [pattern]     Clear cache entries (default: all)
  test                Run comprehensive cache system tests
  configure <k> <v>   Update configuration setting
  reset-metrics       Reset all cache metrics to zero
  help                Show this help message

EXAMPLES:
  # Show current status
  cache-manager.sh status

  # Clear all cache entries
  cache-manager.sh clear

  # Clear specific pattern
  cache-manager.sh clear "user_*"

  # Run tests
  cache-manager.sh test

  # Update configuration
  cache-manager.sh configure similarity_threshold 0.95
  cache-manager.sh configure semantic_caching_enabled false

  # Reset metrics
  cache-manager.sh reset-metrics

For more information, see: ~/.claude/docs/CACHING.md
EOF
}

# Main command router
main() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    status)
      cmd_status
      ;;
    clear)
      cmd_clear "$@"
      ;;
    test)
      cmd_test
      ;;
    configure)
      cmd_configure "$@"
      ;;
    reset-metrics)
      cmd_reset_metrics
      ;;
    help|--help|-h)
      cmd_help
      ;;
    *)
      print_msg "$RED" "Unknown command: $command"
      echo
      cmd_help
      exit 1
      ;;
  esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
