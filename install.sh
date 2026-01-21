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

# Detect Windows for template selection
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
    NEW_SETTINGS_FILE="$SCRIPT_DIR/examples/settings-windows.json"
else
    NEW_SETTINGS_FILE="$SCRIPT_DIR/examples/settings.json"
fi

# Function to merge settings using Node.js
merge_settings() {
    local existing="$1"
    local new_hooks="$2"
    local output="$3"

    node -e "
const fs = require('fs');

const existing = JSON.parse(fs.readFileSync('$existing', 'utf8'));
const newSettings = JSON.parse(fs.readFileSync('$new_hooks', 'utf8'));

// Deep merge function for hooks
function mergeHooks(existingHooks, newHooks) {
    const merged = { ...existingHooks };

    for (const [eventName, newEventHooks] of Object.entries(newHooks)) {
        if (!merged[eventName]) {
            // Event doesn't exist, add it entirely
            merged[eventName] = newEventHooks;
        } else {
            // Event exists, merge the hooks arrays
            for (const newHookGroup of newEventHooks) {
                const matcher = newHookGroup.matcher || '__default__';

                // Find existing group with same matcher
                const existingGroupIndex = merged[eventName].findIndex(g =>
                    (g.matcher || '__default__') === matcher
                );

                if (existingGroupIndex === -1) {
                    // No matching group, add the new one
                    merged[eventName].push(newHookGroup);
                } else {
                    // Merge hooks into existing group, avoiding duplicates
                    const existingGroup = merged[eventName][existingGroupIndex];
                    const existingCommands = new Set(
                        existingGroup.hooks.map(h => h.command)
                    );

                    for (const hook of newHookGroup.hooks) {
                        // Normalize command for comparison (handle path variations)
                        const normalizedNew = hook.command.replace(/\\\"/g, '\"');
                        const isDuplicate = [...existingCommands].some(cmd => {
                            const normalizedExisting = cmd.replace(/\\\"/g, '\"');
                            // Check if commands point to same script
                            const newScript = normalizedNew.split('/').pop().split('\"')[0];
                            const existingScript = normalizedExisting.split('/').pop().split('\"')[0];
                            return newScript === existingScript;
                        });

                        if (!isDuplicate) {
                            existingGroup.hooks.push(hook);
                        }
                    }
                }
            }
        }
    }

    return merged;
}

// Merge the configurations
const result = { ...existing };

// Merge hooks
if (newSettings.hooks) {
    result.hooks = mergeHooks(existing.hooks || {}, newSettings.hooks);
}

// Write the result
fs.writeFileSync('$output', JSON.stringify(result, null, 2) + '\n');

console.log('Settings merged successfully');
"
}

if [[ -f "$SETTINGS_FILE" ]]; then
    echo -e "${YELLOW}Existing settings.json found.${NC}"
    echo ""
    echo "Options:"
    echo "  1. Auto-merge hooks (recommended - preserves your existing settings)"
    echo "  2. Backup existing and install fresh"
    echo "  3. Skip settings configuration"
    echo ""
    read -p "Choose an option (1/2/3): " choice

    case "$choice" in
        1)
            # Auto-merge using Node.js
            if command -v node >/dev/null 2>&1; then
                BACKUP_FILE="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
                echo -e "${GREEN}Backing up to $BACKUP_FILE${NC}"
                cp "$SETTINGS_FILE" "$BACKUP_FILE"

                echo -e "${GREEN}Merging hooks configuration...${NC}"
                if merge_settings "$SETTINGS_FILE" "$NEW_SETTINGS_FILE" "$SETTINGS_FILE"; then
                    echo -e "${GREEN}Settings merged successfully!${NC}"
                else
                    echo -e "${RED}Merge failed. Restoring backup...${NC}"
                    cp "$BACKUP_FILE" "$SETTINGS_FILE"
                    echo -e "${YELLOW}Please manually merge the hooks from:${NC}"
                    echo "  $NEW_SETTINGS_FILE"
                fi
            else
                echo -e "${RED}Node.js not found. Cannot auto-merge.${NC}"
                echo -e "${YELLOW}Please manually merge the hooks from:${NC}"
                echo "  $NEW_SETTINGS_FILE"
            fi
            ;;
        2)
            BACKUP_FILE="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${GREEN}Backing up to $BACKUP_FILE${NC}"
            cp "$SETTINGS_FILE" "$BACKUP_FILE"
            cp "$NEW_SETTINGS_FILE" "$SETTINGS_FILE"
            echo -e "${GREEN}New settings installed.${NC}"
            ;;
        3)
            echo -e "${YELLOW}Skipping settings configuration.${NC}"
            echo -e "${YELLOW}Please manually add the hooks from:${NC}"
            echo "  $NEW_SETTINGS_FILE"
            ;;
        *)
            echo -e "${YELLOW}Invalid option. Skipping settings configuration.${NC}"
            echo -e "${YELLOW}Please manually add the hooks from:${NC}"
            echo "  $NEW_SETTINGS_FILE"
            ;;
    esac
else
    # No existing settings, install fresh
    cp "$NEW_SETTINGS_FILE" "$SETTINGS_FILE"
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
echo "  - PreToolUse: Safety validation + security warnings"
echo "  - PostToolUse: Change tracking + auto-formatting"
echo "  - Stop: Completion checklist"
echo ""
echo "Files installed to:"
echo "  - Hooks: $HOOKS_DIR/"
echo "  - Settings: $SETTINGS_FILE"
echo "  - Skill rules: $CLAUDE_DIR/skill-rules.json"
echo ""
echo -e "${YELLOW}Restart Claude Code for changes to take effect.${NC}"
