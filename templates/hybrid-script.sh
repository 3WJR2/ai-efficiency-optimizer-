#!/usr/bin/env bash
# Hybrid Python+Shell script
# Uses shell for orchestration, Python for heavy lifting

set -euo pipefail

# Shell part: setup and orchestration
echo "🚀 Starting hybrid workflow..."

# Check dependencies
command -v python3 >/dev/null || { echo "Python3 required"; exit 1; }

# Python part: processing
python3 << 'PYTHON'
import sys
import json

def process():
    """Python processing logic"""
    print("Python processing...")
    # Your Python code here
    return {"status": "success"}

if __name__ == "__main__":
    result = process()
    print(json.dumps(result))
PYTHON

echo "✓ Workflow complete"
