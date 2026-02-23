#!/usr/bin/env bash

# dependency-analyzer.sh
# Build call graphs and dependency maps
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_DIR="${HOME}/.claude/indexes"

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    log "ERROR: $*"
    exit 1
}

# Generate unique hash for a directory path
path_hash() {
    local path="$1"
    echo -n "$path" | md5 | cut -c1-16
}

# Get index directory for a codebase
get_index_path() {
    local codebase_path="$1"
    local hash
    hash=$(path_hash "$codebase_path")
    echo "${INDEX_DIR}/${hash}"
}

# ============================================================================
# Code Parsing Functions
# ============================================================================

# Extract imports from Python file
extract_python_imports() {
    local filepath="$1"

    grep -E "^(import|from) " "$filepath" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ ^import[[:space:]]+([a-zA-Z_][a-zA-Z0-9_\.]*) ]]; then
            echo "import:${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^from[[:space:]]+([a-zA-Z_][a-zA-Z0-9_\.]*)[[:space:]]+import ]]; then
            echo "import:${BASH_REMATCH[1]}"
        fi
    done
}

# Extract function calls from Python file
extract_python_calls() {
    local filepath="$1"

    # Simple pattern: function_name(
    grep -oE "[a-zA-Z_][a-zA-Z0-9_]*\(" "$filepath" 2>/dev/null | sed 's/($//' | while read -r func; do
        echo "call:$func"
    done
}

