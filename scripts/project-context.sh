#!/usr/bin/env bash
# project-context.sh - Per-project learning and adaptation
# Part of Adaptive Learning System v1.2 - Phase 2 Improvements

set -euo pipefail

PROJECT_CONTEXTS="$HOME/.claude/data/project-contexts.json"

# Initialize project contexts if doesn't exist
if [[ ! -f "$PROJECT_CONTEXTS" ]]; then
  cat > "$PROJECT_CONTEXTS" <<'EOF'
{
  "version": "1.0.0",
  "projects": {},
  "current_project": null,
  "total_projects": 0
}
EOF
fi

COMMAND="${1:-detect}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

detect_project_type() {
  local dir="$1"

  # Backend API detection
  if [[ -f "$dir/requirements.txt" ]] && grep -qi "fastapi\|flask\|django" "$dir/requirements.txt" 2>/dev/null; then
    echo "backend_api"
    return
  fi

  if [[ -f "$dir/package.json" ]] && grep -qi "express\|nestjs\|koa" "$dir/package.json" 2>/dev/null; then
    echo "backend_api"
    return
  fi

  # Frontend detection
  if [[ -f "$dir/package.json" ]] && grep -qi "react\|vue\|angular\|next" "$dir/package.json" 2>/dev/null; then
    echo "frontend_web"
    return
  fi

  # CLI tool detection
  if [[ -f "$dir/setup.py" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/go.mod" ]]; then
    if grep -qi "click\|argparse\|cli" "$dir"/*.py 2>/dev/null; then
      echo "cli_tool"
      return
    fi
  fi

  # Library detection
  if [[ -f "$dir/setup.py" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/package.json" ]]; then
    if [[ -d "$dir/src" ]] && [[ ! -d "$dir/tests" ]]; then
      echo "library"
      return
    fi
  fi

  # Data science detection
  if find "$dir" -name "*.ipynb" -type f 2>/dev/null | head -1 | grep -q .; then
    echo "data_science"
    return
  fi

  # Default
  echo "general"
}

case "$COMMAND" in
  detect)
    DIRECTORY="${2:-$PWD}"
    PROJECT_NAME=$(basename "$DIRECTORY")
    PROJECT_PATH=$(cd "$DIRECTORY" && pwd)

    echo "🔍 Detecting project context: $PROJECT_NAME"
    echo "Path: $PROJECT_PATH"
    echo ""

    # Detect project type
    PROJECT_TYPE=$(detect_project_type "$PROJECT_PATH")
    echo "Type: $PROJECT_TYPE"

    # Detect primary language
    PRIMARY_LANG="unknown"
    if find "$PROJECT_PATH" -maxdepth 2 -name "*.py" -type f 2>/dev/null | head -1 | grep -q .; then
      PRIMARY_LANG="python"
    elif find "$PROJECT_PATH" -maxdepth 2 -name "*.js" -o -name "*.ts" -type f 2>/dev/null | head -1 | grep -q .; then
      PRIMARY_LANG="javascript"
    elif find "$PROJECT_PATH" -maxdepth 2 -name "*.go" -type f 2>/dev/null | head -1 | grep -q .; then
      PRIMARY_LANG="go"
    fi
    echo "Primary language: $PRIMARY_LANG"

    # Detect frameworks
    FRAMEWORKS=()
    [[ -f "$PROJECT_PATH/requirements.txt" ]] && {
      grep -iq "django" "$PROJECT_PATH/requirements.txt" 2>/dev/null && FRAMEWORKS+=("django")
      grep -iq "flask" "$PROJECT_PATH/requirements.txt" 2>/dev/null && FRAMEWORKS+=("flask")
      grep -iq "fastapi" "$PROJECT_PATH/requirements.txt" 2>/dev/null && FRAMEWORKS+=("fastapi")
    }
    [[ -f "$PROJECT_PATH/package.json" ]] && {
      grep -iq "react" "$PROJECT_PATH/package.json" && FRAMEWORKS+=("react")
      grep -iq "vue" "$PROJECT_PATH/package.json" && FRAMEWORKS+=("vue")
      grep -iq "next" "$PROJECT_PATH/package.json" && FRAMEWORKS+=("nextjs")
    }

    if [[ ${#FRAMEWORKS[@]} -gt 0 ]]; then
      FRAMEWORKS_JSON=$(printf '%s\n' "${FRAMEWORKS[@]}" | jq -R . | jq -s '.')
      echo "Frameworks: ${FRAMEWORKS[@]}"
    else
      FRAMEWORKS_JSON="[]"
      echo "Frameworks: none"
    fi

    # Detect testing approach
    TESTING="unknown"
    [[ -f "$PROJECT_PATH/pytest.ini" ]] || [[ -d "$PROJECT_PATH/tests" ]] && TESTING="pytest"
    [[ -f "$PROJECT_PATH/jest.config.js" ]] && TESTING="jest"
    echo "Testing: $TESTING"

    # Detect deployment target
    DEPLOYMENT="unknown"
    [[ -f "$PROJECT_PATH/Dockerfile" ]] && DEPLOYMENT="docker"
    [[ -d "$PROJECT_PATH/.github/workflows" ]] && DEPLOYMENT="github_actions"
    [[ -f "$PROJECT_PATH/vercel.json" ]] && DEPLOYMENT="vercel"
    echo "Deployment: $DEPLOYMENT"

    echo ""

    # Create or update project context
    PROJECT_ID=$(echo "$PROJECT_PATH" | md5sum | cut -d' ' -f1)

    # Get existing interaction count
    EXISTING_COUNT=$(jq -r ".projects.\"$PROJECT_ID\".interaction_count // 0" "$PROJECT_CONTEXTS" 2>/dev/null || echo "0")
    EXISTING_CREATED=$(jq -r ".projects.\"$PROJECT_ID\".created_at // \"$TIMESTAMP\"" "$PROJECT_CONTEXTS" 2>/dev/null || echo "$TIMESTAMP")
    NEW_COUNT=$((EXISTING_COUNT + 1))

    jq --arg id "$PROJECT_ID" \
       --arg name "$PROJECT_NAME" \
       --arg path "$PROJECT_PATH" \
       --arg type "$PROJECT_TYPE" \
       --arg lang "$PRIMARY_LANG" \
       --argjson frameworks "$FRAMEWORKS_JSON" \
       --arg testing "$TESTING" \
       --arg deployment "$DEPLOYMENT" \
       --arg timestamp "$TIMESTAMP" \
       --arg count "$NEW_COUNT" \
       --arg created "$EXISTING_CREATED" \
       '
       .projects[$id] = {
         "name": $name,
         "path": $path,
         "type": $type,
         "language": $lang,
         "frameworks": $frameworks,
         "preferences": {
           "testing_approach": $testing,
           "documentation_style": "auto",
           "deployment_target": $deployment
         },
         "learned_patterns": [],
         "interaction_count": ($count | tonumber),
         "created_at": $created,
         "last_accessed": $timestamp
       } |
       .current_project = $id |
       .total_projects = (.projects | length)
       ' \
       "$PROJECT_CONTEXTS" > "${PROJECT_CONTEXTS}.tmp" && mv "${PROJECT_CONTEXTS}.tmp" "$PROJECT_CONTEXTS"

    echo "✅ Project context saved: $PROJECT_ID"
    ;;

  set-preference)
    # Set project-specific preference
    PROJECT_PATH="${2:-$PWD}"
    PREFERENCE_KEY="${3}"
    PREFERENCE_VALUE="${4}"

    if [[ -z "$PREFERENCE_KEY" ]] || [[ -z "$PREFERENCE_VALUE" ]]; then
      echo "Error: Preference key and value required"
      exit 1
    fi

    PROJECT_ID=$(echo "$PROJECT_PATH" | md5sum | cut -d' ' -f1)

    jq --arg id "$PROJECT_ID" \
       --arg key "$PREFERENCE_KEY" \
       --arg value "$PREFERENCE_VALUE" \
       '
       .projects[$id].preferences[$key] = $value
       ' \
       "$PROJECT_CONTEXTS" > "${PROJECT_CONTEXTS}.tmp" && mv "${PROJECT_CONTEXTS}.tmp" "$PROJECT_CONTEXTS"

    echo "Set $PREFERENCE_KEY = $PREFERENCE_VALUE for project $PROJECT_ID"
    ;;

  get)
    # Get current project context
    PROJECT_PATH="${2:-$PWD}"
    PROJECT_ID=$(echo "$PROJECT_PATH" | md5sum | cut -d' ' -f1)

    if jq -e ".projects.\"$PROJECT_ID\"" "$PROJECT_CONTEXTS" > /dev/null 2>&1; then
      jq -r ".projects.\"$PROJECT_ID\"" "$PROJECT_CONTEXTS"
    else
      echo "{\"error\": \"No context for project at: $PROJECT_PATH\"}"
      echo "{\"suggestion\": \"Run: /adaptive-intelligence project detect\"}"
      exit 1
    fi
    ;;

  list)
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   Tracked Projects                               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    TOTAL=$(jq -r '.total_projects // 0' "$PROJECT_CONTEXTS")
    CURRENT=$(jq -r '.current_project // "none"' "$PROJECT_CONTEXTS")

    echo "Total projects: $TOTAL"
    echo "Current project: $CURRENT"
    echo ""

    jq -r '
      .projects |
      to_entries |
      sort_by(-.value.last_accessed) |
      .[] |
      "[\(.key[0:8])] \(.value.name)\n" +
      "  Path: \(.value.path)\n" +
      "  Type: \(.value.type)\n" +
      "  Language: \(.value.language)\n" +
      "  Frameworks: \(.value.frameworks | join(", "))\n" +
      "  Interactions: \(.value.interaction_count)\n" +
      "  Last accessed: \(.value.last_accessed)\n"
    ' "$PROJECT_CONTEXTS"
    ;;

  summary)
    PROJECT_PATH="${2:-$PWD}"
    PROJECT_ID=$(echo "$PROJECT_PATH" | md5sum | cut -d' ' -f1)

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                   Project Context Summary                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if jq -e ".projects.\"$PROJECT_ID\"" "$PROJECT_CONTEXTS" > /dev/null 2>&1; then
      jq -r ".projects.\"$PROJECT_ID\" |
        \"Project: \(.name)\n\" +
        \"Type: \(.type)\n\" +
        \"Language: \(.language)\n\" +
        \"Frameworks: \(.frameworks | join(", "))\n\" +
        \"Testing: \(.preferences.testing_approach)\n\" +
        \"Deployment: \(.preferences.deployment_target)\n\" +
        \"Interactions: \(.interaction_count)\n\" +
        \"Last accessed: \(.last_accessed)\n\"
      " "$PROJECT_CONTEXTS"
    else
      echo "No context found for current project."
      echo "Run: /adaptive-intelligence project detect"
    fi
    ;;

  *)
    echo "Usage: $0 {detect [directory]|set-preference <path> <key> <value>|get [path]|list|summary [path]}"
    exit 1
    ;;
esac

exit 0
