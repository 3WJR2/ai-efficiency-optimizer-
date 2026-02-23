#!/usr/bin/env bash

# code-embedder.sh
# Generate semantic embeddings for code files
# Part of Deep Codebase Understanding System

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
CACHE_DIR="${HOME}/.claude/cache/embeddings"

# Supported file types
SUPPORTED_EXTENSIONS=(
    "py" "js" "ts" "jsx" "tsx" "sh" "bash" "zsh"
    "rb" "java" "go" "rs" "c" "cpp" "h" "hpp"
    "php" "swift" "kt" "scala" "clj" "el" "vim"
)

# Embedding methods
EMBEDDING_METHOD="${EMBEDDING_METHOD:-tfidf}"  # tfidf, openai, local

# Initialize
mkdir -p "$CACHE_DIR"

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

# Check if file type is supported
is_supported_file() {
    local filepath="$1"
    local ext="${filepath##*.}"

    for supported in "${SUPPORTED_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# Get file type from extension
get_file_type() {
    local filepath="$1"
    local ext="${filepath##*.}"

    case "$ext" in
        py) echo "python" ;;
        js|jsx) echo "javascript" ;;
        ts|tsx) echo "typescript" ;;
        sh|bash|zsh) echo "shell" ;;
        rb) echo "ruby" ;;
        java) echo "java" ;;
        go) echo "go" ;;
        rs) echo "rust" ;;
        c|cpp|h|hpp) echo "c/c++" ;;
        php) echo "php" ;;
        swift) echo "swift" ;;
        kt) echo "kotlin" ;;
        scala) echo "scala" ;;
        clj) echo "clojure" ;;
        *) echo "unknown" ;;
    esac
}

# ============================================================================
# Code Parsing Functions
# ============================================================================

# Extract function/class definitions from Python
extract_python_definitions() {
    local filepath="$1"
    local line_num=0
    local in_function=false
    local in_class=false
    local current_def=""
    local current_type=""
    local current_name=""
    local start_line=0

    while IFS= read -r line; do
        ((line_num++))

        # Detect function definitions
        if [[ "$line" =~ ^[[:space:]]*def[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            if [[ -n "$current_def" ]]; then
                emit_definition "$filepath" "$start_line" "$current_type" "$current_name" "$current_def"
            fi
            current_type="function"
            current_name="${BASH_REMATCH[1]}"
            current_def="$line"
            start_line=$line_num
            in_function=true

        # Detect class definitions
        elif [[ "$line" =~ ^[[:space:]]*class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            if [[ -n "$current_def" ]]; then
                emit_definition "$filepath" "$start_line" "$current_type" "$current_name" "$current_def"
            fi
            current_type="class"
            current_name="${BASH_REMATCH[1]}"
            current_def="$line"
            start_line=$line_num
            in_class=true

        # Continue collecting definition
        elif [[ "$in_function" == "true" || "$in_class" == "true" ]]; then
            # End of definition (non-indented line that's not blank or comment)
            if [[ ! "$line" =~ ^[[:space:]] ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                emit_definition "$filepath" "$start_line" "$current_type" "$current_name" "$current_def"
                current_def=""
                current_type=""
                current_name=""
                in_function=false
                in_class=false
            else
                current_def+=$'\n'"$line"
            fi
        fi
    done < "$filepath"

    # Emit last definition if exists
    if [[ -n "$current_def" ]]; then
        emit_definition "$filepath" "$start_line" "$current_type" "$current_name" "$current_def"
    fi
}

# Extract function/class definitions from JavaScript/TypeScript
extract_js_definitions() {
    local filepath="$1"
    local line_num=0
    local brace_count=0
    local in_function=false
    local current_def=""
    local current_type=""
    local current_name=""
    local start_line=0

    while IFS= read -r line; do
        ((line_num++))

        # Detect function declarations
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]] || \
           [[ "$line" =~ ^[[:space:]]*(const|let|var)[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(async[[:space:]]+)?.*=\> ]]; then
            current_type="function"
            if [[ -n "${BASH_REMATCH[3]}" ]]; then
                current_name="${BASH_REMATCH[3]}"
            else
                current_name="${BASH_REMATCH[2]}"
            fi
            current_def="$line"
            start_line=$line_num
            in_function=true
            brace_count=$(echo "$line" | tr -cd '{' | wc -c)
            brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))

        # Detect class declarations
        elif [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?class[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            current_type="class"
            current_name="${BASH_REMATCH[2]}"
            current_def="$line"
            start_line=$line_num
            in_function=true
            brace_count=$(echo "$line" | tr -cd '{' | wc -c)
            brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))

        # Continue collecting definition
        elif [[ "$in_function" == "true" ]]; then
            current_def+=$'\n'"$line"
            brace_count=$((brace_count + $(echo "$line" | tr -cd '{' | wc -c)))
            brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))

            # End of definition
            if [[ $brace_count -eq 0 ]]; then
                emit_definition "$filepath" "$start_line" "$current_type" "$current_name" "$current_def"
                current_def=""
                current_type=""
                current_name=""
                in_function=false
            fi
        fi
    done < "$filepath"
}

# Extract function definitions from Shell scripts
extract_shell_definitions() {
    local filepath="$1"
    local line_num=0
    local in_function=false
    local current_def=""
    local current_name=""
    local start_line=0

    while IFS= read -r line; do
        ((line_num++))

        # Detect function declarations (both styles)
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(\)[[:space:]]*\{ ]] || \
           [[ "$line" =~ ^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
            if [[ -n "$current_def" ]]; then
                emit_definition "$filepath" "$start_line" "function" "$current_name" "$current_def"
            fi
            if [[ -n "${BASH_REMATCH[1]}" ]]; then
                current_name="${BASH_REMATCH[1]}"
            else
                current_name="${BASH_REMATCH[2]}"
            fi
            current_def="$line"
            start_line=$line_num
            in_function=true

        # Continue collecting definition
        elif [[ "$in_function" == "true" ]]; then
            current_def+=$'\n'"$line"

            # End of function (closing brace at start of line)
            if [[ "$line" =~ ^[[:space:]]*\} ]]; then
                emit_definition "$filepath" "$start_line" "function" "$current_name" "$current_def"
                current_def=""
                current_name=""
                in_function=false
            fi
        fi
    done < "$filepath"

    # Emit last definition if exists
    if [[ -n "$current_def" ]]; then
        emit_definition "$filepath" "$start_line" "function" "$current_name" "$current_def"
    fi
}

# Extract definitions based on file type
extract_definitions() {
    local filepath="$1"
    local filetype
    filetype=$(get_file_type "$filepath")

    case "$filetype" in
        python)
            extract_python_definitions "$filepath"
            ;;
        javascript|typescript)
            extract_js_definitions "$filepath"
            ;;
        shell)
            extract_shell_definitions "$filepath"
            ;;
        *)
            # For unsupported types, treat whole file as one chunk
            emit_definition "$filepath" 1 "file" "$(basename "$filepath")" "$(cat "$filepath")"
            ;;
    esac
}