# Extract imports from JavaScript/TypeScript file
extract_js_imports() {
    local filepath="$1"

    # ES6 imports
    grep -E "^import " "$filepath" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ from[[:space:]]+[\'\"]\@?([a-zA-Z0-9_\-\/\.]+) ]]; then
            echo "import:${BASH_REMATCH[1]}"
        fi
    done

    # CommonJS requires
    grep -oE "require\(['\"]([a-zA-Z0-9_\-\/\.]+)['\"]" "$filepath" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ require\([\'\"]\@?([a-zA-Z0-9_\-\/\.]+) ]]; then
            echo "import:${BASH_REMATCH[1]}"
        fi
    done
}

# Extract function calls from JavaScript/TypeScript file
extract_js_calls() {
    local filepath="$1"

    # Function calls: name(
    grep -oE "[a-zA-Z_][a-zA-Z0-9_]*\(" "$filepath" 2>/dev/null | sed 's/($//' | while read -r func; do
        echo "call:$func"
    done
}

# Extract source statements from Shell script
extract_shell_sources() {
    local filepath="$1"

    grep -E "^(source|\.) " "$filepath" 2>/dev/null | while read -r line; do
        if [[ "$line" =~ (source|\.)[[:space:]]+([^[:space:]]+) ]]; then
            echo "import:${BASH_REMATCH[2]}"
        fi
    done
}

# Extract function calls from Shell script
extract_shell_calls() {
    local filepath="$1"

    # Function calls (simpler than JS/Python)
    grep -oE "[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(" "$filepath" 2>/dev/null | sed 's/[[:space:]]*($//' | while read -r func; do
        echo "call:$func"
    done
}

# ============================================================================
# Dependency Analysis Functions
# ============================================================================

# Analyze dependencies for a codebase
analyze_dependencies() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    log "Analyzing dependencies for: $codebase_path"

    local index_path
    index_path=$(get_index_path "$codebase_path")

    # Check if index exists
    if [[ ! -f "${index_path}/metadata.json" ]]; then
        error "Index not found. Run codebase-indexer.sh first"
    fi

    local embeddings_file="${index_path}/embeddings.jsonl"
    local graph_file="${index_path}/dependency_graph.json"

    # Initialize graph structure
    local nodes_temp
    local edges_temp
    nodes_temp=$(mktemp)
    edges_temp=$(mktemp)

    echo "[]" > "$nodes_temp"
    echo "[]" > "$edges_temp"

    # Get all unique files from embeddings
    local files
    files=$(jq -r '.metadata.file' "$embeddings_file" | sort -u)

    log "Analyzing $(echo "$files" | wc -l | tr -d ' ') files..."

    # Build nodes from definitions
    jq -s '
        map({
            id: "\(.metadata.file):\(.name)",
            name: .name,
            type: .type,
            file: .metadata.file,
            line: .metadata.line
        }) | unique_by(.id)
    ' "$embeddings_file" > "$nodes_temp"

    # Analyze each file for dependencies
    local processed=0
    while IFS= read -r file; do
        [[ ! -f "$file" ]] && continue

        local ext="${file##*.}"

        # Extract imports and calls based on file type
        case "$ext" in
            py)
                extract_python_imports "$file" | while IFS= read -r imp; do
                    [[ -z "$imp" ]] && continue
                    local module="${imp#import:}"
                    # Add import edge
                    jq --arg from "$file" --arg to "$module" --arg type "import" \
                        '. += [{from: $from, to: $to, type: $type}]' \
                        "$edges_temp" > "${edges_temp}.tmp"
                    mv "${edges_temp}.tmp" "$edges_temp"
                done

                extract_python_calls "$file" | while IFS= read -r call; do
                    [[ -z "$call" ]] && continue
                    local func="${call#call:}"
                    # Try to find function definition in nodes
                    local target
                    target=$(jq -r --arg name "$func" \
                        '.[] | select(.name == $name and .type == "function") | .id' \
                        "$nodes_temp" | head -1)
                    if [[ -n "$target" ]]; then
                        jq --arg from "$file" --arg to "$target" --arg type "call" \
                            '. += [{from: $from, to: $to, type: $type}]' \
                            "$edges_temp" > "${edges_temp}.tmp"
                        mv "${edges_temp}.tmp" "$edges_temp"
                    fi
                done
                ;;
            js|ts|jsx|tsx)
                extract_js_imports "$file" | while IFS= read -r imp; do
                    [[ -z "$imp" ]] && continue
                    local module="${imp#import:}"
                    jq --arg from "$file" --arg to "$module" --arg type "import" \
                        '. += [{from: $from, to: $to, type: $type}]' \
                        "$edges_temp" > "${edges_temp}.tmp"
                    mv "${edges_temp}.tmp" "$edges_temp"
                done

                extract_js_calls "$file" | while IFS= read -r call; do
                    [[ -z "$call" ]] && continue
                    local func="${call#call:}"
                    local target
                    target=$(jq -r --arg name "$func" \
                        '.[] | select(.name == $name and .type == "function") | .id' \
                        "$nodes_temp" | head -1)
                    if [[ -n "$target" ]]; then
                        jq --arg from "$file" --arg to "$target" --arg type "call" \
                            '. += [{from: $from, to: $to, type: $type}]' \
                            "$edges_temp" > "${edges_temp}.tmp"
                        mv "${edges_temp}.tmp" "$edges_temp"
                    fi
                done
                ;;
            sh|bash|zsh)
                extract_shell_sources "$file" | while IFS= read -r imp; do
                    [[ -z "$imp" ]] && continue
                    local module="${imp#import:}"
                    jq --arg from "$file" --arg to "$module" --arg type "import" \
                        '. += [{from: $from, to: $to, type: $type}]' \
                        "$edges_temp" > "${edges_temp}.tmp"
                    mv "${edges_temp}.tmp" "$edges_temp"
                done

                extract_shell_calls "$file" | while IFS= read -r call; do
                    [[ -z "$call" ]] && continue
                    local func="${call#call:}"
                    local target
                    target=$(jq -r --arg name "$func" \
                        '.[] | select(.name == $name and .type == "function") | .id' \
                        "$nodes_temp" | head -1)
                    if [[ -n "$target" ]]; then
                        jq --arg from "$file" --arg to "$target" --arg type "call" \
                            '. += [{from: $from, to: $to, type: $type}]' \
                            "$edges_temp" > "${edges_temp}.tmp"
                        mv "${edges_temp}.tmp" "$edges_temp"
                    fi
                done
                ;;
        esac

        ((processed++))
        if ((processed % 10 == 0)); then
            log "Processed $processed files..."
        fi

    done <<< "$files"

    # Calculate metrics
    local total_nodes
    local total_edges
    local circular_deps
    total_nodes=$(jq 'length' "$nodes_temp")
    total_edges=$(jq 'length' "$edges_temp")

    # Detect circular dependencies (simplified)
    circular_deps=$(detect_circular_deps "$nodes_temp" "$edges_temp")

    # Calculate coupling (average edges per node)
    local coupling
    if [[ $total_nodes -gt 0 ]]; then
        coupling=$(echo "scale=4; $total_edges / $total_nodes" | bc)
    else
        coupling="0"
    fi

    # Build final graph
    jq -n \
        --slurpfile nodes "$nodes_temp" \
        --slurpfile edges "$edges_temp" \
        --argjson total_functions "$total_nodes" \
        --arg coupling "$coupling" \
        --argjson circular "$circular_deps" \
        '{
            nodes: $nodes[0],
            edges: $edges[0],
            metrics: {
                total_functions: $total_functions,
                total_dependencies: ($edges[0] | length),
                coupling: ($coupling | tonumber),
                circular_deps: $circular
            },
            generated_at: (now | todateiso8601)
        }' > "$graph_file"

    # Cleanup
    rm -f "$nodes_temp" "$edges_temp"

    log "Dependency analysis complete"
    log "Graph saved to: $graph_file"
    log "Nodes: $total_nodes, Edges: $total_edges"
}

