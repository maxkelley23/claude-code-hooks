#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync, statSync, appendFileSync, mkdirSync } from 'fs';
import { join, basename, dirname } from 'path';
import { homedir } from 'os';

interface HookInput {
    session_id: string;
    transcript_path: string;
    cwd: string;
    permission_mode: string;
    prompt: string;
}

interface PromptTriggers {
    keywords?: string[];
    intentPatterns?: string[];
}

interface SkillRule {
    type: 'guardrail' | 'domain';
    enforcement?: 'block' | 'suggest' | 'warn';
    priority: 'critical' | 'high' | 'medium' | 'low';
    description?: string;
    promptTriggers?: PromptTriggers;
}

interface SkillRules {
    version: string;
    skills: Record<string, SkillRule>;
}

interface MatchedSkill {
    name: string;
    matchType: 'keyword' | 'intent';
    config: SkillRule;
    path?: string;
    content?: string;
}

// Debug logging - controlled by environment variable
const DEBUG = process.env.CLAUDE_HOOKS_DEBUG === 'true';
const homeDir = process.env.HOME || process.env.USERPROFILE || homedir() || '';
const logDir = join(homeDir, '.claude', 'logs');
const logFile = join(logDir, 'skill-activation.log');

function log(message: string): void {
    if (!DEBUG) return;
    try {
        if (!existsSync(logDir)) {
            mkdirSync(logDir, { recursive: true });
        }
        const timestamp = new Date().toISOString();
        appendFileSync(logFile, `[${timestamp}] ${message}\n`);
    } catch {
        // Silently ignore logging errors
    }
}

// Recursively search for SKILL.md files
function findSkillFiles(dir: string, results: Map<string, string> = new Map()): Map<string, string> {
    try {
        const entries = readdirSync(dir);
        for (const entry of entries) {
            const fullPath = join(dir, entry);
            try {
                const stat = statSync(fullPath);
                if (stat.isDirectory()) {
                    findSkillFiles(fullPath, results);
                } else if (entry.toLowerCase() === 'skill.md') {
                    const skillName = basename(dirname(fullPath));
                    // Prefer cache paths (active installed versions)
                    if (!results.has(skillName) || fullPath.includes('cache')) {
                        results.set(skillName, fullPath);
                    }
                }
            } catch {
                // Skip files we can't access
            }
        }
    } catch {
        // Skip directories we can't access
    }
    return results;
}

// Read and optionally truncate skill content
function readSkillContent(path: string, maxChars: number = 8000): string {
    try {
        const content = readFileSync(path, 'utf-8');
        if (content.length > maxChars) {
            const truncated = content.substring(0, maxChars);
            const lastHeader = truncated.lastIndexOf('\n## ');
            const lastParagraph = truncated.lastIndexOf('\n\n');
            const breakPoint = lastHeader > maxChars * 0.7 ? lastHeader : lastParagraph;
            return content.substring(0, breakPoint > 0 ? breakPoint : maxChars) + '\n\n... [truncated for brevity]';
        }
        return content;
    } catch {
        return '';
    }
}

// Valid priority values for validation
const VALID_PRIORITIES = ['critical', 'high', 'medium', 'low'] as const;
type Priority = typeof VALID_PRIORITIES[number];

function isValidPriority(priority: string): priority is Priority {
    return VALID_PRIORITIES.includes(priority as Priority);
}