# Emit a code definition as JSON
emit_definition() {
    local filepath="$1"
    local line_num="$2"
    local type="$3"
    local name="$4"
    local content="$5"

    # Skip empty definitions
    [[ -z "$content" ]] && return

    # Generate embedding
    local embedding
    embedding=$(generate_embedding "$content")

    # Extract metadata
    local loc
    loc=$(echo "$content" | wc -l | tr -d ' ')

    # Escape JSON strings
    local escaped_content
    escaped_content=$(echo "$content" | jq -Rs .)

    # Output JSONL
    jq -nc \
        --arg path "${filepath}:${line_num}" \
        --arg type "$type" \
        --arg name "$name" \
        --argjson content "$escaped_content" \
        --arg embedding "$embedding" \
        --argjson loc "$loc" \
        '{
            path: $path,
            type: $type,
            name: $name,
            content: $content,
            embedding: ($embedding | split(",") | map(tonumber)),
            metadata: {
                loc: $loc,
                file: ($path | split(":")[0]),
                line: ($path | split(":")[1] | tonumber)
            }
        }'
}

# ============================================================================
# Embedding Generation
# ============================================================================

# Generate embedding using TF-IDF (simple fallback)
generate_embedding_tfidf() {
    local text="$1"

    # Simple TF-IDF: word frequency vector (100 dimensions)
    # Use common code terms as vocabulary
    local vocab=(
        "function" "class" "method" "return" "if" "else" "for" "while"
        "try" "catch" "import" "export" "const" "let" "var" "async"
        "await" "new" "this" "self" "def" "lambda" "map" "filter"
        "reduce" "array" "object" "string" "number" "boolean" "null"
        "undefined" "true" "false" "public" "private" "protected" "static"
        "interface" "type" "struct" "enum" "trait" "impl" "fn" "let"
        "mut" "ref" "match" "case" "switch" "break" "continue" "goto"
        "package" "module" "namespace" "using" "include" "require" "from"
        "as" "is" "in" "of" "extends" "implements" "throws" "raise"
        "assert" "test" "describe" "it" "expect" "should" "mock" "stub"
        "get" "set" "post" "put" "delete" "patch" "head" "options"
        "http" "https" "api" "rest" "json" "xml" "html" "css"
        "database" "query" "select" "insert" "update" "delete" "join"
        "auth" "login" "logout" "session" "token" "jwt" "oauth" "user"
    )

    local vector=()
    local total_words=0

    # Count word occurrences (case-insensitive)
    local text_lower
    text_lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    for word in "${vocab[@]}"; do
        local count
        count=$(echo "$text_lower" | grep -o "\b$word\b" | wc -l | tr -d ' ')
        vector+=("$count")
        total_words=$((total_words + count))
    done

    # Normalize to unit vector (or close enough for our purposes)
    if [[ $total_words -gt 0 ]]; then
        local normalized=()
        for val in "${vector[@]}"; do
            # Simple normalization: divide by sqrt(sum of squares)
            # For performance, just divide by total
            normalized+=("$(echo "scale=4; $val / $total_words" | bc)")
        done
        vector=("${normalized[@]}")
    fi

    # Return as comma-separated string
    (IFS=,; echo "${vector[*]}")
}