# Detect circular dependencies (simplified DFS-based detection)
detect_circular_deps() {
    local nodes_file="$1"
    local edges_file="$2"

    # For now, return empty array (full cycle detection is complex)
    # TODO: Implement proper cycle detection algorithm
    echo "[]"
}

# ============================================================================
# Graph Query Functions
# ============================================================================

# Get call graph for a function (who calls this?)
get_call_graph() {
    local codebase_path="$1"
    local function_name="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Finding callers of: $function_name"

    # Find all edges pointing to this function
    jq --arg name "$function_name" '
        {
            function: $name,
            callers: [
                .edges[] |
                select(.to | contains($name)) |
                {from: .from, type: .type}
            ]
        }
    ' "$graph_file"
}

# Get callees (what does this function call?)
get_callees() {
    local codebase_path="$1"
    local function_name="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Finding callees of: $function_name"

    # Find all edges from this function
    jq --arg name "$function_name" '
        {
            function: $name,
            callees: [
                .edges[] |
                select(.from | contains($name)) |
                {to: .to, type: .type}
            ]
        }
    ' "$graph_file"
}

# Find entry points (functions with no callers)
find_entry_points() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Finding entry points..."

    # Find nodes with no incoming edges
    jq '
        .nodes |
        map(select(.type == "function")) |
        map(.id) as $all_nodes |
        ([ .edges[] | select(.type == "call") | .to ] | unique) as $called_nodes |
        $all_nodes - $called_nodes
    ' "$graph_file"
}

# Find leaf functions (functions that call nothing)
find_leaf_functions() {
    local codebase_path="$1"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Finding leaf functions..."

    # Find nodes with no outgoing edges
    jq '
        .nodes |
        map(select(.type == "function")) |
        map(.id) as $all_nodes |
        ([ .edges[] | select(.type == "call") | .from ] | unique) as $calling_nodes |
        $all_nodes - $calling_nodes
    ' "$graph_file"
}

