"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.projectsCommand = projectsCommand;
const chalk_1 = __importDefault(require("chalk"));
const inquirer_1 = __importDefault(require("inquirer"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs-extra"));
const logger_js_1 = require("../utils/logger.js");
const config_js_1 = require("../utils/config.js");
const shell_js_1 = require("../utils/shell.js");
function projectsCommand(program) {
    const proj = program
        .command('projects')
        .alias('p')
        .description('Manage MomenTerm projects');
    proj
        .command('list')
        .description('List all projects across all spaces')
        .action(async () => {
        const config = await (0, config_js_1.loadConfig)();
        logger_js_1.logger.header('Projects');
        if (config.spaces.length === 0) {
            logger_js_1.logger.info('No projects yet. Run: mt init [directory]');
            return;
        }
        for (const space of config.spaces) {
            console.log(`\n  ${chalk_1.default.bold.cyan(space.name)} (${space.projects.length} projects)`);
            for (const p of space.projects) {
                const aiLabel = chalk_1.default.dim(`[${p.aiTool}]`);
                const tmuxLabel = p.tmuxMode !== 'disabled' ? chalk_1.default.dim(`[tmux:${p.tmuxMode}]`) : '';
                const exists = await fs.pathExists(p.path);
                const pathColor = exists ? chalk_1.default.dim : chalk_1.default.red;
                console.log(`    ${chalk_1.default.bold(p.name)} ${aiLabel} ${tmuxLabel}`);
                console.log(`    ${pathColor(p.path)}`);
            }
        }
        logger_js_1.logger.blank();
    });
    proj
        .command('add <directory>')
        .description('Add a directory as a project')
        .action(async (directory) => {
        const targetDir = path.resolve(directory);
        if (!(await fs.pathExists(targetDir))) {
            logger_js_1.logger.error(`Directory not found: ${targetDir}`);
            return;
        }
        const answers = await inquirer_1.default.prompt([
            { type: 'input', name: 'name', message: 'Project name:', default: path.basename(targetDir) },
            { type: 'input', name: 'spaceName', message: 'Space name:', default: 'Default' },
            {
                type: 'list', name: 'aiTool', message: 'AI tool:',
                choices: [
                    { name: 'Claude Code', value: 'claude_code' },
                    { name: 'Codex', value: 'codex' },
                    { name: 'Both', value: 'both' },
                    { name: 'None', value: 'none' },
                ],
            },
            {
                type: 'list', name: 'tmuxMode', message: 'tmux mode:',
                choices: [
                    { name: 'Disabled', value: 'disabled' },
                    { name: 'New session', value: 'new_session' },
                    { name: 'Existing session', value: 'existing_session' },
                ],
            },
        ]);
        const config = await (0, config_js_1.loadConfig)();
        let space = config.spaces.find(s => s.name === answers.spaceName);
        if (!space) {
            space = { id: (0, config_js_1.generateId)(), name: answers.spaceName, projects: [] };
            config.spaces.push(space);
        }
        space.projects.push({
            id: (0, config_js_1.generateId)(),
            name: answers.name,
            path: targetDir,
            aiTool: answers.aiTool,
            tmuxMode: answers.tmuxMode,
            createdAt: new Date().toISOString(),
        });
        await (0, config_js_1.saveConfig)(config);
        logger_js_1.logger.success(`Project "${answers.name}" added to space "${answers.spaceName}"`);
    });
    proj
        .command('open <name>')
        .description('Open a project (print the cd command)')
        .option('--tab', 'Open in new iTerm2 tab (via it2 CLI)')
        .option('--window', 'Open in new iTerm2 window (via it2 CLI)')
        .action(async (name, opts) => {
        const config = await (0, config_js_1.loadConfig)();
        let found = null;
        for (const space of config.spaces) {
            const project = space.projects.find(p => p.name === name || p.id === name);
            if (project) {
                found = { spaceName: space.name, project };
                break;
            }
        }
        if (!found) {
            logger_js_1.logger.error(`Project "${name}" not found. Run: mt projects list`);
            return;
        }
        const { project } = found;
        if (opts.tab || opts.window) {
            const it2Available = await (0, shell_js_1.commandExists)('it2');
            if (it2Available) {
                const mode = opts.window ? 'window new' : 'tab new';
                console.log(`it2 ${mode} && it2 session send "cd ${project.path} && ${getAILaunchCmd(project.aiTool)}"`);
                return;
            }
            logger_js_1.logger.warn('it2 CLI not found. Printing cd command instead.');
        }
        logger_js_1.logger.success(`Opening project: ${project.name}`);
        logger_js_1.logger.blank();
        console.log(`  ${chalk_1.default.dim('Path:')} ${project.path}`);
        console.log(`  ${chalk_1.default.dim('AI Tool:')} ${project.aiTool}`);
        if (project.tmuxMode !== 'disabled') {
            console.log(`  ${chalk_1.default.dim('tmux:')} ${project.tmuxMode}`);
        }
        logger_js_1.logger.blank();
        // Print the command to run
        const cmd = buildOpenCommand(project);
        console.log(chalk_1.default.bold('Run this command:'));
        console.log(`  ${chalk_1.default.cyan(cmd)}`);
    });
    proj
        .command('remove <name>')
        .description('Remove a project from registry')
        .action(async (name) => {
        const config = await (0, config_js_1.loadConfig)();
        let removed = false;
        for (const space of config.spaces) {
            const idx = space.projects.findIndex(p => p.name === name || p.id === name);
            if (idx !== -1) {
                space.projects.splice(idx, 1);
                removed = true;
                break;
            }
        }
        if (!removed) {
            logger_js_1.logger.error(`Project "${name}" not found.`);
            return;
        }
        await (0, config_js_1.saveConfig)(config);
        logger_js_1.logger.success(`Project "${name}" removed from registry.`);
    });
}
function getAILaunchCmd(tool) {
    switch (tool) {
        case 'claude_code': return 'claude';
        case 'codex': return 'codex';
        case 'both': return 'claude & codex';
        default: return '';
    }
}
function buildOpenCommand(project) {
    const parts = [`cd "${project.path}"`];
    if (project.tmuxMode === 'new_session') {
        parts.push(`tmux new-session -s "${project.name.replace(/\s+/g, '-').toLowerCase()}"`);
    }
    else if (project.tmuxMode === 'existing_session') {
        parts.push(`tmux attach -t "${project.tmuxSession ?? project.name.replace(/\s+/g, '-').toLowerCase()}"`);
    }
    const aiCmd = getAILaunchCmd(project.aiTool);
    if (aiCmd)
        parts.push(aiCmd);
    return parts.join(' && ');
}
//# sourceMappingURL=projects.js.map