# Generate embedding (dispatch to appropriate method)
generate_embedding() {
    local text="$1"

    case "$EMBEDDING_METHOD" in
        tfidf)
            generate_embedding_tfidf "$text"
            ;;
        openai)
            generate_embedding_openai "$text"
            ;;
        local)
            generate_embedding_local "$text"
            ;;
        *)
            error "Unknown embedding method: $EMBEDDING_METHOD"
            ;;
    esac
}

# Generate embedding using OpenAI API (future implementation)
generate_embedding_openai() {
    local text="$1"
    # TODO: Implement OpenAI embeddings API call
    # For now, fallback to TF-IDF
    generate_embedding_tfidf "$text"
}

# Generate embedding using local model (future implementation)
generate_embedding_local() {
    local text="$1"
    # TODO: Implement local sentence-transformers
    # For now, fallback to TF-IDF
    generate_embedding_tfidf "$text"
}

# ============================================================================
# Main API Functions
# ============================================================================

# Embed a single file
embed_file() {
    local filepath="$1"

    # Check if file exists
    [[ -f "$filepath" ]] || error "File not found: $filepath"

    # Check if supported
    is_supported_file "$filepath" || {
        log "Skipping unsupported file: $filepath"
        return 0
    }

    # Extract and emit definitions
    extract_definitions "$filepath"
}

# Embed a directory recursively
embed_directory() {
    local dirpath="$1"
    local output_file="${2:-/dev/stdout}"

    # Check if directory exists
    [[ -d "$dirpath" ]] || error "Directory not found: $dirpath"

    log "Embedding directory: $dirpath"

    # Find all supported files
    local pattern=""
    for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
        pattern="$pattern -o -name *.$ext"
    done
    pattern="${pattern# -o }"  # Remove leading " -o "

    local file_count=0
    local output_temp
    output_temp=$(mktemp)

    # Process each file
    while IFS= read -r file; do
        # Skip excluded directories
        if echo "$file" | grep -qE '/(node_modules|venv|\.git|build|dist|target|\.next|\.cache)/'; then
            continue
        fi

        embed_file "$file" >> "$output_temp" 2>/dev/null || true
        ((file_count++))

        if ((file_count % 10 == 0)); then
            log "Processed $file_count files..."
        fi
    done < <(find "$dirpath" -type f \( $pattern \) 2>/dev/null)

    # Move to final output
    if [[ "$output_file" != "/dev/stdout" ]]; then
        mv "$output_temp" "$output_file"
        log "Embeddings saved to: $output_file"
    else
        cat "$output_temp"
        rm "$output_temp"
    fi

    log "Completed: $file_count files embedded"
}

# Chunk large code files into semantic pieces
chunk_code() {
    local content="$1"
    local max_lines="${2:-100}"

    # Split by lines and output chunks
    local line_count=0
    local chunk=""

    while IFS= read -r line; do
        chunk+="$line"$'\n'
        ((line_count++))

        if [[ $line_count -ge $max_lines ]]; then
            echo "$chunk"
            chunk=""
            line_count=0
        fi
    done <<< "$content"

    # Output remaining chunk
    [[ -n "$chunk" ]] && echo "$chunk"
}

# ============================================================================
# CLI Interface
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
    file <filepath>              Embed a single file
    directory <dirpath> [output] Embed directory recursively
    chunk <filepath> [max_lines] Chunk file into semantic pieces

Options:
    -m, --method <method>        Embedding method: tfidf (default), openai, local
    -h, --help                   Show this help message

Environment Variables:
    EMBEDDING_METHOD             Set embedding method (default: tfidf)

Examples:
    # Embed single file
    $(basename "$0") file app.py

    # Embed entire directory
    $(basename "$0") directory ~/my-project embeddings.jsonl

    # Chunk large file
    $(basename "$0") chunk large_file.py 50

EOF
}

main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--method)
                EMBEDDING_METHOD="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            file|directory|chunk)
                local command="$1"
                shift
                break
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Execute command
    case "${command:-}" in
        file)
            [[ $# -ge 1 ]] || error "Missing filepath argument"
            embed_file "$1"
            ;;
        directory)
            [[ $# -ge 1 ]] || error "Missing dirpath argument"
            embed_directory "$1" "${2:-/dev/stdout}"
            ;;
        chunk)
            [[ $# -ge 1 ]] || error "Missing filepath argument"
            [[ -f "$1" ]] || error "File not found: $1"
            chunk_code "$(cat "$1")" "${2:-100}"
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