# Find critical path between two functions
find_critical_path() {
    local codebase_path="$1"
    local entry="$2"
    local exit="$3"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Finding path from $entry to $exit..."

    # Simple BFS path finding (implemented in jq)
    jq --arg entry "$entry" --arg exit "$exit" '
        # This is a placeholder - proper BFS implementation needed
        {
            entry: $entry,
            exit: $exit,
            path: ["Path finding not yet implemented"],
            distance: 0
        }
    ' "$graph_file"
}

# ============================================================================
# Export Functions
# ============================================================================

# Export graph to Graphviz DOT format
export_graph_dot() {
    local codebase_path="$1"
    local output_file="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Exporting graph to DOT format: $output_file"

    {
        echo "digraph dependencies {"
        echo "  rankdir=LR;"
        echo "  node [shape=box];"
        echo ""

        # Export nodes
        jq -r '.nodes[] | "  \"\(.id)\" [label=\"\(.name)\"];"' "$graph_file"

        echo ""

        # Export edges
        jq -r '.edges[] | "  \"\(.from)\" -> \"\(.to)\" [label=\"\(.type)\"];"' "$graph_file"

        echo "}"
    } > "$output_file"

    log "DOT file saved: $output_file"
    log "To generate image: dot -Tpng $output_file -o graph.png"
}

# Export graph to JSON (formatted)
export_graph_json() {
    local codebase_path="$1"
    local output_file="$2"
    codebase_path=$(cd "$codebase_path" && pwd)

    local index_path
    index_path=$(get_index_path "$codebase_path")
    local graph_file="${index_path}/dependency_graph.json"

    if [[ ! -f "$graph_file" ]]; then
        error "Dependency graph not found. Run analyze_dependencies first"
    fi

    log "Exporting graph to JSON: $output_file"
    jq '.' "$graph_file" > "$output_file"
    log "JSON file saved: $output_file"
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> <codebase> [options]

Commands:
    analyze <codebase>              Build dependency graph
    callers <codebase> <function>   Find who calls this function
    callees <codebase> <function>   Find what this function calls
    entry-points <codebase>         Find entry point functions
    leaf-functions <codebase>       Find leaf functions
    path <codebase> <from> <to>     Find path between functions
    export-dot <codebase> <file>    Export to Graphviz DOT
    export-json <codebase> <file>   Export to JSON

Options:
    -h, --help                      Show this help message

Examples:
    # Build dependency graph
    $(basename "$0") analyze ~/my-project

    # Find who calls a function
    $(basename "$0") callers ~/my-project "authenticate"

    # Find what a function calls
    $(basename "$0") callees ~/my-project "authenticate"

    # Find entry points
    $(basename "$0") entry-points ~/my-project

    # Export to DOT format
    $(basename "$0") export-dot ~/my-project graph.dot

EOF
}

main() {
    # Parse command
    case "${1:-}" in
        analyze)
            [[ $# -ge 2 ]] || error "Usage: analyze <codebase>"
            analyze_dependencies "$2"
            ;;
        callers)
            [[ $# -ge 3 ]] || error "Usage: callers <codebase> <function>"
            get_call_graph "$2" "$3"
            ;;
        callees)
            [[ $# -ge 3 ]] || error "Usage: callees <codebase> <function>"
            get_callees "$2" "$3"
            ;;
        entry-points)
            [[ $# -ge 2 ]] || error "Usage: entry-points <codebase>"
            find_entry_points "$2"
            ;;
        leaf-functions)
            [[ $# -ge 2 ]] || error "Usage: leaf-functions <codebase>"
            find_leaf_functions "$2"
            ;;
        path)
            [[ $# -ge 4 ]] || error "Usage: path <codebase> <from> <to>"
            find_critical_path "$2" "$3" "$4"
            ;;
        export-dot)
            [[ $# -ge 3 ]] || error "Usage: export-dot <codebase> <file>"
            export_graph_dot "$2" "$3"
            ;;
        export-json)
            [[ $# -ge 3 ]] || error "Usage: export-json <codebase> <file>"
            export_graph_json "$2" "$3"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
