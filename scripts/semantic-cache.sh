#!/usr/bin/env bash
# semantic-cache.sh - Redis-based semantic cache with vector similarity
# Part of Phase 1A Caching Infrastructure

set -euo pipefail

CONFIG_FILE="$HOME/.claude/data/cache-config.json"
METRICS_FILE="$HOME/.claude/data/cache-metrics.json"

# Source embedding generator
source "$HOME/.claude/scripts/get-embedding.sh"

# Check if semantic caching is enabled
is_semantic_cache_enabled() {
  local enabled=$(jq -r '.semantic_caching_enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  [[ "$enabled" == "true" ]]
}

# Check Redis availability
is_redis_available() {
  redis-cli ping >/dev/null 2>&1
}

# Query semantic cache
# Usage: semantic_cache_get "query_text"
# Returns: cached response if found (similarity > threshold), empty otherwise
semantic_cache_get() {
  local query="$1"

  # Check if enabled
  if ! is_semantic_cache_enabled; then
    return 1
  fi

  # Check Redis availability
  if ! is_redis_available; then
    return 1
  fi

  local threshold=$(jq -r '.similarity_threshold // 0.92' "$CONFIG_FILE" 2>/dev/null || echo "0.92")

  # Generate embedding for query
  local query_embedding=$(get_embedding "$query")

  # Get all cached query embeddings
  local cache_keys=$(redis-cli KEYS "semantic_cache:*" 2>/dev/null || echo "")

  if [[ -z "$cache_keys" ]]; then
    update_cache_metrics "semantic" "miss"
    return 1
  fi

  # Find most similar cached query
  local best_similarity=0.0
  local best_key=""

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue

    # Get cached embedding
    local cached_embedding=$(redis-cli HGET "$key" "embedding" 2>/dev/null || echo "")
    [[ -z "$cached_embedding" ]] && continue

    # Calculate similarity
    local similarity=$(cosine_similarity "$query_embedding" "$cached_embedding")

    # Update best match
    if (( $(echo "$similarity > $best_similarity" | bc -l 2>/dev/null || echo 0) )); then
      best_similarity=$similarity
      best_key=$key
    fi
  done <<< "$cache_keys"

  # Check if best match exceeds threshold
  if (( $(echo "$best_similarity >= $threshold" | bc -l 2>/dev/null || echo 0) )); then
    # Cache hit
    local cached_response=$(redis-cli HGET "$best_key" "response" 2>/dev/null)
    update_cache_metrics "semantic" "hit" "$best_similarity"
    echo "$cached_response"
    return 0
  else
    # Cache miss
    update_cache_metrics "semantic" "miss"
    return 1
  fi
}

# Store in semantic cache
# Usage: semantic_cache_set "query_text" "response_text"
semantic_cache_set() {
  local query="$1"
  local response="$2"

  # Check if enabled
  if ! is_semantic_cache_enabled; then
    return 0
  fi

  # Check Redis availability
  if ! is_redis_available; then
    return 0
  fi

  local ttl=$(jq -r '.cache_ttl_seconds // 86400' "$CONFIG_FILE" 2>/dev/null || echo "86400")

  # Generate embedding
  local query_embedding=$(get_embedding "$query")

  # Generate cache key
  local query_hash=$(echo -n "$query" | shasum -a 256 | cut -d' ' -f1)
  local cache_key="semantic_cache:$query_hash"

  # Store in Redis
  redis-cli HSET "$cache_key" \
    "query" "$query" \
    "embedding" "$query_embedding" \
    "response" "$response" \
    "timestamp" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    >/dev/null 2>&1

  # Set TTL
  redis-cli EXPIRE "$cache_key" "$ttl" >/dev/null 2>&1
}

# Invalidate semantic cache
# Usage: semantic_cache_invalidate [pattern]
semantic_cache_invalidate() {
  local pattern="${1:-*}"

  if ! is_redis_available; then
    echo "Redis not available" >&2
    return 1
  fi

  local keys=$(redis-cli KEYS "semantic_cache:$pattern" 2>/dev/null || echo "")
  local count=0

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    redis-cli DEL "$key" >/dev/null 2>&1
    ((count++))
  done <<< "$keys"

  echo "Invalidated $count cache entries"
}

# Update cache metrics
update_cache_metrics() {
  local cache_type="$1"  # "semantic" or "prompt"
  local result="$2"      # "hit" or "miss"
  local similarity="${3:-0.0}"

  # Thread-safe update using jq
  local temp_file=$(mktemp)

  jq --arg type "$cache_type" \
     --arg result "$result" \
     --arg sim "$similarity" \
     --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
    if $type == "semantic" then
      .semantic_cache.total_requests += 1 |
      if $result == "hit" then
        .semantic_cache.cache_hits += 1 |
        .semantic_cache.avg_similarity_score = (
          (.semantic_cache.avg_similarity_score * (.semantic_cache.cache_hits - 1) + ($sim | tonumber)) / .semantic_cache.cache_hits
        )
      else
        .semantic_cache.cache_misses += 1
      end
    else
      .prompt_cache.total_requests += 1 |
      if $result == "hit" then
        .prompt_cache.cache_hits += 1
      else
        .prompt_cache.cache_misses += 1
      end
    end |
    .last_updated = $ts
  ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Export functions
export -f semantic_cache_get
export -f semantic_cache_set
export -f semantic_cache_invalidate
export -f is_semantic_cache_enabled
export -f is_redis_available
