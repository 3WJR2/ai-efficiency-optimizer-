#!/usr/bin/env bash
# on-session-start.sh - Initialize Adaptive Intelligence System on Claude startup
# Part of Adaptive Learning System v1.0

set -euo pipefail

# Silent initialization - only output if there's an error
QUIET=true

# Ensure data directory exists
mkdir -p "$HOME/.claude/data" 2>/dev/null || true

# Initialize user profile if not exists
USER_PROFILE="$HOME/.claude/data/user-profile.json"
if [[ ! -f "$USER_PROFILE" ]]; then
    cat > "$USER_PROFILE" <<'EOF'
{
  "version": "1.0.0",
  "created": "$(date -u +"%Y-%m-%d")",
  "last_updated": "$(date -u +"%Y-%m-%d")",
  "profile": {
    "learning_stage": "initialization",
    "interaction_count": 0,
    "preferences": {
      "communication_style": "adaptive",
      "detail_level": "comprehensive",
      "explanation_style": "technical",
      "proactive_suggestions": true,
      "critical_thinking": "mandatory"
    },
    "domains": {
      "expertise_areas": [],
      "learning_areas": [],
      "frequent_technologies": {}
    },
    "interaction_patterns": {
      "typical_request_types": {},
      "time_of_day_patterns": {},
      "session_duration_avg": 0,
      "complexity_preference": "adaptive"
    },
    "quality_metrics": {
      "satisfaction_signals": 0,
      "retry_rate": 0,
      "clarification_rate": 0,
      "success_rate": 0
    },
    "learning_insights": {
      "communication_preferences": [],
      "technical_depth_preferences": [],
      "workflow_patterns": []
    }
  },
  "metadata": {
    "schema_version": "1.0",
    "auto_learn": true,
    "privacy_mode": false,
    "retention_days": 365
  }
}
EOF
    [[ "$QUIET" != "true" ]] && echo "✓ Initialized user profile"
fi

# Initialize interaction learning if not exists
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
if [[ ! -f "$INTERACTION_LEARNING" ]]; then
    cat > "$INTERACTION_LEARNING" <<'EOF'
{
  "version": "1.0.0",
  "learning_system": {
    "enabled": true,
    "confidence_threshold": 0.70,
    "min_samples_for_learning": 3,
    "adaptation_rate": 0.15
  },
  "interaction_patterns": {
    "request_categories": {
      "code_implementation": {
        "count": 0,
        "avg_complexity": 0,
        "preferred_approach": "unknown",
        "success_rate": 0,
        "common_patterns": []
      },
      "system_design": {
        "count": 0,
        "avg_complexity": 0,
        "preferred_approach": "unknown",
        "success_rate": 0,
        "common_patterns": []
      },
      "debugging": {
        "count": 0,
        "avg_complexity": 0,
        "preferred_approach": "unknown",
        "success_rate": 0,
        "common_patterns": []
      },
      "explanation_requests": {
        "count": 0,
        "depth_preference": "unknown",
        "preferred_format": "unknown",
        "success_rate": 0
      },
      "research_tasks": {
        "count": 0,
        "thoroughness_preference": "unknown",
        "success_rate": 0,
        "common_patterns": []
      }
    },
    "communication_style": {
      "brevity_vs_detail": {
        "score": 0.5,
        "confidence": 0.0,
        "samples": 0
      },
      "technical_depth": {
        "score": 0.5,
        "confidence": 0.0,
        "samples": 0
      },
      "code_examples_preferred": {
        "score": 0.5,
        "confidence": 0.0,
        "samples": 0
      },
      "visual_diagrams_preferred": {
        "score": 0.5,
        "confidence": 0.0,
        "samples": 0
      }
    },
    "problem_solving_style": {
      "systematic_vs_exploratory": 0.5,
      "top_down_vs_bottom_up": 0.5,
      "theory_first_vs_practice_first": 0.5,
      "confidence": 0.0
    },
    "quality_indicators": {
      "follows_up_with_questions": 0,
      "requests_clarifications": 0,
      "provides_detailed_context": 0,
      "accepts_suggestions": 0,
      "rejects_suggestions": 0
    }
  },
  "learned_preferences": {
    "technologies": {},
    "frameworks": {},
    "methodologies": {},
    "documentation_sources": {}
  },
  "behavioral_insights": {
    "typical_workflows": [],
    "common_pitfalls": [],
    "strengths": [],
    "areas_needing_support": []
  },
  "adaptation_history": []
}
EOF
    [[ "$QUIET" != "true" ]] && echo "✓ Initialized interaction learning"
