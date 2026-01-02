#!/bin/bash
# Security Reminder Hook - Bash port of security-guidance plugin
# Checks for security patterns in file edits and warns about vulnerabilities

set -e

# Read JSON input from stdin
INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' | cut -d'"' -f4)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | cut -d'"' -f4)

# Only check Edit, Write, MultiEdit tools
case "$TOOL_NAME" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

# Exit if no file path
[[ -z "$FILE_PATH" ]] && exit 0

# Extract content based on tool type
if [[ "$TOOL_NAME" == "Write" ]]; then
    CONTENT=$(echo "$INPUT" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')
elif [[ "$TOOL_NAME" == "Edit" ]]; then
    CONTENT=$(echo "$INPUT" | sed -n 's/.*"new_string":"\([^"]*\)".*/\1/p')
else
    CONTENT=""
fi

# State file for tracking shown warnings (per session)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
STATE_FILE="$HOME/.claude/security_warnings_${SESSION_ID:-default}.json"

# Function to check if warning was already shown
warning_shown() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "\"$key\"" "$STATE_FILE" 2>/dev/null && return 0
    fi
    return 1
}

# Function to save warning as shown
save_warning() {
    local key="$1"
    mkdir -p "$(dirname "$STATE_FILE")"
    if [[ -f "$STATE_FILE" ]]; then
        # Add to existing array
        local existing=$(cat "$STATE_FILE")
        echo "$existing" | sed 's/]$/,"'"$key"'"]/' > "$STATE_FILE"
    else
        echo "[\"$key\"]" > "$STATE_FILE"
    fi
}

# Check GitHub Actions workflow files
if [[ "$FILE_PATH" == *".github/workflows/"* ]] && [[ "$FILE_PATH" == *.yml || "$FILE_PATH" == *.yaml ]]; then
    WARNING_KEY="${FILE_PATH}-github_actions"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        cat >&2 << 'EOF'
⚠️ Security Warning: GitHub Actions Workflow

You are editing a GitHub Actions workflow file. Be aware of these security risks:

1. **Command Injection**: Never use untrusted input directly in run: commands
2. **Use environment variables**: Instead of ${{ github.event.issue.title }}, use env:

UNSAFE:
  run: echo "${{ github.event.issue.title }}"

SAFE:
  env:
    TITLE: ${{ github.event.issue.title }}
  run: echo "$TITLE"

Risky inputs: github.event.issue.body, github.event.pull_request.title/body,
github.event.comment.body, github.event.commits.*.message, github.head_ref
EOF
        exit 2
    fi
fi

# Check for child_process.exec
if [[ "$CONTENT" == *"child_process.exec"* ]] || [[ "$CONTENT" == *"execSync("* ]]; then
    WARNING_KEY="${FILE_PATH}-child_process"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        cat >&2 << 'EOF'
⚠️ Security Warning: child_process.exec() can lead to command injection.

Instead of: exec(`command ${userInput}`)
Use: execFile('command', [userInput])

execFile prevents shell injection by not using a shell.
EOF
        exit 2
    fi
fi

# Check for new Function()
if [[ "$CONTENT" == *"new Function"* ]]; then
    WARNING_KEY="${FILE_PATH}-new_function"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: new Function() with dynamic strings can lead to code injection. Consider alternatives." >&2
        exit 2
    fi
fi

# Check for eval()
if [[ "$CONTENT" == *"eval("* ]]; then
    WARNING_KEY="${FILE_PATH}-eval"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: eval() executes arbitrary code. Use JSON.parse() for data or find alternatives." >&2
        exit 2
    fi
fi

# Check for dangerouslySetInnerHTML
if [[ "$CONTENT" == *"dangerouslySetInnerHTML"* ]]; then
    WARNING_KEY="${FILE_PATH}-dangerously_set_html"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: dangerouslySetInnerHTML can lead to XSS. Sanitize content with DOMPurify." >&2
        exit 2
    fi
fi

# Check for innerHTML
if [[ "$CONTENT" == *".innerHTML ="* ]] || [[ "$CONTENT" == *".innerHTML="* ]]; then
    WARNING_KEY="${FILE_PATH}-innerHTML"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: innerHTML with untrusted content can cause XSS. Use textContent or sanitize with DOMPurify." >&2
        exit 2
    fi
fi

# Check for document.write
if [[ "$CONTENT" == *"document.write"* ]]; then
    WARNING_KEY="${FILE_PATH}-document_write"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: document.write() can be exploited for XSS. Use DOM methods like createElement()." >&2
        exit 2
    fi
fi

# Check for pickle (Python)
if [[ "$CONTENT" == *"pickle"* ]]; then
    WARNING_KEY="${FILE_PATH}-pickle"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: pickle with untrusted content can lead to code execution. Use JSON instead." >&2
        exit 2
    fi
fi

# Check for os.system (Python)
if [[ "$CONTENT" == *"os.system"* ]]; then
    WARNING_KEY="${FILE_PATH}-os_system"
    if ! warning_shown "$WARNING_KEY"; then
        save_warning "$WARNING_KEY"
        echo "⚠️ Security Warning: os.system should only be used with static arguments, never user-controlled input." >&2
        exit 2
    fi
fi

# All checks passed
exit 0
