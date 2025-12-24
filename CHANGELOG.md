# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-24

### Added
- **SessionStart hook** - Injects project context (git status, TODOs, npm scripts) when sessions begin
- **UserPromptSubmit hook** - Matches prompts against skill rules for intelligent suggestions
- **PreToolUse hook** - Blocks dangerous bash commands before execution
- **PostToolUse hooks**:
  - **Tracker** - Tracks edited files, detects affected repos/subprojects, caches build commands
  - **Formatter** - Auto-formats code files using Prettier, ESLint, Black, Ruff, gofmt, rustfmt
- **Stop hook** - Shows completion checklist with uncommitted changes and test reminders
- Cross-platform support for macOS, Linux, and Windows (via Git Bash)
- Installation script with interactive setup
- Example configurations for Unix and Windows
- Customizable skill-rules.json for prompt matching
