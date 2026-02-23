#!/usr/bin/env bash
# knowledge-graph-builder.sh - Build knowledge graph with relationships
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
GRAPH_FILE="${KNOWLEDGE_DIR}/knowledge-graph.json"
EMBEDDINGS_FILE="${CLAUDE_DATA_DIR}/knowledge-embeddings.json"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions"

# Ensure directories exist
mkdir -p "${KNOWLEDGE_DIR}" "${CLAUDE_DATA_DIR}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Initialize graph structure
initialize_graph() {
    if [[ -f "${GRAPH_FILE}" ]]; then
        log_info "Graph file exists, loading..."
        return 0
    fi

    log_info "Initializing new knowledge graph..."
    cat > "${GRAPH_FILE}" <<'EOF'
{
  "version": "1.0.0",
  "created": "",
  "last_updated": "",
  "nodes": [],
  "edges": [],
  "metadata": {
    "nodes_count": 0,
    "edges_count": 0,
    "clusters": 0,
    "relationship_types": {
      "builds-on": 0,
      "replaces": 0,
      "related-to": 0,
      "prerequisite": 0,
      "alternative": 0,
      "contradicts": 0,
      "example-of": 0,
      "generalizes": 0
    }
  }
}
EOF

    # Set timestamps
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$timestamp" '.created = $ts | .last_updated = $ts' "${GRAPH_FILE}" > "${GRAPH_FILE}.tmp"
    mv "${GRAPH_FILE}.tmp" "${GRAPH_FILE}"

    log_success "Graph initialized"
}

# Add node to graph
add_node() {
    local node_id="$1"
    local node_type="${2:-solution}"
    local tags="$3"
    local confidence="${4:-0.5}"
    local metadata="${5:-{}}"

    # Check if node already exists
    if jq -e --arg id "$node_id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}" &>/dev/null; then
        log_warn "Node $node_id already exists, skipping..."
        return 0
    fi

    log_info "Adding node: $node_id"

    # Parse tags into array
    local tags_array
    if [[ "$tags" == "["* ]]; then
        tags_array="$tags"
    else
        # Convert comma-separated to JSON array
        tags_array=$(echo "$tags" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
    fi

    # Ensure metadata is valid JSON
    if ! echo "$metadata" | jq empty 2>/dev/null; then
        metadata="{}"
    fi

    # Add node
    jq --arg id "$node_id" \
       --arg type "$node_type" \
       --argjson tags "$tags_array" \
       --argjson conf "$confidence" \
       --argjson meta "$metadata" \
       '.nodes += [{
         id: $id,
         type: $type,
         tags: $tags,
         confidence: $conf,
         metadata: $meta,
         created: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
       }] | .metadata.nodes_count += 1' "${GRAPH_FILE}" > "${GRAPH_FILE}.tmp"

    mv "${GRAPH_FILE}.tmp" "${GRAPH_FILE}"
    log_success "Node added: $node_id"
}

# Add edge to graph
add_relationship() {
    local from_id="$1"
    local to_id="$2"
    local rel_type="$3"
    local confidence="${4:-0.5}"
    local reason="${5:-}"

    # Validate relationship type
    local valid_types=("builds-on" "replaces" "related-to" "prerequisite" "alternative" "contradicts" "example-of" "generalizes")
    if [[ ! " ${valid_types[@]} " =~ " ${rel_type} " ]]; then
        log_error "Invalid relationship type: $rel_type"
        return 1
    fi

    # Check if edge already exists
    if jq -e --arg from "$from_id" --arg to "$to_id" --arg type "$rel_type" \
       '.edges[] | select(.from == $from and .to == $to and .type == $type)' "${GRAPH_FILE}" &>/dev/null; then
        log_warn "Relationship already exists: $from_id -> $to_id ($rel_type)"
        return 0
    fi

    log_info "Adding relationship: $from_id -> $to_id ($rel_type)"

    # Add edge
    jq --arg from "$from_id" \
       --arg to "$to_id" \
       --arg type "$rel_type" \
       --argjson conf "$confidence" \
       --arg reason "$reason" \
       '.edges += [{
         from: $from,
         to: $to,
         type: $type,
         confidence: $conf,
         reason: $reason,
         created: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
       }] | .metadata.edges_count += 1 | .metadata.relationship_types[$type] += 1' "${GRAPH_FILE}" > "${GRAPH_FILE}.tmp"

    mv "${GRAPH_FILE}.tmp" "${GRAPH_FILE}"
    log_success "Relationship added"
}

