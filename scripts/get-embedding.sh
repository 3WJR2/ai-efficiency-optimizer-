#!/usr/bin/env bash
# get-embedding.sh - Generate embeddings for semantic similarity
# Part of Phase 1A Caching Infrastructure

set -euo pipefail

CONFIG_FILE="$HOME/.claude/data/cache-config.json"
EMBEDDING_CACHE="$HOME/.claude/cache/embeddings"

mkdir -p "$EMBEDDING_CACHE"

# Get embedding for text
# Usage: get_embedding "text to embed"
# Returns: JSON array of embedding vector
get_embedding() {
  local text="$1"
  local provider=$(jq -r '.embedding_provider // "anthropic"' "$CONFIG_FILE" 2>/dev/null || echo "fallback")

  # Generate hash for cache key
  local text_hash=$(echo -n "$text" | shasum -a 256 | cut -d' ' -f1)
  local cache_file="$EMBEDDING_CACHE/$text_hash.json"

  # Check cache first
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
    return 0
  fi

  # Generate embedding using fallback method
  generate_fallback_embedding "$text" | tee "$cache_file"
}

# Generate semantic embedding using sentence-transformers
# Falls back to hash-based if model unavailable
generate_fallback_embedding() {
  local text="$1"
  local venv_python="$HOME/.claude/venv/embeddings/bin/python3"

  # Try sentence-transformers first (real semantic embeddings)
  if [[ -f "$venv_python" ]]; then
    "$venv_python" -c "
from sentence_transformers import SentenceTransformer
import json
import sys

try:
    # Load model (cached after first use)
    model = SentenceTransformer('all-MiniLM-L6-v2', device='cpu')

    # Generate embedding
    text = '''$text'''
    embedding = model.encode(text, show_progress_bar=False)

    # Output as JSON
    print(json.dumps(embedding.tolist()))
except Exception as e:
    # Fall back to hash if model fails
    import hashlib
    hash_obj = hashlib.sha256(text.encode())
    hash_bytes = hash_obj.digest()
    embedding = [float(b) / 255.0 for b in hash_bytes[:32]]
    magnitude = sum(x*x for x in embedding) ** 0.5
    normalized = [x/magnitude for x in embedding] if magnitude > 0 else embedding
    print(json.dumps(normalized))
    sys.exit(0)
" 2>/dev/null
  elif command -v python3 &> /dev/null; then
    # Fallback: hash-based embedding
    python3 -c "
import hashlib
import json

text = '''$text'''
hash_obj = hashlib.sha256(text.encode())
hash_bytes = hash_obj.digest()
embedding = [float(b) / 255.0 for b in hash_bytes[:32]]
magnitude = sum(x*x for x in embedding) ** 0.5
if magnitude > 0:
    normalized = [x/magnitude for x in embedding]
else:
    normalized = embedding
print(json.dumps(normalized))
" 2>/dev/null || echo "[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]"
  else
    # Last resort: static vector
    echo "[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]"
  fi
}

# Calculate cosine similarity between two embedding vectors
# Usage: cosine_similarity "vector1_json" "vector2_json"
cosine_similarity() {
  local vec1="$1"
  local vec2="$2"

  if command -v python3 &> /dev/null; then
    python3 -c "
import json
import math

v1 = json.loads('''$vec1''')
v2 = json.loads('''$vec2''')

dot_product = sum(a*b for a, b in zip(v1, v2))
mag1 = math.sqrt(sum(a*a for a in v1))
mag2 = math.sqrt(sum(b*b for b in v2))

similarity = dot_product / (mag1 * mag2) if mag1 > 0 and mag2 > 0 else 0.0
print(f'{similarity:.4f}')
" 2>/dev/null || echo "0.5"
  else
    echo "0.5"
  fi
}

# Export functions
export -f get_embedding
export -f cosine_similarity
