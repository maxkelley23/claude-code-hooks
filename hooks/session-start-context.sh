#!/bin/bash
# SessionStart hook - Inject useful context at session start
# Provides git status, recent commits, and TODO items

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

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)

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
fi

line="========================================================"
echo "$line"
echo "SESSION CONTEXT"
echo "$line"
echo ""

if [[ -n "$cwd" ]]; then
    echo "CWD: $cwd"
    echo ""
fi

# Git status if in a git repo
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "GIT STATUS:"
    branch=$(git branch --show-current 2>/dev/null || echo "detached")
    echo "  Branch: $branch"

    # Show short status
    status=$(git status --short 2>/dev/null)
    if [[ -n "$status" ]]; then
        echo "  Changes:"
        echo "$status" | head -10 | sed 's/^/    /'
        count=$(echo "$status" | wc -l | tr -d ' ')
        if [[ $count -gt 10 ]]; then
            echo "    ... and $((count - 10)) more files"
        fi
    else
        echo "  Working tree clean"
    fi

    # Recent commits
    echo ""
    echo "RECENT COMMITS:"
    git log --oneline -3 2>/dev/null | sed 's/^/  /' || echo "  No commits yet"
    echo ""
fi

# Check for TODO files
for todo_file in "TODO.md" "TODO" "todo.md" ".todo" "TASKS.md"; do
    if [[ -f "$todo_file" ]]; then
        echo "TODO ($todo_file):"
        head -20 "$todo_file" | sed 's/^/  /'
        lines=$(wc -l < "$todo_file" | tr -d ' ')
        if [[ $lines -gt 20 ]]; then
            echo "  ... ($((lines - 20)) more lines)"
        fi
        echo ""
        break
    fi
done

# Check for CLAUDE.md
if [[ -f "CLAUDE.md" ]]; then
    echo "Project has CLAUDE.md"
fi

# Check for package.json scripts
if [[ -f "package.json" ]] && command -v jq >/dev/null 2>&1; then
    echo ""
    echo "AVAILABLE SCRIPTS:"
    jq -r '.scripts // {} | keys[]' package.json 2>/dev/null | head -8 | sed 's/^/  - /' || true
fi

echo ""
echo "$line"

exit 0
