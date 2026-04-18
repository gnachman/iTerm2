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
exports.initCommand = initCommand;
const inquirer_1 = __importDefault(require("inquirer"));
const path = __importStar(require("path"));
const fs = __importStar(require("fs-extra"));
const ora_1 = __importDefault(require("ora"));
const logger_js_1 = require("../utils/logger.js");
const config_js_1 = require("../utils/config.js");
const shell_js_1 = require("../utils/shell.js");
function initCommand(program) {
    program
        .command('init [directory]')
        .description('Initialize MomenTerm project in current or specified directory')
        .option('--harness', 'Also run harness engineering setup')
        .option('--quick', 'Skip interactive prompts, use defaults')
        .action(async (directory, opts) => {
        const targetDir = path.resolve(directory ?? process.cwd());
        logger_js_1.logger.header('MomenTerm Project Init');
        if (!(await fs.pathExists(targetDir))) {
            logger_js_1.logger.error(`Directory not found: ${targetDir}`);
            process.exit(1);
        }
        const isGit = await (0, shell_js_1.isGitRepo)(targetDir);
        if (!isGit) {
            logger_js_1.logger.warn('This directory is not a git repository. Proceeding anyway.');
        }
        let projectName = path.basename(targetDir);
        let aiTool = 'claude_code';
        let tmuxMode = 'disabled';
        let spaceName = 'Default';
        if (!opts?.quick) {
            const answers = await inquirer_1.default.prompt([
                {
                    type: 'input',
                    name: 'projectName',
                    message: 'Project name:',
                    default: projectName,
                },
                {
                    type: 'input',
                    name: 'spaceName',
                    message: 'Workspace (space) name:',
                    default: 'Default',
                },
                {
                    type: 'list',
                    name: 'aiTool',
                    message: 'AI tool:',
                    choices: [
                        { name: 'Claude Code', value: 'claude_code' },
                        { name: 'Codex', value: 'codex' },
                        { name: 'Both', value: 'both' },
                        { name: 'None', value: 'none' },
                    ],
                    default: 'claude_code',
                },
                {
                    type: 'list',
                    name: 'tmuxMode',
                    message: 'tmux mode:',
                    choices: [
                        { name: 'Disabled', value: 'disabled' },
                        { name: 'New session', value: 'new_session' },
                        { name: 'Connect to existing session', value: 'existing_session' },
                    ],
                    default: 'disabled',
                },
            ]);
            projectName = answers.projectName;
            spaceName = answers.spaceName;
            aiTool = answers.aiTool;
            tmuxMode = answers.tmuxMode;
        }
        const spinner = (0, ora_1.default)('Saving project configuration…').start();
        const config = await (0, config_js_1.loadConfig)();
        let space = config.spaces.find(s => s.name === spaceName);
        if (!space) {
            space = { id: (0, config_js_1.generateId)(), name: spaceName, projects: [] };
            config.spaces.push(space);
        }
        const existing = space.projects.find(p => path.resolve(p.path) === targetDir);
        if (existing) {
            spinner.warn(`Project already registered in space "${spaceName}"`);
        }
        else {
            space.projects.push({
                id: (0, config_js_1.generateId)(),
                name: projectName,
                path: targetDir,
                aiTool,
                tmuxMode,
                createdAt: new Date().toISOString(),
            });
            await (0, config_js_1.saveConfig)(config);
            spinner.succeed(`Project "${projectName}" saved to space "${spaceName}"`);
        }
        // Create .agentignore if missing
        const agentignorePath = path.join(targetDir, '.agentignore');
        if (!(await fs.pathExists(agentignorePath))) {
            await fs.writeFile(agentignorePath, AGENTIGNORE_TEMPLATE);
            logger_js_1.logger.step('Created .agentignore');
        }
        // Create/update handoff.md
        const handoffPath = path.join(targetDir, 'handoff.md');
        if (!(await fs.pathExists(handoffPath))) {
            await fs.writeFile(handoffPath, handoffTemplate(projectName));
            logger_js_1.logger.step('Created handoff.md');
        }
        // Check AI tools
        const claudeInstalled = await (0, shell_js_1.commandExists)('claude');
        const codexInstalled = await (0, shell_js_1.commandExists)('codex');
        logger_js_1.logger.blank();
        logger_js_1.logger.section('AI Tool Status', [
            `Claude Code: ${claudeInstalled ? '✓ installed' : '✗ not found (npm i -g @anthropic-ai/claude-code)'}`,
            `Codex: ${codexInstalled ? '✓ installed' : '✗ not found (npm i -g @openai/codex)'}`,
        ]);
        logger_js_1.logger.blank();
        logger_js_1.logger.success('Project initialized! Run `mt doctor` to check environment health.');
    });
}
const AGENTIGNORE_TEMPLATE = `# .agentignore — paths excluded from AI context scanning
# AI tools like Claude Code and Codex will skip these when building context.

# Build artifacts
.next/
dist/
build/
out/

# Dependencies
node_modules/
.pnpm-store/
vendor/

# Caches
.cache/
.turbo/
.parcel-cache/
__pycache__/
*.pyc
.mypy_cache/
.pytest_cache/

# Coverage & test artifacts
coverage/
.nyc_output/

# Logs
*.log
logs/

# OS temporaries
.DS_Store
Thumbs.db

# Auto-generated code (review before excluding)
# generated/
# src/generated/
`;
function handoffTemplate(projectName) {
    const now = new Date().toLocaleString('ko-KR');
    return `# Handoff — ${projectName}

> 마지막 업데이트: ${now}

## 현재 목표
<!-- 지금 진행 중인 작업 목표를 한 줄로 -->

## 최근 완료
- [ ] 프로젝트 초기화 (mt init)

## 진행 중
<!-- 현재 작업 중인 항목 -->

## 막힌 이슈
<!-- 해결이 필요한 이슈 -->

## 다음 액션
<!-- 다음 세션에서 바로 시작할 항목 -->

## 참고 문서
<!-- 관련 문서 경로 -->

## 관련 브랜치
<!-- 현재 feature 브랜치 -->

## 주의사항
<!-- 작업 중 주의해야 할 내용 -->
`;
}
//# sourceMappingURL=init.js.map