async function main(): Promise<void> {
    log('=== Hook triggered ===');

    try {
        const input = readFileSync(0, 'utf-8');
        if (!input.trim()) {
            log('No input received, exiting');
            process.exit(0);
        }

        const data: HookInput = JSON.parse(input);
        const prompt = (data.prompt || '').toLowerCase();

        log(`Prompt received: "${prompt.substring(0, 100)}${prompt.length > 100 ? '...' : ''}"`);

        if (!prompt) {
            log('Empty prompt, exiting');
            process.exit(0);
        }

        // Load skill rules
        const projectDir = process.env.CLAUDE_PROJECT_DIR || '';

        const possiblePaths = [
            join(homeDir, '.claude', 'skill-rules.json'),
            join(homeDir, '.claude', 'skills', 'skill-rules.json'),
            join(projectDir, '.claude', 'skills', 'skill-rules.json'),
            join(projectDir, '.claude', 'skill-rules.json'),
        ];

        let rulesPath = '';
        for (const p of possiblePaths) {
            try {
                if (p && existsSync(p)) {
                    rulesPath = p;
                    break;
                }
            } catch {
                // Skip inaccessible paths
            }
        }

        if (!rulesPath) {
            log('No skill-rules.json found, exiting');
            process.exit(0);
        }

        log(`Using rules from: ${rulesPath}`);

        const rules: SkillRules = JSON.parse(readFileSync(rulesPath, 'utf-8'));

        // Build skill file index
        const pluginsDir = join(homeDir, '.claude', 'plugins');
        const skillFiles = findSkillFiles(pluginsDir);

        // Also check user skills directory
        const userSkillsDir = join(homeDir, '.claude', 'skills');
        if (existsSync(userSkillsDir)) {
            findSkillFiles(userSkillsDir, skillFiles);
        }

        log(`Found ${skillFiles.size} skill files in plugins`);

        const matchedSkills: MatchedSkill[] = [];

        // Check each skill for matches
        for (const [skillName, config] of Object.entries(rules.skills)) {
            // Validate priority - skip skills with invalid priority
            if (!isValidPriority(config.priority)) {
                log(`WARNING: Skill "${skillName}" has invalid priority "${config.priority}", skipping`);
                continue;
            }

            const triggers = config.promptTriggers;
            if (!triggers) continue;

            let matched = false;
            let matchType: 'keyword' | 'intent' = 'keyword';
            let matchedKeyword = '';

            // Keyword matching
            if (triggers.keywords) {
                for (const kw of triggers.keywords) {
                    if (prompt.includes(kw.toLowerCase())) {
                        matched = true;
                        matchType = 'keyword';
                        matchedKeyword = kw;
                        break;
                    }
                }
            }

            // Intent pattern matching (only if not already matched by keyword)
            if (!matched && triggers.intentPatterns) {
                const intentMatch = triggers.intentPatterns.some(pattern => {
                    try {
                        const regex = new RegExp(pattern, 'i');
                        return regex.test(prompt);
                    } catch (e) {
                        log(`WARNING: Invalid regex pattern "${pattern}" for skill "${skillName}": ${e}`);
                        return false;
                    }
                });
                if (intentMatch) {
                    matched = true;
                    matchType = 'intent';
                    matchedKeyword = '[pattern]';
                }
            }

            if (matched) {
                const skillPath = skillFiles.get(skillName);
                log(`MATCHED: ${skillName} (${matchType}: "${matchedKeyword}", priority: ${config.priority}, path: ${skillPath ? 'found' : 'NOT FOUND'})`);

                const skill: MatchedSkill = {
                    name: skillName,
                    matchType,
                    config,
                    path: skillPath
                };

                // For critical/high priority, load the content directly
                if (skillPath && (config.priority === 'critical' || config.priority === 'high')) {
                    skill.content = readSkillContent(skillPath);
                    log(`  -> Content loaded: ${skill.content.length} chars`);
                }

                matchedSkills.push(skill);
            }
        }

        if (matchedSkills.length === 0) {
            log('No skills matched, exiting');
            process.exit(0);
        }

        log(`Total matched: ${matchedSkills.length} skills`);

        // Filter to only skills with paths
        const skillsWithPaths = matchedSkills.filter(s => s.path);
        if (skillsWithPaths.length === 0) {
            log('No skills with valid paths, exiting');
            process.exit(0);
        }

        // Sort by priority (with validation already done above)
        const priorityOrder: Record<Priority, number> = { critical: 0, high: 1, medium: 2, low: 3 };
        skillsWithPaths.sort((a, b) =>
            priorityOrder[a.config.priority as Priority] - priorityOrder[b.config.priority as Priority]
        );

        // Group by priority
        const critical = skillsWithPaths.filter(s => s.config.priority === 'critical');
        const high = skillsWithPaths.filter(s => s.config.priority === 'high');
        const medium = skillsWithPaths.filter(s => s.config.priority === 'medium');
        const low = skillsWithPaths.filter(s => s.config.priority === 'low');

        log(`By priority - Critical: ${critical.length}, High: ${high.length}, Medium: ${medium.length}, Low: ${low.length}`);

        // Limit injected content to avoid context bloat
        const maxInjectedSkills = 3;
        const skillsToInject = [...critical, ...high].slice(0, maxInjectedSkills);
        const skillsWithContent = skillsToInject.filter(s => s.content);

        log(`Injecting content for ${skillsWithContent.length} skills: ${skillsWithContent.map(s => s.name).join(', ')}`);

        let output = '\n';
        output += '\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557\n';
        output += '\u2551                    SKILL CONTEXT LOADED                          \u2551\n';
        output += '\u255A\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255D\n\n';

        // Output injected skill content (critical + high priority)
        if (skillsWithContent.length > 0) {
            output += '\u2501'.repeat(68) + '\n';
            output += '  APPLY THESE SKILLS TO YOUR RESPONSE:\n';
            output += '\u2501'.repeat(68) + '\n\n';

            for (const skill of skillsWithContent) {
                // Truncate skill name to fit in box (max 55 chars)
                const displayName = skill.name.toUpperCase().substring(0, 55).padEnd(55);
                output += '\u250C' + '\u2500'.repeat(65) + '\u2510\n';
                output += `\u2502 SKILL: ${displayName}\u2502\n`;
                output += '\u2514' + '\u2500'.repeat(65) + '\u2518\n\n';
                output += skill.content + '\n\n';
                output += '\u2500'.repeat(68) + '\n\n';
            }
        }

        // Show remaining high-priority skills that weren't injected (if any)
        const remainingHigh = [...critical, ...high].slice(maxInjectedSkills).filter(s => s.path);
        if (remainingHigh.length > 0) {
            output += '\uD83D\uDCCC ADDITIONAL HIGH-PRIORITY SKILLS (use view tool if needed):\n';
            remainingHigh.forEach(s => {
                output += `   \u2022 ${s.name}: ${s.path}\n`;
            });
            output += '\n';
        }

        // Show medium/low priority as optional references
        if (medium.length > 0 || low.length > 0) {
            output += '\uD83D\uDCCE OPTIONAL REFERENCE SKILLS (view if relevant):\n';
            [...medium, ...low].forEach(s => {
                const priority = s.config.priority === 'medium' ? '\uD83D\uDFE1' : '\uD83D\uDFE2';
                output += `   ${priority} ${s.name}\n`;
            });
            output += '\n';
        }

        output += '\u2550'.repeat(66) + '\n';

        log(`Output generated: ${output.length} chars`);
        log('=== Hook complete ===\n');

        console.log(output);
        process.exit(0);
    } catch (err) {
        log(`ERROR: ${err}`);
        process.exit(0);
    }
}

main().catch((err) => {
    log(`UNCAUGHT ERROR: ${err}`);
    process.exit(0);
});
