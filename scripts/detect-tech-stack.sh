#!/usr/bin/env bash
# detect-tech-stack.sh - Auto-detect technology stack from environment
# Part of Adaptive Learning System v1.1 - Phase 1 Improvements

set -euo pipefail

INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
TECH_PROFILE="$HOME/.claude/data/tech-stack.json"
WORKING_DIR="${1:-$PWD}"

# Initialize tech profile if doesn't exist
if [[ ! -f "$TECH_PROFILE" ]]; then
  cat > "$TECH_PROFILE" <<'EOF'
{
  "version": "1.0.0",
  "detected_at": null,
  "technologies": {},
  "frameworks": {},
  "languages": {},
  "tools": {},
  "confidence": {}
}
EOF
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Detection functions

detect_languages() {
  local dir="$1"
  local temp_file=$(mktemp)

  # Count files by extension
  find "$dir" -maxdepth 3 -type f 2>/dev/null | while IFS= read -r file; do
    case "$file" in
      *.py) echo "python" ;;
      *.js|*.jsx) echo "javascript" ;;
      *.ts|*.tsx) echo "typescript" ;;
      *.go) echo "golang" ;;
      *.rs) echo "rust" ;;
      *.java) echo "java" ;;
      *.rb) echo "ruby" ;;
      *.php) echo "php" ;;
      *.swift) echo "swift" ;;
      *.kt) echo "kotlin" ;;
      *.c|*.cpp|*.cc) echo "c_cpp" ;;
      *.sh|*.bash) echo "shell" ;;
    esac
  done | sort | uniq -c | awk '{print "\""$2"\": "$1}' > "$temp_file"

  # Convert to JSON
  if [[ -s "$temp_file" ]]; then
    echo "{$(cat "$temp_file" | tr '\n' ',' | sed 's/,$//')}"
  else
    echo "{}"
  fi

  rm -f "$temp_file"
}

detect_frameworks() {
  local dir="$1"
  local temp_file=$(mktemp)

  # Python frameworks
  if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/Pipfile" ]] || [[ -f "$dir/pyproject.toml" ]]; then
    grep -iq "django" "$dir/requirements.txt" 2>/dev/null && echo '"django": 1' >> "$temp_file"
    grep -iq "flask" "$dir/requirements.txt" 2>/dev/null && echo '"flask": 1' >> "$temp_file"
    grep -iq "fastapi" "$dir/requirements.txt" 2>/dev/null && echo '"fastapi": 1' >> "$temp_file"
  fi

  # JavaScript/TypeScript frameworks
  if [[ -f "$dir/package.json" ]]; then
    grep -iq "react" "$dir/package.json" && echo '"react": 1' >> "$temp_file"
    grep -iq "vue" "$dir/package.json" && echo '"vue": 1' >> "$temp_file"
    grep -iq "angular" "$dir/package.json" && echo '"angular": 1' >> "$temp_file"
    grep -iq "next" "$dir/package.json" && echo '"nextjs": 1' >> "$temp_file"
    grep -iq "express" "$dir/package.json" && echo '"express": 1' >> "$temp_file"
    grep -iq "nestjs" "$dir/package.json" && echo '"nestjs": 1' >> "$temp_file"
  fi

  # Go frameworks
  if [[ -f "$dir/go.mod" ]]; then
    grep -iq "gin" "$dir/go.mod" && echo '"gin": 1' >> "$temp_file"
    grep -iq "echo" "$dir/go.mod" && echo '"echo": 1' >> "$temp_file"
    grep -iq "fiber" "$dir/go.mod" && echo '"fiber": 1' >> "$temp_file"
  fi

  # Ruby frameworks
  if [[ -f "$dir/Gemfile" ]]; then
    grep -iq "rails" "$dir/Gemfile" && echo '"rails": 1' >> "$temp_file"
    grep -iq "sinatra" "$dir/Gemfile" && echo '"sinatra": 1' >> "$temp_file"
  fi

  # Convert to JSON
  if [[ -s "$temp_file" ]]; then
    echo "{$(cat "$temp_file" | tr '\n' ',' | sed 's/,$//')}"
  else
    echo "{}"
  fi

  rm -f "$temp_file"
}

