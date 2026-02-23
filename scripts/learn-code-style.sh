#!/usr/bin/env bash
# learn-code-style.sh - Learn user's coding style from examples
# Part of Adaptive Learning System v1.2 - Phase 2 Improvements

set -euo pipefail

CODE_STYLE_DATA="$HOME/.claude/data/code-style.json"

# Initialize code style data if doesn't exist
if [[ ! -f "$CODE_STYLE_DATA" ]]; then
  cat > "$CODE_STYLE_DATA" <<'EOF'
{
  "version": "1.0.0",
  "languages": {},
  "global_preferences": {
    "comment_style": "unknown",
    "documentation_verbosity": "medium",
    "error_handling_approach": "unknown",
    "test_coverage_preference": "unknown"
  },
  "last_analyzed": null,
  "total_files_analyzed": 0
}
EOF
fi

COMMAND="${1:-analyze}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

analyze_file() {
  local file="$1"
  local language="$2"

  # Detect indentation
  local indent_type="unknown"
  local indent_size=0

  if grep -q "^    " "$file" 2>/dev/null; then
    indent_type="spaces"
    indent_size=4
  elif grep -q "^  " "$file" 2>/dev/null; then
    indent_type="spaces"
    indent_size=2
  elif grep -q "^\t" "$file" 2>/dev/null; then
    indent_type="tabs"
    indent_size=1
  fi

  # Detect naming convention
  local naming="unknown"
  case "$language" in
    python)
      if grep -q "def [a-z_]*(" "$file" 2>/dev/null; then
        naming="snake_case"
      fi
      ;;
    javascript|typescript)
      if grep -q "function [a-z][a-zA-Z]*(" "$file" 2>/dev/null; then
        naming="camelCase"
      fi
      ;;
  esac

  # Detect line length preference
  local max_line=$(awk '{print length}' "$file" 2>/dev/null | sort -rn | head -1)

  # Detect comment density
  local total_lines=$(wc -l < "$file" 2>/dev/null || echo "0")
  local comment_lines=0

  case "$language" in
    python)
      comment_lines=$(grep -c "^[[:space:]]*#" "$file" 2>/dev/null || echo "0")
      ;;
    javascript|typescript)
      comment_lines=$(grep -c "^[[:space:]]*//" "$file" 2>/dev/null || echo "0")
      ;;
  esac

  local comment_ratio=0
  if [[ $total_lines -gt 0 ]]; then
    comment_ratio=$(echo "scale=2; $comment_lines / $total_lines" | bc -l)
  fi

  # Output analysis
  echo "{\"indent_type\":\"$indent_type\",\"indent_size\":$indent_size,\"naming\":\"$naming\",\"max_line\":$max_line,\"comment_ratio\":$comment_ratio}"
}