fi

# Initialize critical thinking framework if not exists
CRITICAL_THINKING="$HOME/.claude/data/critical-thinking-framework.json"
if [[ ! -f "$CRITICAL_THINKING" ]]; then
    cat > "$CRITICAL_THINKING" <<'EOF'
{
  "version": "1.0.0",
  "framework": {
    "enabled": true,
    "enforcement_level": "mandatory",
    "quality_threshold": 0.85
  },
  "thinking_protocols": {
    "problem_analysis": {
      "steps": [
        "1. Understand the core problem (not just symptoms)",
        "2. Identify constraints and requirements",
        "3. Map dependencies and relationships",
        "4. Evaluate scope and complexity",
        "5. Check for hidden assumptions"
      ],
      "required_for": ["code_implementation", "system_design", "debugging"]
    },
    "solution_design": {
      "steps": [
        "1. Generate multiple candidate approaches",
        "2. Evaluate trade-offs (performance, maintainability, complexity)",
        "3. Consider edge cases and failure modes",
        "4. Validate against requirements",
        "5. Choose optimal solution with rationale"
      ],
      "required_for": ["code_implementation", "system_design", "architecture"]
    },
    "quality_validation": {
      "steps": [
        "1. Verify solution completeness",
        "2. Check for security vulnerabilities",
        "3. Assess maintainability and extensibility",
        "4. Validate performance characteristics",
        "5. Ensure testability"
      ],
      "required_for": ["all"]
    },
    "knowledge_verification": {
      "steps": [
        "1. Verify information currency (check versions)",
        "2. Validate against authoritative sources",
        "3. Cross-reference multiple sources",
        "4. Flag assumptions and uncertainties",
        "5. Cite sources for verification"
      ],
      "required_for": ["research_tasks", "code_implementation"]
    }
  },
  "thinking_modes": {
    "quick_analysis": {
      "duration_target": "30-60s",
      "depth": "surface",
      "use_for": ["simple_queries", "clarifications", "routine_tasks"]
    },
    "standard_thinking": {
      "duration_target": "1-2min",
      "depth": "moderate",
      "use_for": ["code_review", "implementation", "explanation"]
    },
    "deep_thinking": {
      "duration_target": "2-5min",
      "depth": "comprehensive",
      "use_for": ["architecture", "complex_debugging", "optimization"]
    },
    "critical_thinking": {
      "duration_target": "5-10min",
      "depth": "exhaustive",
      "use_for": ["system_design", "novel_problems", "high_stakes_decisions"]
    }
  },
  "quality_gates": {
    "solution_completeness": {
      "weight": 0.25,
      "criteria": [
        "Addresses all stated requirements",
        "Handles edge cases",
        "Includes error handling",
        "Provides rollback/recovery"
      ]
    },
    "technical_correctness": {
      "weight": 0.30,
      "criteria": [
        "Uses correct APIs/patterns",
        "Follows best practices",
        "No security vulnerabilities",
        "Performance considerations"
      ]
    },
    "maintainability": {
      "weight": 0.20,
      "criteria": [
        "Clear, readable code/documentation",
        "Modular and extensible",
        "Well-tested",
        "Documented rationale"
      ]
    },
    "user_alignment": {
      "weight": 0.25,
      "criteria": [
        "Matches user's skill level",
        "Addresses stated goals",
        "Considers user's context",
        "Clear communication"
      ]
    }
  },
  "critical_thinking_triggers": {
    "auto_enable_for": [
      "requests mentioning 'production'",
      "requests mentioning 'critical'",
      "system architecture tasks",
      "security-related tasks",
      "performance optimization",
      "data integrity concerns",
      "multi-component integration"
    ],
    "warning_indicators": [
      "insufficient information provided",
      "conflicting requirements detected",
      "high complexity with simple approach",
      "potential security implications",
      "scalability concerns",
      "multiple valid approaches with unclear tradeoffs"
    ]
  }
}
EOF
    [[ "$QUIET" != "true" ]] && echo "✓ Initialized critical thinking framework"
fi

# Verify all scripts are executable
chmod +x "$HOME/.claude/scripts/capture-interaction.sh" 2>/dev/null || true
chmod +x "$HOME/.claude/scripts/analyze-interaction-patterns.sh" 2>/dev/null || true
chmod +x "$HOME/.claude/scripts/apply-critical-thinking.sh" 2>/dev/null || true
chmod +x "$HOME/.claude/skills/adaptive-intelligence/skill.sh" 2>/dev/null || true

# System is now ready - exit silently
exit 0
