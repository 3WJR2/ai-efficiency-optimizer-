#!/usr/bin/env bash
# llm-api-wrapper.sh - Transparent wrapper for Anthropic API with caching
# Part of Phase 1A Caching Infrastructure

set -euo pipefail

CONFIG_FILE="$HOME/.claude/data/cache-config.json"
METRICS_FILE="$HOME/.claude/data/cache-metrics.json"

# Source semantic cache
source "$HOME/.claude/scripts/semantic-cache.sh" 2>/dev/null || true

# Check if caching is enabled
is_cache_enabled() {
  local enabled=$(jq -r '.feature_flags.enable_cache // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
  [[ "$enabled" == "true" ]]
}

# Call Claude API with caching
# Usage: call_claude_api "system_prompt" "user_prompt" [additional_args_json]
# Returns: API response text
call_claude_api() {
  local system_prompt="$1"
  local user_prompt="$2"
  local additional_args="${3:-{}}"

  local start_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || date +%s000)

  # Check semantic cache first (if enabled)
  if is_cache_enabled && is_semantic_cache_enabled 2>/dev/null; then
    local cached_response=$(semantic_cache_get "$user_prompt" 2>/dev/null || echo "")

    if [[ -n "$cached_response" ]]; then
      local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || date +%s000)
      local latency=$((end_time - start_time))

      # Update metrics
      update_performance_metrics "$latency" "cached"

      # Return cached response
      echo "$cached_response"
      return 0
    fi
  fi

  # Build API request
  local api_key="${ANTHROPIC_API_KEY:-}"

  if [[ -z "$api_key" ]]; then
    echo "Error: ANTHROPIC_API_KEY not set" >&2
    return 1
  fi

  # Check if prompt caching enabled
  local use_prompt_cache=$(jq -r '.prompt_caching_enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

  # Build messages array
  local model=$(echo "$additional_args" | jq -r '.model // "claude-sonnet-4-5-20250929"')
  local max_tokens=$(echo "$additional_args" | jq -r '.max_tokens // 4096')

  # Create request JSON with caching
  local request_json=$(jq -n \
    --arg model "$model" \
    --argjson max_tokens "$max_tokens" \
    --arg system "$system_prompt" \
    --arg user "$user_prompt" \
    --arg use_cache "$use_prompt_cache" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      system: [{
        type: "text",
        text: $system,
        cache_control: (if $use_cache == "true" then {type: "ephemeral"} else null end)
      }],
      messages: [{
        role: "user",
        content: $user
      }]
    }' | jq 'if .system[0].cache_control == null then del(.system[0].cache_control) else . end')

  # Make API call
  local response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "$request_json")

  local end_time=$(python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || date +%s000)
  local latency=$((end_time - start_time))

  # Extract response content
  local content=$(echo "$response" | jq -r '.content[0].text // ""')

  # Check for errors
  if [[ -z "$content" ]]; then
    echo "Error: API call failed" >&2
    echo "$response" >&2
    return 1
  fi

  # Update metrics from usage data
  local input_tokens=$(echo "$response" | jq -r '.usage.input_tokens // 0')
  local output_tokens=$(echo "$response" | jq -r '.usage.output_tokens // 0')
  local cached_tokens=$(echo "$response" | jq -r '.usage.cache_read_input_tokens // 0')

  update_prompt_cache_metrics "$input_tokens" "$output_tokens" "$cached_tokens"
  update_performance_metrics "$latency" "api"

  # Track outcome for active learning (async, non-blocking)
  if [[ -f "$HOME/.claude/scripts/outcome-tracker.sh" ]]; then
    "$HOME/.claude/scripts/outcome-tracker.sh" track-cache >/dev/null 2>&1 &
  fi

  # Store in semantic cache (if enabled)
  if is_cache_enabled && is_semantic_cache_enabled 2>/dev/null; then
    semantic_cache_set "$user_prompt" "$content" 2>/dev/null || true
  fi

  # Return response
  echo "$content"
}

# Update prompt cache metrics
update_prompt_cache_metrics() {
  local input_tokens=$1
  local output_tokens=$2
  local cached_tokens=$3

  # Calculate cost savings
  local input_cost_per_1k=$(jq -r '.cost_per_1k_tokens.input' "$CONFIG_FILE" 2>/dev/null || echo "0.003")
  local cached_cost_per_1k=$(jq -r '.cost_per_1k_tokens.cached_input' "$CONFIG_FILE" 2>/dev/null || echo "0.0003")

  local tokens_saved=$cached_tokens
  local cost_saved=$(echo "scale=6; ($input_cost_per_1k - $cached_cost_per_1k) * $tokens_saved / 1000" | bc 2>/dev/null || echo "0")

  # Update metrics file
  local temp_file=$(mktemp)
  jq --arg tokens "$tokens_saved" \
     --arg cost "$cost_saved" \
     --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
    .prompt_cache.tokens_saved += ($tokens | tonumber) |
    .prompt_cache.cost_saved_usd += ($cost | tonumber) |
    .prompt_cache.total_requests += 1 |
    if ($tokens | tonumber) > 0 then
      .prompt_cache.cache_hits += 1
    else
      .prompt_cache.cache_misses += 1
    end |
    .last_updated = $ts
  ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Update performance metrics
update_performance_metrics() {
  local latency=$1
  local type=$2  # "api" or "cached"

  local temp_file=$(mktemp)
  jq --arg latency "$latency" \
     --arg type "$type" \
     --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
    if $type == "api" then
      .performance.avg_latency_ms = (
        (.performance.avg_latency_ms * (.prompt_cache.total_requests - 1) + ($latency | tonumber)) /
        (if .prompt_cache.total_requests > 0 then .prompt_cache.total_requests else 1 end)
      )
    else
      .performance.avg_latency_with_cache_ms = (
        (.performance.avg_latency_with_cache_ms * (.semantic_cache.cache_hits - 1) + ($latency | tonumber)) /
        (if .semantic_cache.cache_hits > 0 then .semantic_cache.cache_hits else 1 end)
      )
    end |
    .performance.latency_reduction_pct = (
      if .performance.avg_latency_ms > 0 then
        (((.performance.avg_latency_ms - .performance.avg_latency_with_cache_ms) / .performance.avg_latency_ms) * 100)
      else 0 end
    ) |
    .last_updated = $ts
  ' "$METRICS_FILE" > "$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# Export function
export -f call_claude_api
