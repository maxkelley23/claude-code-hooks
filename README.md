# Claude Code Hooks

A collection of powerful hooks for [Claude Code](https://claude.ai/code) that add safety guardrails, automatic formatting, skill activation, and session context.

## What Are Hooks?

Hooks are shell commands that Claude Code executes at specific moments during your session. They can:
- **Inject context** when sessions start
- **Suggest skills** based on your prompts
- **Block dangerous commands** before they run
- **Auto-format code** after edits
- **Show checklists** when Claude finishes

## Hook Lifecycle

```
SESSION START ─────────────────────────────────────────────────────
  └─► SessionStart hook → Shows git status, TODOs, project context

YOU TYPE A PROMPT ─────────────────────────────────────────────────
  └─► UserPromptSubmit hook → Matches prompt to skills
      "create a react component" → Suggests frontend-dev-guidelines

CLAUDE USES A TOOL ────────────────────────────────────────────────
  └─► PreToolUse hook → Validates safety
      "rm -rf /" → BLOCKED
      "npm install" → ALLOWED

TOOL COMPLETES ────────────────────────────────────────────────────
  └─► PostToolUse hooks → Tracks changes, then auto-formats code

CLAUDE FINISHES ───────────────────────────────────────────────────
  └─► Stop hook → Shows completion checklist
      "3 uncommitted changes", "consider running tests"
```

## Features

### 1. Session Context Injection
When you start a session, automatically see:
- Current git branch and status
- Recent commits
- TODO file contents
- Available npm scripts

### 2. Skill Activation
Prompts are matched against keyword rules to suggest relevant skills:
- "create a component" → frontend-dev-guidelines
- "add an API endpoint" → backend-dev-guidelines
- "create a skill" → skill-developer

### 3. Safety Guardrails
Dangerous bash commands are blocked before execution:
- `rm -rf /` and variations
- `chmod 777`
- Force push to main/master
- Commands accessing `.env`, passwords, API keys
- Piped curl/wget to shell

### 4. Change Tracking
Tracks which files are edited during a session:
- Logs all edited files with timestamps
- Detects affected repos/subprojects (frontend, backend, packages/*)
- Caches build commands for affected repos
- Stores TypeScript compilation commands
- Creates `.claude/tsc-cache/` in your project directory

### 5. Auto-Formatting
After file edits, automatically runs formatters if available:
- **JavaScript/TypeScript**: Prettier, ESLint
- **Python**: Black, Ruff
- **Go**: gofmt
- **Rust**: rustfmt

### 6. Completion Checklist
When Claude finishes, reminds you about:
- Uncommitted git changes
- Available test scripts
- TypeScript compilation

## Installation

### Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/maxkelley23/claude-code-hooks.git
cd claude-code-hooks

# Run the installer
./install.sh
```

### Manual Install

1. **Copy hooks to your Claude config:**
```bash
mkdir -p ~/.claude/hooks
cp hooks/* ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

2. **Install TypeScript dependencies:**
```bash
cd ~/.claude/hooks
npm install
```

3. **Merge settings into your config:**
```bash
# Edit ~/.claude/settings.json and add the hooks configuration
# See examples/settings.json for the full configuration
```

## Configuration

### Settings Location

Hooks are configured in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [...],
    "UserPromptSubmit": [...],
    "PreToolUse": [...],
    "PostToolUse": [...],
    "Stop": [...]
  }
}
```

### Skill Rules

Customize skill matching in `~/.claude/skill-rules.json`:

```json
{
  "skills": {
    "my-custom-skill": {
      "priority": "high",
      "promptTriggers": {
        "keywords": ["keyword1", "keyword2"],
        "intentPatterns": ["(create|build).*something"]
      }
    }
  }
}
```

## File Structure

```
~/.claude/
├── settings.json              # Hook configuration
├── skill-rules.json           # Skill matching rules
└── hooks/
    ├── session-start-context.sh      # Session initialization
    ├── skill-activation-prompt.sh    # Skill detection (wrapper)
    ├── skill-activation-prompt.ts    # Skill detection (logic)
    ├── pre-tool-use-safety.sh        # Command safety validation
    ├── post-tool-use-tracker.sh      # Change tracking
    ├── post-tool-use-format.sh       # Auto-formatting
    ├── stop-verification.sh          # Completion checklist
    ├── package.json                  # Node dependencies
    └── tsconfig.json                 # TypeScript config
```

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Fully supported | Native bash |
| Linux | Fully supported | Native bash |
| Windows | Fully supported | Requires Git Bash |

### Windows Setup

Windows uses Git Bash for hook execution. The settings automatically invoke:
```
"C:/Program Files/Git/bin/bash.exe" -lc "$HOME/.claude/hooks/script.sh"
```

## Customization

### Adding Safety Patterns

Edit `hooks/pre-tool-use-safety.sh` to add blocked patterns:

```bash
literal_patterns=(
    "your-dangerous-pattern"
    # ... existing patterns
)
```

### Adding Skill Keywords

Edit `skill-rules.json` to add new skills or keywords:

```json
{
  "skills": {
    "your-skill-name": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "promptTriggers": {
        "keywords": ["your", "keywords"],
        "intentPatterns": ["regex patterns"]
      }
    }
  }
}
```

### Adding Formatters

Edit `hooks/post-tool-use-format.sh` to add new formatters:

```bash
case "$ext" in
    your_extension)
        your-formatter "$file_path" && format_msg "your-formatter"
        ;;
esac
```

## How It Works

### Data Flow

1. Claude Code triggers a hook event
2. Runs the configured shell command via bash
3. Passes event data as JSON to stdin
4. Script processes the data and:
   - Outputs to stdout (shown to Claude)
   - Outputs to stderr (shown as errors)
   - Exits with code 0 (success) or 2 (block action)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - action proceeds |
| 2 | Block - action prevented, stderr sent to Claude |
| Other | Non-blocking error |

### Hook Input (JSON via stdin)

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript",
  "cwd": "/current/working/directory",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm install"
  }
}
```

## Troubleshooting

### Hooks not running?

1. Check settings.json syntax: `cat ~/.claude/settings.json | jq .`
2. Verify scripts are executable: `ls -la ~/.claude/hooks/`
3. Test manually: `echo '{}' | ~/.claude/hooks/session-start-context.sh`

### Windows path issues?

The scripts include `to_posix_path()` to convert Windows paths. If issues persist, check that Git Bash is installed at `C:/Program Files/Git/bin/bash.exe`.

### TypeScript errors?

```bash
cd ~/.claude/hooks
npm install
npx tsc --noEmit
```

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests if applicable
4. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Claude Code Documentation](https://code.claude.com/docs/en/hooks)
- [Anthropic](https://anthropic.com) for Claude Code
