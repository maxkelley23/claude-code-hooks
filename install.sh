#!/bin/bash
# Claude Code Hooks Installer
# Installs hooks to ~/.claude/hooks and configures settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Claude Code Hooks Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine home directory
if [[ -n "$HOME" ]]; then
    HOME_DIR="$HOME"
elif [[ -n "$USERPROFILE" ]]; then
    # Windows
    HOME_DIR="$USERPROFILE"
else
    echo -e "${RED}Error: Could not determine home directory${NC}"
    exit 1
fi

CLAUDE_DIR="$HOME_DIR/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"

echo -e "${YELLOW}Home directory:${NC} $HOME_DIR"
echo -e "${YELLOW}Claude config:${NC} $CLAUDE_DIR"
echo -e "${YELLOW}Hooks directory:${NC} $HOOKS_DIR"
echo ""

# Create directories
echo -e "${GREEN}Creating directories...${NC}"
mkdir -p "$HOOKS_DIR"

# Copy hook scripts
echo -e "${GREEN}Copying hook scripts...${NC}"
cp "$SCRIPT_DIR/hooks/"*.sh "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/"*.ts "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/package.json" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/tsconfig.json" "$HOOKS_DIR/"

# Make scripts executable
echo -e "${GREEN}Making scripts executable...${NC}"
chmod +x "$HOOKS_DIR/"*.sh

# Install npm dependencies
echo -e "${GREEN}Installing npm dependencies...${NC}"
cd "$HOOKS_DIR"
if command -v npm >/dev/null 2>&1; then
    npm install --silent
else
    echo -e "${YELLOW}Warning: npm not found. Please run 'npm install' in $HOOKS_DIR manually.${NC}"
fi

# Copy skill-rules.json if it doesn't exist
if [[ ! -f "$CLAUDE_DIR/skill-rules.json" ]]; then
    echo -e "${GREEN}Installing default skill-rules.json...${NC}"
    cp "$SCRIPT_DIR/examples/skill-rules.json" "$CLAUDE_DIR/skill-rules.json"
else
    echo -e "${YELLOW}Skipping skill-rules.json (already exists)${NC}"
fi

# Detect platform and choose settings template
echo ""
echo -e "${GREEN}Configuring settings...${NC}"

SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "${YELLOW}Existing settings.json found.${NC}"
    echo ""
    echo "You have two options:"
    echo "  1. Manually merge the hooks configuration"
    echo "  2. Backup existing and install fresh"
    echo ""
    read -p "Choose an option (1/2): " choice

    if [[ "$choice" == "2" ]]; then
        BACKUP_FILE="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}Backing up to $BACKUP_FILE${NC}"
        cp "$SETTINGS_FILE" "$BACKUP_FILE"

        # Detect Windows
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
            cp "$SCRIPT_DIR/examples/settings-windows.json" "$SETTINGS_FILE"
        else
            cp "$SCRIPT_DIR/examples/settings.json" "$SETTINGS_FILE"
        fi
        echo -e "${GREEN}New settings installed.${NC}"
    else
        echo ""
        echo -e "${YELLOW}Please manually add the hooks from:${NC}"
        if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
            echo "  $SCRIPT_DIR/examples/settings-windows.json"
        else
            echo "  $SCRIPT_DIR/examples/settings.json"
        fi
    fi
else
    # No existing settings, install fresh
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
        cp "$SCRIPT_DIR/examples/settings-windows.json" "$SETTINGS_FILE"
    else
        cp "$SCRIPT_DIR/examples/settings.json" "$SETTINGS_FILE"
    fi
    echo -e "${GREEN}Settings installed.${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Installed hooks:"
echo "  - SessionStart: Context injection (git status, TODOs)"
echo "  - UserPromptSubmit: Skill activation"
echo "  - PreToolUse: Safety validation"
echo "  - PostToolUse: Auto-formatting"
echo "  - Stop: Completion checklist"
echo ""
echo "Files installed to:"
echo "  - Hooks: $HOOKS_DIR/"
echo "  - Settings: $SETTINGS_FILE"
echo "  - Skill rules: $CLAUDE_DIR/skill-rules.json"
echo ""
echo -e "${YELLOW}Restart Claude Code for changes to take effect.${NC}"
