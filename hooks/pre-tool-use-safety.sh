#!/bin/bash
# PreToolUse hook - Block dangerous bash commands before execution
# Exit code 2 = block the command, 0 = allow

set -e

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Read input from stdin
input=$(cat)

# Extract tool name and input
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Only check Bash commands
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

# Extract the command
command=$(echo "$input" | jq -r '.tool_input.command // empty')
if [[ -z "$command" ]]; then
    exit 0
fi

# Dangerous literal patterns to block
literal_patterns=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf $HOME"
    "rm -rf /*"
    "rm -rf ~/*"
    "chmod 777"
    "chmod -R 777"
    "> /dev/sda"
    "mkfs."
    "dd if="
    ":(){:|:&};:"
    ".env"
    "password"
    "secret"
    "api_key"
    "API_KEY"
    "credentials"
)

# Regex patterns to block
regex_patterns=(
    "curl.*\\|.*(sh|bash)"
    "wget.*\\|.*(sh|bash)"
)

# Check for dangerous literal patterns
for pattern in "${literal_patterns[@]}"; do
    if echo "$command" | grep -qiF "$pattern"; then
        echo "BLOCKED: Potentially dangerous command detected matching pattern: $pattern" >&2
        echo "Command was: $command" >&2
        exit 2
    fi
done

# Check for dangerous regex patterns
for pattern in "${regex_patterns[@]}"; do
    if echo "$command" | grep -qiE "$pattern"; then
        echo "BLOCKED: Potentially dangerous command detected matching pattern: $pattern" >&2
        echo "Command was: $command" >&2
        exit 2
    fi
done

# Block recursive deletion in sensitive directories
if echo "$command" | grep -qE "rm\s+(-[rf]+\s+)*(/|~|/home|/usr|/etc|/var|/sys|/boot|C:|C:\\\\)"; then
    echo "BLOCKED: Recursive deletion in sensitive directory" >&2
    exit 2
fi

# Block force push to main/master
if echo "$command" | grep -qE "git\s+push.*(-f|--force).*\b(main|master)\b"; then
    echo "BLOCKED: Force push to main/master branch" >&2
    exit 2
fi

# Allow the command
exit 0