# Calculate semantic similarity between two texts
calculate_similarity() {
    local text1="$1"
    local text2="$2"

    # Simple word-based similarity (Jaccard index)
    # In production, would use embeddings and cosine similarity

    # Convert to lowercase and split into words
    local words1=($(echo "$text1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u))
    local words2=($(echo "$text2" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u))

    # Calculate intersection
    local intersection=0
    for word in "${words1[@]}"; do
        if [[ " ${words2[@]} " =~ " ${word} " ]]; then
            ((intersection++)) || true
        fi
    done

    # Calculate union
    local union=$((${#words1[@]} + ${#words2[@]} - intersection))

    # Calculate Jaccard similarity
    if [[ $union -eq 0 ]]; then
        echo "0.0"
    else
        echo "scale=3; $intersection / $union" | bc
    fi
}

# Calculate tag overlap
calculate_tag_overlap() {
    local tags1="$1"
    local tags2="$2"

    # Parse JSON arrays
    local tags1_array=($(echo "$tags1" | jq -r '.[]'))
    local tags2_array=($(echo "$tags2" | jq -r '.[]'))

    # Calculate intersection
    local intersection=0
    for tag in "${tags1_array[@]}"; do
        if [[ " ${tags2_array[@]} " =~ " ${tag} " ]]; then
            ((intersection++)) || true
        fi
    done

    # Calculate union
    local union=$((${#tags1_array[@]} + ${#tags2_array[@]} - intersection))

    if [[ $union -eq 0 ]]; then
        echo "0.0"
    else
        echo "scale=3; $intersection / $union" | bc
    fi
}

# Detect relationships between two knowledge entries
detect_relationships() {
    local entry_a="$1"
    local entry_b="$2"

    # Extract node IDs
    local id_a=$(echo "$entry_a" | jq -r '.id')
    local id_b=$(echo "$entry_b" | jq -r '.id')

    # Extract timestamps
    local time_a=$(echo "$entry_a" | jq -r '.metadata.timestamp // .created // ""')
    local time_b=$(echo "$entry_b" | jq -r '.metadata.timestamp // .created // ""')

    # Extract content
    local content_a=$(echo "$entry_a" | jq -r '.metadata.problem + " " + .metadata.solution // ""')
    local content_b=$(echo "$entry_b" | jq -r '.metadata.problem + " " + .metadata.solution // ""')

    # Extract tags
    local tags_a=$(echo "$entry_a" | jq -c '.tags // []')
    local tags_b=$(echo "$entry_b" | jq -c '.tags // []')

    # Calculate semantic similarity
    local similarity=$(calculate_similarity "$content_a" "$content_b")

    # Calculate tag overlap
    local tag_overlap=$(calculate_tag_overlap "$tags_a" "$tags_b")

    log_info "Comparing: $id_a vs $id_b"
    log_info "  Semantic similarity: $similarity"
    log_info "  Tag overlap: $tag_overlap"

    # Detect relationship types
    local relationships=()

    # Related-To: High semantic similarity or high tag overlap
    if (( $(echo "$similarity > 0.80" | bc -l) )) || (( $(echo "$tag_overlap > 0.50" | bc -l) )); then
        local confidence=$(echo "scale=3; ($similarity + $tag_overlap) / 2" | bc)
        relationships+=("related-to:$confidence:High semantic similarity ($similarity) and tag overlap ($tag_overlap)")
    fi

    # Builds-On: Check for references and temporal ordering
    if echo "$content_b" | grep -qiE "(build|extend|improv|based on)"; then
        if [[ -n "$time_a" && -n "$time_b" ]]; then
            if [[ "$time_a" < "$time_b" ]]; then
                relationships+=("builds-on:0.75:Entry B references building/extending and is newer")
            fi
        fi
    fi

    # Replaces: Similar problem, different solution, better confidence
    local conf_a=$(echo "$entry_a" | jq -r '.confidence // 0.5')
    local conf_b=$(echo "$entry_b" | jq -r '.confidence // 0.5')

    if (( $(echo "$similarity > 0.85" | bc -l) )); then
        if (( $(echo "$conf_b > $conf_a + 0.15" | bc -l) )); then
            if [[ -n "$time_a" && -n "$time_b" ]] && [[ "$time_a" < "$time_b" ]]; then
                relationships+=("replaces:0.80:Similar problem, significantly better confidence ($conf_b vs $conf_a)")
            fi
        fi
    fi

    # Prerequisite: Check for dependency mentions
    if echo "$content_b" | grep -qiE "(first|require|depend|need).*$(echo "$id_a" | sed 's/_/ /g')"; then
        relationships+=("prerequisite:0.70:Entry B mentions requiring entry A")
    fi

    # Alternative: High similarity but different approaches
    if (( $(echo "$similarity > 0.75" | bc -l) )) && (( $(echo "$tag_overlap < 0.30" | bc -l) )); then
        relationships+=("alternative:0.65:Similar problem but different technical approaches")
    fi

    # Contradicts: Check for contradiction keywords
    if echo "$content_b" | grep -qiE "(instead of|don't use|avoid|better than|rather than)"; then
        if (( $(echo "$similarity > 0.70" | bc -l) )); then
            relationships+=("contradicts:0.60:Entry B suggests avoiding approach in entry A")
        fi
    fi

    # Return detected relationships
    if [[ ${#relationships[@]} -eq 0 ]]; then
        echo "[]"
    else
        # Convert to JSON array
        printf '%s\n' "${relationships[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0) | split(":") | {type: .[0], confidence: (.[1] | tonumber), reason: .[2]})'
    fi
}

# Build graph from knowledge base
build_graph() {
    log_info "Building knowledge graph from existing knowledge base..."

    initialize_graph

    # Find all knowledge entries
    local knowledge_files=()

    # Check for session insights
    if [[ -d "${SESSIONS_DIR}/sessions" ]]; then
        while IFS= read -r -d '' file; do
            knowledge_files+=("$file")
        done < <(find "${SESSIONS_DIR}/sessions" -name "insights.md" -print0 2>/dev/null)
    fi

    log_info "Found ${#knowledge_files[@]} knowledge files"

    if [[ ${#knowledge_files[@]} -eq 0 ]]; then
        log_warn "No knowledge files found. Creating sample data..."
        create_sample_graph
        return 0
    fi

    # Process each file and extract knowledge
    local processed=0
    for file in "${knowledge_files[@]}"; do
        log_info "Processing: $file"

        # Extract session ID from path
        local session_id=$(basename "$(dirname "$file")")

        # Parse insights file (simplified - would need more sophisticated parsing)
        if [[ -f "$file" ]]; then
            # Create a node for this session's knowledge
            local node_id="k_${session_id}_$(date +%Y%m%d)"

            # Extract tags from content (simplified)
            local tags='["general"]'
            if grep -qi "python" "$file"; then
                tags=$(echo "$tags" | jq '. += ["python"]')
            fi
            if grep -qi "javascript\|node" "$file"; then
                tags=$(echo "$tags" | jq '. += ["javascript"]')
            fi
            if grep -qi "api\|rest" "$file"; then
                tags=$(echo "$tags" | jq '. += ["api"]')
            fi

            # Add node
            local metadata=$(jq -n \
                --arg session "$session_id" \
                --arg file "$file" \
                '{session: $session, source_file: $file}')

            add_node "$node_id" "solution" "$tags" "0.75" "$metadata"

            ((processed++))
        fi
    done

    log_success "Processed $processed knowledge entries"

    # Now detect relationships between all nodes
    detect_all_relationships

    # Update graph statistics
    update_graph_stats

    log_success "Knowledge graph built successfully"
}

# Detect relationships between all nodes
detect_all_relationships() {
    log_info "Detecting relationships between nodes..."

    # Get all nodes
    local nodes=$(jq -c '.nodes[]' "${GRAPH_FILE}")
    local node_array=()

    while IFS= read -r node; do
        node_array+=("$node")
    done <<< "$nodes"

    log_info "Analyzing ${#node_array[@]} nodes for relationships..."

    local relationships_found=0

    # Compare each pair of nodes
    for ((i=0; i<${#node_array[@]}; i++)); do
        for ((j=i+1; j<${#node_array[@]}; j++)); do
            local node_a="${node_array[$i]}"
            local node_b="${node_array[$j]}"

            # Detect relationships
            local rels=$(detect_relationships "$node_a" "$node_b")

            # Add detected relationships
            local rel_count=$(echo "$rels" | jq 'length')
            if [[ $rel_count -gt 0 ]]; then
                local id_a=$(echo "$node_a" | jq -r '.id')
                local id_b=$(echo "$node_b" | jq -r '.id')

                # Add each relationship
                echo "$rels" | jq -c '.[]' | while read -r rel; do
                    local type=$(echo "$rel" | jq -r '.type')
                    local conf=$(echo "$rel" | jq -r '.confidence')
                    local reason=$(echo "$rel" | jq -r '.reason')

                    add_relationship "$id_a" "$id_b" "$type" "$conf" "$reason"
                    ((relationships_found++)) || true
                done
            fi
        done

        # Progress indicator
        if (( (i + 1) % 10 == 0 )); then
            log_info "Progress: $((i + 1))/${#node_array[@]} nodes analyzed"
        fi
    done

    log_success "Found $relationships_found relationships"
}

# Update graph statistics
update_graph_stats() {
    log_info "Updating graph statistics..."

    # Update timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg ts "$timestamp" '.last_updated = $ts' "${GRAPH_FILE}" > "${GRAPH_FILE}.tmp"
    mv "${GRAPH_FILE}.tmp" "${GRAPH_FILE}"

    # Calculate clusters (simplified - just count connected components)
    # In production, would use proper graph clustering algorithms

    log_success "Statistics updated"
}

# Get related knowledge
get_related_knowledge() {
    local node_id="$1"
    local rel_type="${2:-all}"

    if [[ "$rel_type" == "all" ]]; then
        jq --arg id "$node_id" \
           '.edges[] | select(.from == $id or .to == $id)' \
           "${GRAPH_FILE}"
    else
        jq --arg id "$node_id" \
           --arg type "$rel_type" \
           '.edges[] | select((.from == $id or .to == $id) and .type == $type)' \
           "${GRAPH_FILE}"
    fi
}

# Find path between two nodes (BFS)
find_knowledge_path() {
    local from_id="$1"
    local to_id="$2"
    local max_depth="${3:-5}"

    log_info "Finding path: $from_id -> $to_id (max depth: $max_depth)"

    # Use jq to perform BFS
    # For simplicity, using a Python helper (would be pure bash/jq in production)
    python3 -c "
import json
import sys
from collections import deque

with open('${GRAPH_FILE}') as f:
    graph = json.load(f)

# Build adjacency list
adj = {}
for edge in graph['edges']:
    if edge['from'] not in adj:
        adj[edge['from']] = []
    adj[edge['from']].append((edge['to'], edge['type']))

    # Add reverse edge for undirected search
    if edge['to'] not in adj:
        adj[edge['to']] = []
    adj[edge['to']].append((edge['from'], edge['type']))

# BFS
from_id = '${from_id}'
to_id = '${to_id}'
max_depth = ${max_depth}

queue = deque([(from_id, [from_id], [])])
visited = {from_id}

found_path = None

while queue:
    node, path, rel_types = queue.popleft()

    if len(path) > max_depth:
        continue

    if node == to_id:
        found_path = (path, rel_types)
        break

    if node in adj:
        for neighbor, rel_type in adj[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, path + [neighbor], rel_types + [rel_type]))

if found_path:
    path, rel_types = found_path
    result = {
        'found': True,
        'path': path,
        'relationship_types': rel_types,
        'length': len(path) - 1
    }
else:
    result = {'found': False}

print(json.dumps(result, indent=2))
" 2>/dev/null || echo '{"found": false, "error": "Python not available"}'
}

# Export graph in different formats
export_graph() {
    local format="${1:-json}"
    local output_file="${2:-}"

    case "$format" in
        json)
            if [[ -n "$output_file" ]]; then
                cp "${GRAPH_FILE}" "$output_file"
                log_success "Graph exported to: $output_file"
            else
                cat "${GRAPH_FILE}"
            fi
            ;;
        dot)
            # Export as Graphviz DOT format
            local output="${output_file:-${KNOWLEDGE_DIR}/knowledge-graph.dot}"

            cat > "$output" <<'EOF'
digraph KnowledgeGraph {
    rankdir=LR;
    node [shape=box, style=rounded];

EOF

            # Add nodes
            jq -r '.nodes[] | "    \"\(.id)\" [label=\"\(.id | split("_")[1])\"];"' "${GRAPH_FILE}" >> "$output"

            echo "" >> "$output"

            # Add edges with colors by type
            jq -r '.edges[] | "    \"\(.from)\" -> \"\(.to)\" [label=\"\(.type)\", color=\"\(if .type == "builds-on" then "blue" elif .type == "replaces" then "red" elif .type == "related-to" then "green" else "gray" end)\"];"' "${GRAPH_FILE}" >> "$output"

            echo "}" >> "$output"

            log_success "DOT graph exported to: $output"
            log_info "View with: dot -Tpng $output -o ${output%.dot}.png"
            ;;
        mermaid)
            # Export as Mermaid format
            local output="${output_file:-${KNOWLEDGE_DIR}/knowledge-graph.mmd}"

            cat > "$output" <<'EOF'
graph TD
EOF

            # Add edges (nodes are implicit in Mermaid)
            jq -r '.edges[] | "    \(.from) -->|\(.type)| \(.to)"' "${GRAPH_FILE}" >> "$output"

            log_success "Mermaid graph exported to: $output"
            ;;
        *)
            log_error "Unknown format: $format"
            return 1
            ;;
    esac
}

# Get graph statistics
get_graph_stats() {
    log_info "Knowledge Graph Statistics:"
    echo ""

    jq -r '
    "Total Nodes: " + (.metadata.nodes_count | tostring),
    "Total Edges: " + (.metadata.edges_count | tostring),
    "",
    "Relationships by Type:",
    (.metadata.relationship_types | to_entries | map("  " + .key + ": " + (.value | tostring)) | join("\n")),
    "",
    "Last Updated: " + .last_updated
    ' "${GRAPH_FILE}"

    echo ""
}

# Create sample graph for testing
create_sample_graph() {
    log_info "Creating sample knowledge graph..."

    initialize_graph

    # Add sample nodes using jq to build metadata
    local meta1=$(jq -n --arg p "User authentication" --arg s "JWT tokens" '{problem: $p, solution: $s}')
    add_node "k_auth_basic_20260115" "solution" '["auth","security","nodejs"]' 0.85 "$meta1"

    local meta2=$(jq -n --arg p "Social login" --arg s "OAuth 2.0" '{problem: $p, solution: $s}')
    add_node "k_auth_oauth_20260201" "solution" '["auth","oauth","security"]' 0.90 "$meta2"

    local meta3=$(jq -n --arg p "Real-time updates" --arg s "Socket.io" '{problem: $p, solution: $s}')
    add_node "k_websocket_realtime_20260205" "solution" '["websocket","realtime","nodejs"]' 0.88 "$meta3"

    local meta4=$(jq -n --arg p "REST API" --arg s "Express.js" '{problem: $p, solution: $s}')
    add_node "k_api_rest_20260110" "solution" '["api","rest","express"]' 0.82 "$meta4"

    local meta5=$(jq -n --arg p "Two-factor authentication" --arg s "TOTP with Speakeasy" '{problem: $p, solution: $s}')
    add_node "k_auth_2fa_20260210" "solution" '["auth","security","2fa"]' 0.92 "$meta5"

    # Add sample relationships
    add_relationship "k_auth_basic_20260115" "k_auth_oauth_20260201" "builds-on" 0.85 "OAuth extends basic authentication"
    add_relationship "k_auth_oauth_20260201" "k_auth_2fa_20260210" "builds-on" 0.80 "2FA enhances OAuth security"
    add_relationship "k_api_rest_20260110" "k_websocket_realtime_20260205" "alternative" 0.70 "Different approaches to client-server communication"
    add_relationship "k_auth_basic_20260115" "k_api_rest_20260110" "prerequisite" 0.75 "API needs authentication"
    add_relationship "k_websocket_realtime_20260205" "k_auth_basic_20260115" "prerequisite" 0.78 "WebSocket needs authentication"

    update_graph_stats
    log_success "Sample graph created with 5 nodes and 5 relationships"
}

# Main command dispatcher
main() {
    case "${1:-build}" in
        build)
            build_graph
            ;;
        add-node)
            add_node "${2:-}" "${3:-solution}" "${4:-[]}" "${5:-0.5}" "${6:-{}}"
            ;;
        add-relationship|add-edge)
            add_relationship "${2:-}" "${3:-}" "${4:-}" "${5:-0.5}" "${6:-}"
            ;;
        detect)
            if [[ -f "$2" && -f "$3" ]]; then
                local entry_a=$(cat "$2")
                local entry_b=$(cat "$3")
                detect_relationships "$entry_a" "$entry_b"
            else
                log_error "Usage: $0 detect <entry_a.json> <entry_b.json>"
                exit 1
            fi
            ;;
        related)
            get_related_knowledge "${2:-}" "${3:-all}"
            ;;
        path)
            find_knowledge_path "${2:-}" "${3:-}" "${4:-5}"
            ;;
        export)
            export_graph "${2:-json}" "${3:-}"
            ;;
        stats)
            get_graph_stats
            ;;
        sample)
            create_sample_graph
            ;;
        init)
            initialize_graph
            ;;
        *)
            echo "Usage: $0 {build|add-node|add-relationship|detect|related|path|export|stats|sample|init}"
            echo ""
            echo "Commands:"
            echo "  build                     - Build graph from knowledge base"
            echo "  add-node <id> [type] [tags] [conf] [metadata]"
            echo "  add-relationship <from> <to> <type> [conf] [reason]"
            echo "  detect <entry_a.json> <entry_b.json>"
            echo "  related <node_id> [type]"
            echo "  path <from_id> <to_id> [max_depth]"
            echo "  export <format> [output]  - Format: json|dot|mermaid"
            echo "  stats                     - Show graph statistics"
            echo "  sample                    - Create sample graph"
            echo "  init                      - Initialize empty graph"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
