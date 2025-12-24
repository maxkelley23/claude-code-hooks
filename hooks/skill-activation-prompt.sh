#!/bin/bash
set -e

cd "$HOME/.claude/hooks" || exit 0

if [[ -x "node_modules/.bin/tsx" ]]; then
    cat | ./node_modules/.bin/tsx skill-activation-prompt.ts
elif command -v npx >/dev/null 2>&1; then
    cat | npx tsx skill-activation-prompt.ts
fi
