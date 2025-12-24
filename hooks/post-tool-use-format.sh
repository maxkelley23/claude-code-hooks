#!/bin/bash
# PostToolUse hook - Auto-format files after edits
# Runs formatters if available in the project

# Don't exit on error - formatting is optional
set +e

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Read input
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
project_dir="${CLAUDE_PROJECT_DIR:-}"

# Only process file edit tools
if [[ ! "$tool_name" =~ ^(Edit|MultiEdit|Write)$ ]]; then
    exit 0
fi

# Skip if no file path
if [[ -z "$file_path" ]]; then
    exit 0
fi

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

file_path=$(to_posix_path "$file_path")
project_dir=$(to_posix_path "$project_dir")

# Skip non-code files
if [[ "$file_path" =~ \.(md|txt|json|yaml|yml|toml|lock|log|csv)$ ]]; then
    exit 0
fi

# Skip node_modules and common non-source directories
if [[ "$file_path" =~ (node_modules|\.git|dist|build|coverage|\.next|\.cache) ]]; then
    exit 0
fi

# Change to project directory
if [[ -n "$project_dir" ]]; then
    cd "$project_dir" 2>/dev/null || exit 0
fi

# Get file extension
ext="${file_path##*.}"

format_msg() {
    echo "Formatted ($1): $file_path"
}

# Try to format based on file type
case "$ext" in
    ts|tsx|js|jsx|mjs|cjs)
        if command -v npx >/dev/null 2>&1; then
            if [[ -f "node_modules/.bin/prettier" || -f ".prettierrc" || -f ".prettierrc.json" || -f ".prettierrc.js" || -f ".prettierrc.cjs" || -f "prettier.config.js" || -f "prettier.config.cjs" || -f "prettier.config.mjs" ]]; then
                npx --no-install prettier --write "$file_path" >/dev/null 2>&1 && format_msg "prettier"
            fi
            if [[ -f "node_modules/.bin/eslint" || -f ".eslintrc" || -f ".eslintrc.json" || -f ".eslintrc.js" || -f ".eslintrc.cjs" || -f "eslint.config.js" || -f "eslint.config.cjs" || -f "eslint.config.mjs" ]]; then
                npx --no-install eslint --fix "$file_path" >/dev/null 2>&1 && format_msg "eslint"
            fi
        fi
        ;;
    py)
        if command -v black >/dev/null 2>&1; then
            black "$file_path" >/dev/null 2>&1 && format_msg "black"
        elif command -v ruff >/dev/null 2>&1; then
            ruff format "$file_path" >/dev/null 2>&1 && format_msg "ruff"
        fi
        ;;
    go)
        if command -v gofmt >/dev/null 2>&1; then
            gofmt -w "$file_path" >/dev/null 2>&1 && format_msg "gofmt"
        fi
        ;;
    rs)
        if command -v rustfmt >/dev/null 2>&1; then
            rustfmt "$file_path" >/dev/null 2>&1 && format_msg "rustfmt"
        fi
        ;;
esac

# Always exit successfully - formatting is nice-to-have
exit 0
