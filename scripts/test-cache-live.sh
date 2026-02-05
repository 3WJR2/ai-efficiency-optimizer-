#!/usr/bin/env bash
# test-cache-live.sh - Live caching demonstration with real API calls
# Shows prompt caching and semantic caching in action

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Live Cache Testing ===${NC}"
echo

# Source the API wrapper
source "$HOME/.claude/scripts/llm-api-wrapper.sh"

# Check API key
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo -e "${YELLOW}⚠ ANTHROPIC_API_KEY not set${NC}"
  echo "Set it with: export ANTHROPIC_API_KEY='your-key'"
  exit 1
fi

echo -e "${GREEN}✓ API key found${NC}"
echo

# Reset metrics for clean test
echo "Resetting metrics..."
cat > "$HOME/.claude/data/cache-metrics.json" << 'EOF'
{
  "version": "1.0.0",
  "initialized_at": "2026-02-02T00:00:00Z",
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
  "last_updated": "2026-02-02T00:00:00Z"
}
EOF

# Clear semantic cache
redis-cli FLUSHDB >/dev/null 2>&1 || true
echo -e "${GREEN}✓ Metrics reset, cache cleared${NC}"
echo

# Test 1: Initial API call (cache miss)
echo -e "${BLUE}Test 1: Initial API call (should be cache miss)${NC}"
echo "Query: What is 2+2?"
echo

start1=$(python3 -c "import time; print(int(time.time() * 1000))")
response1=$(call_claude_api "You are a helpful math assistant." "What is 2+2?" 2>/dev/null || echo "API call failed")
end1=$(python3 -c "import time; print(int(time.time() * 1000))")
latency1=$((end1 - start1))

echo "Response: $response1"
echo "Latency: ${latency1}ms"
echo

sleep 2

# Test 2: Exact same query (semantic cache hit)
echo -e "${BLUE}Test 2: Exact same query (should be semantic cache hit)${NC}"
echo "Query: What is 2+2?"
echo

start2=$(python3 -c "import time; print(int(time.time() * 1000))")
response2=$(call_claude_api "You are a helpful math assistant." "What is 2+2?" 2>/dev/null || echo "API call failed")
end2=$(python3 -c "import time; print(int(time.time() * 1000))")
latency2=$((end2 - start2))

echo "Response: $response2"
echo "Latency: ${latency2}ms"
echo

# Calculate improvement
if [[ $latency1 -gt 0 ]]; then
  improvement=$(echo "scale=1; ($latency1 - $latency2) * 100 / $latency1" | bc)
  echo -e "${GREEN}Speed improvement: ${improvement}%${NC}"
fi
echo

sleep 2

# Test 3: Similar query (semantic cache hit with similarity matching)
echo -e "${BLUE}Test 3: Similar query (should match semantically)${NC}"
echo "Query: What's two plus two?"
echo

start3=$(python3 -c "import time; print(int(time.time() * 1000))")
response3=$(call_claude_api "You are a helpful math assistant." "What's two plus two?" 2>/dev/null || echo "API call failed")
end3=$(python3 -c "import time; print(int(time.time() * 1000))")
latency3=$((end3 - start3))

echo "Response: $response3"
echo "Latency: ${latency3}ms"
echo

if [[ $latency1 -gt 0 ]]; then
  improvement3=$(echo "scale=1; ($latency1 - $latency3) * 100 / $latency1" | bc)
  echo -e "${GREEN}Speed improvement vs initial: ${improvement3}%${NC}"
fi
echo

sleep 2

# Test 4: Different query (cache miss)
echo -e "${BLUE}Test 4: Different query (should be cache miss)${NC}"
echo "Query: What is the capital of France?"
echo

start4=$(python3 -c "import time; print(int(time.time() * 1000))")
response4=$(call_claude_api "You are a helpful geography assistant." "What is the capital of France?" 2>/dev/null || echo "API call failed")
end4=$(python3 -c "import time; print(int(time.time() * 1000))")
latency4=$((end4 - start4))

echo "Response: $response4"
echo "Latency: ${latency4}ms"
echo

# Show final metrics
echo -e "${BLUE}=== Final Cache Metrics ===${NC}"
echo

cat "$HOME/.claude/data/cache-metrics.json" | jq -r '
  "Prompt Cache:",
  "  Total requests: \(.prompt_cache.total_requests)",
  "  Cache hits: \(.prompt_cache.cache_hits)",
  "  Cache misses: \(.prompt_cache.cache_misses)",
  "  Tokens saved: \(.prompt_cache.tokens_saved)",
  "  Cost saved: $\(.prompt_cache.cost_saved_usd)",
  "",
  "Semantic Cache:",
  "  Total requests: \(.semantic_cache.total_requests)",
  "  Cache hits: \(.semantic_cache.cache_hits)",
  "  Cache misses: \(.semantic_cache.cache_misses)",
  "  Avg similarity: \(.semantic_cache.avg_similarity_score)",
  "",
  "Performance:",
  "  Avg API latency: \(.performance.avg_latency_ms)ms",
  "  Avg cached latency: \(.performance.avg_latency_with_cache_ms)ms",
  "  Latency reduction: \(.performance.latency_reduction_pct)%"
'

echo
echo -e "${GREEN}=== Live Cache Test Complete ===${NC}"