detect_tools() {
  local dir="$1"
  local temp_file=$(mktemp)

  # Version control
  [[ -d "$dir/.git" ]] && echo '"git": 1' >> "$temp_file"

  # Package managers
  [[ -f "$dir/package.json" ]] && echo '"npm": 1' >> "$temp_file"
  [[ -f "$dir/yarn.lock" ]] && echo '"yarn": 1' >> "$temp_file"
  [[ -f "$dir/pnpm-lock.yaml" ]] && echo '"pnpm": 1' >> "$temp_file"
  [[ -f "$dir/requirements.txt" ]] && echo '"pip": 1' >> "$temp_file"
  [[ -f "$dir/Pipfile" ]] && echo '"pipenv": 1' >> "$temp_file"
  [[ -f "$dir/poetry.lock" ]] && echo '"poetry": 1' >> "$temp_file"
  [[ -f "$dir/Gemfile" ]] && echo '"bundler": 1' >> "$temp_file"
  [[ -f "$dir/go.mod" ]] && echo '"go-modules": 1' >> "$temp_file"
  [[ -f "$dir/Cargo.toml" ]] && echo '"cargo": 1' >> "$temp_file"

  # Build tools
  [[ -f "$dir/Makefile" ]] && echo '"make": 1' >> "$temp_file"
  [[ -f "$dir/webpack.config.js" ]] && echo '"webpack": 1' >> "$temp_file"
  [[ -f "$dir/vite.config.js" ]] && echo '"vite": 1' >> "$temp_file"
  [[ -f "$dir/rollup.config.js" ]] && echo '"rollup": 1' >> "$temp_file"

  # Testing
  { [[ -f "$dir/pytest.ini" ]] || [[ -d "$dir/tests" ]]; } && echo '"pytest": 1' >> "$temp_file"
  [[ -f "$dir/jest.config.js" ]] && echo '"jest": 1' >> "$temp_file"

  # Docker
  [[ -f "$dir/Dockerfile" ]] && echo '"docker": 1' >> "$temp_file"
  [[ -f "$dir/docker-compose.yml" ]] && echo '"docker-compose": 1' >> "$temp_file"

  # CI/CD
  [[ -d "$dir/.github/workflows" ]] && echo '"github-actions": 1' >> "$temp_file"
  [[ -f "$dir/.gitlab-ci.yml" ]] && echo '"gitlab-ci": 1' >> "$temp_file"
  [[ -f "$dir/.circleci/config.yml" ]] && echo '"circleci": 1' >> "$temp_file"

  # Convert to JSON
  if [[ -s "$temp_file" ]]; then
    echo "{$(cat "$temp_file" | tr '\n' ',' | sed 's/,$//')}"
  else
    echo "{}"
  fi

  rm -f "$temp_file"
}

# Perform detection
echo "🔍 Detecting technology stack in: $WORKING_DIR"

LANGUAGES=$(detect_languages "$WORKING_DIR")
FRAMEWORKS=$(detect_frameworks "$WORKING_DIR")
TOOLS=$(detect_tools "$WORKING_DIR")

# Calculate confidence based on number of indicators
LANG_COUNT=$(echo "$LANGUAGES" | jq 'length')
FRAMEWORK_COUNT=$(echo "$FRAMEWORKS" | jq 'length')
TOOL_COUNT=$(echo "$TOOLS" | jq 'length')

TOTAL_INDICATORS=$((LANG_COUNT + FRAMEWORK_COUNT + TOOL_COUNT))

if [[ $TOTAL_INDICATORS -gt 10 ]]; then
  CONFIDENCE="high"
elif [[ $TOTAL_INDICATORS -gt 5 ]]; then
  CONFIDENCE="medium"
else
  CONFIDENCE="low"
fi

# Update tech profile
jq --arg timestamp "$TIMESTAMP" \
   --argjson languages "$LANGUAGES" \
   --argjson frameworks "$FRAMEWORKS" \
   --argjson tools "$TOOLS" \
   --arg confidence "$CONFIDENCE" \
   '.detected_at = $timestamp |
    .languages = $languages |
    .frameworks = $frameworks |
    .tools = $tools |
    .confidence_level = $confidence' \
   "$TECH_PROFILE" > "${TECH_PROFILE}.tmp" && mv "${TECH_PROFILE}.tmp" "$TECH_PROFILE"

# Update interaction learning with detected technologies
if [[ -f "$INTERACTION_LEARNING" ]]; then
  # Merge detected tech into learned preferences
  jq --argjson languages "$LANGUAGES" \
     --argjson frameworks "$FRAMEWORKS" \
     '.learned_preferences.technologies = (
        .learned_preferences.technologies + $languages + $frameworks
      )' \
     "$INTERACTION_LEARNING" > "${INTERACTION_LEARNING}.tmp" && mv "${INTERACTION_LEARNING}.tmp" "$INTERACTION_LEARNING"
fi

# Display results
echo ""
echo "✅ Technology Stack Detected (Confidence: $CONFIDENCE)"
echo ""

if [[ $LANG_COUNT -gt 0 ]]; then
  echo "Languages:"
  echo "$LANGUAGES" | jq -r 'to_entries | .[] | "  • \(.key): \(.value) files"'
  echo ""
fi

if [[ $FRAMEWORK_COUNT -gt 0 ]]; then
  echo "Frameworks:"
  echo "$FRAMEWORKS" | jq -r 'to_entries | .[] | "  • \(.key)"'
  echo ""
fi

if [[ $TOOL_COUNT -gt 0 ]]; then
  echo "Tools:"
  echo "$TOOLS" | jq -r 'to_entries | .[] | "  • \(.key)"'
  echo ""
fi

echo "💡 Claude will now provide more relevant suggestions for your stack!"
echo ""

exit 0