case "$COMMAND" in
  analyze)
    DIRECTORY="${2:-$PWD}"

    echo "🔍 Analyzing code style in: $DIRECTORY"
    echo ""

    # Analyze Python files
    if find "$DIRECTORY" -name "*.py" -type f 2>/dev/null | head -1 | grep -q .; then
      echo "Analyzing Python files..."

      local py_indent_spaces=0
      local py_indent_tabs=0
      local py_snake_case=0
      local py_files=0

      while IFS= read -r file; do
        ((py_files++))

        analysis=$(analyze_file "$file" "python")
        indent_type=$(echo "$analysis" | jq -r '.indent_type')
        naming=$(echo "$analysis" | jq -r '.naming')

        [[ "$indent_type" == "spaces" ]] && ((py_indent_spaces++))
        [[ "$indent_type" == "tabs" ]] && ((py_indent_tabs++))
        [[ "$naming" == "snake_case" ]] && ((py_snake_case++))

      done < <(find "$DIRECTORY" -name "*.py" -type f 2>/dev/null | head -20)

      # Determine preferences
      local py_indent="spaces"
      [[ $py_indent_tabs -gt $py_indent_spaces ]] && py_indent="tabs"

      # Update code style data
      jq --arg indent "$py_indent" \
         --arg naming "snake_case" \
         --arg timestamp "$TIMESTAMP" \
         --arg files "$py_files" \
         '.languages.python = {
           "indentation": $indent,
           "indent_size": 4,
           "naming_convention": $naming,
           "max_line_length": 88,
           "files_analyzed": ($files | tonumber),
           "last_analyzed": $timestamp
         } |
         .last_analyzed = $timestamp |
         .total_files_analyzed += ($files | tonumber)' \
         "$CODE_STYLE_DATA" > "${CODE_STYLE_DATA}.tmp" && mv "${CODE_STYLE_DATA}.tmp" "$CODE_STYLE_DATA"

      echo "  ✓ Python: $py_files files analyzed"
      echo "    Indentation: $py_indent"
      echo "    Naming: snake_case"
    fi

    # Analyze JavaScript/TypeScript files
    if find "$DIRECTORY" -name "*.js" -o -name "*.ts" -type f 2>/dev/null | head -1 | grep -q .; then
      echo "Analyzing JavaScript/TypeScript files..."

      local js_indent_spaces=0
      local js_indent_tabs=0
      local js_files=0

      while IFS= read -r file; do
        ((js_files++))

        analysis=$(analyze_file "$file" "javascript")
        indent_type=$(echo "$analysis" | jq -r '.indent_type')

        [[ "$indent_type" == "spaces" ]] && ((js_indent_spaces++))
        [[ "$indent_type" == "tabs" ]] && ((js_indent_tabs++))

      done < <(find "$DIRECTORY" \( -name "*.js" -o -name "*.ts" \) -type f 2>/dev/null | head -20)

      local js_indent="spaces"
      [[ $js_indent_tabs -gt $js_indent_spaces ]] && js_indent="tabs"

      jq --arg indent "$js_indent" \
         --arg timestamp "$TIMESTAMP" \
         --arg files "$js_files" \
         '.languages.javascript = {
           "indentation": $indent,
           "indent_size": 2,
           "naming_convention": "camelCase",
           "max_line_length": 80,
           "files_analyzed": ($files | tonumber),
           "last_analyzed": $timestamp
         } |
         .last_analyzed = $timestamp |
         .total_files_analyzed += ($files | tonumber)' \
         "$CODE_STYLE_DATA" > "${CODE_STYLE_DATA}.tmp" && mv "${CODE_STYLE_DATA}.tmp" "$CODE_STYLE_DATA"

      echo "  ✓ JavaScript/TypeScript: $js_files files analyzed"
      echo "    Indentation: $js_indent"
    fi

    echo ""
    echo "✅ Code style analysis complete"
    ;;

  get)
    LANGUAGE="${2:-python}"

    if jq -e ".languages.$LANGUAGE" "$CODE_STYLE_DATA" > /dev/null 2>&1; then
      jq -r ".languages.$LANGUAGE" "$CODE_STYLE_DATA"
    else
      echo "{\"error\": \"No style data for language: $LANGUAGE\"}"
      exit 1
    fi
    ;;

  summary)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              Learned Code Style Preferences                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_files_analyzed // 0' "$CODE_STYLE_DATA")
    LAST=$(jq -r '.last_analyzed // "never"' "$CODE_STYLE_DATA")

    echo "Total files analyzed: $TOTAL"
    echo "Last analyzed: $LAST"
    echo ""

    # Show preferences per language
    for lang in python javascript ruby go; do
      if jq -e ".languages.$lang" "$CODE_STYLE_DATA" > /dev/null 2>&1; then
        echo "$lang:"
        jq -r ".languages.$lang |
          \"  Indentation: \(.indentation) (size: \(.indent_size))\n\" +
          \"  Naming: \(.naming_convention)\n\" +
          \"  Max line length: \(.max_line_length)\n\" +
          \"  Files analyzed: \(.files_analyzed)\"
        " "$CODE_STYLE_DATA"
        echo ""
      fi
    done
    ;;

  *)
    echo "Usage: $0 {analyze [directory]|get <language>|summary}"
    exit 1
    ;;
esac

exit 0
