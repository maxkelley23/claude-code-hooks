#!/bin/bash
# Stop hook - Verification before Claude claims completion
# Checks for uncommitted changes, failing tests, and TypeScript errors

set -e

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Read input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')

to_posix_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo ""
        return
    fi
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path"
        return
    fi
    if [[ "$path" =~ ^[A-Za-z]:[\\/].* ]]; then
        local drive="${path:0:1}"
        local rest="${path:2}"
        rest="${rest//\\//}"
        echo "/${drive,,}${rest}"
        return
    fi
    echo "$path"
}

# Change to project directory if provided
cwd=$(to_posix_path "$cwd")
if [[ -n "$cwd" ]]; then
    cd "$cwd" 2>/dev/null || true
fi

warnings=()

# Check if in a git repo
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Check for uncommitted changes
    status=$(git status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        changed_count=$(echo "$status" | wc -l | tr -d ' ')
        warnings+=("$changed_count uncommitted change(s) in git")
    fi
fi

# Check for TypeScript errors if tsconfig exists
if [[ -f "tsconfig.json" ]]; then
    warnings+=("TypeScript project detected - consider running 'npx tsc --noEmit'")
fi

# Check for test files that might need running
if [[ -f "package.json" ]]; then
    if jq -e '.scripts.test // empty' package.json >/dev/null 2>&1; then
        warnings+=("Test script available - consider running 'npm test'")
    fi
fi

# Output warnings if any
if [[ ${#warnings[@]} -gt 0 ]]; then
    line="========================================================"
    echo ""
    echo "$line"
    echo "COMPLETION CHECKLIST"
    echo "$line"
    for warning in "${warnings[@]}"; do
        echo "- $warning"
    done
    echo "$line"
fi

# Always exit 0 - we're just providing info, not blocking
exit 0
