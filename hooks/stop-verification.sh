#!/bin/bash
# Stop hook - Verification before Claude claims completion
# Checks for uncommitted changes, failing tests, and TypeScript errors

# Debug logging - controlled by environment variable
DEBUG="${CLAUDE_HOOKS_DEBUG:-false}"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/stop-verification.log"

log() {
    if [[ "$DEBUG" == "true" ]]; then
        mkdir -p "$LOG_DIR"
        echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
    fi
}

log "=== Stop hook triggered ==="

# Read input with timeout to prevent hanging
if command -v timeout >/dev/null 2>&1; then
    input=$(timeout 2 cat 2>/dev/null || echo "{}")
else
    # Fallback: read with a short timeout using read command
    input=""
    while IFS= read -r -t 2 line; do
        input+="$line"$'\n'
    done
    [[ -z "$input" ]] && input="{}"
fi

log "Input received (${#input} chars)"

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    log "jq not found, exiting"
    exit 0
fi

cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
log "Extracted cwd: $cwd"

to_posix_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo ""
        return
    fi
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path" 2>/dev/null
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

if [[ -n "$cwd" ]] && [[ -d "$cwd" ]]; then
    cd "$cwd" 2>/dev/null || true
    log "Changed to: $(pwd)"
fi

warnings=()

# Check if in a git repo
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    status=$(git status --porcelain 2>/dev/null)
    if [[ -n "$status" ]]; then
        changed_count=$(echo "$status" | wc -l | tr -d ' ')
        warnings+=("$changed_count uncommitted change(s) in git")
        log "Found $changed_count uncommitted changes"
    fi
fi

# Check for TypeScript errors if tsconfig exists
if [[ -f "tsconfig.json" ]]; then
    warnings+=("TypeScript project detected - consider running 'npx tsc --noEmit'")
fi

# Check for test files that might need running
if [[ -f "package.json" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts.test // empty' package.json >/dev/null 2>&1; then
        warnings+=("Test script available - consider running 'npm test'")
    fi
fi

# Output warnings if any
if [[ ${#warnings[@]} -gt 0 ]]; then
    log "Outputting ${#warnings[@]} warnings"
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

log "=== Stop hook complete ==="
exit 0
