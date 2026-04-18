import { Command } from 'commander';
import inquirer from 'inquirer';
import * as path from 'path';
import * as fs from 'fs-extra';
import ora from 'ora';
import { logger } from '../utils/logger.js';
import { loadConfig, saveConfig, generateId } from '../utils/config.js';
import { isGitRepo, commandExists } from '../utils/shell.js';
import type { AITool, TmuxMode } from '../types.js';

export function initCommand(program: Command): void {
  program
    .command('init [directory]')
    .description('Initialize MomenTerm project in current or specified directory')
    .option('--harness', 'Also run harness engineering setup')
    .option('--quick', 'Skip interactive prompts, use defaults')
    .action(async (directory?: string, opts?: { harness?: boolean; quick?: boolean }) => {
      const targetDir = path.resolve(directory ?? process.cwd());

      logger.header('MomenTerm Project Init');

      if (!(await fs.pathExists(targetDir))) {
        logger.error(`Directory not found: ${targetDir}`);
        process.exit(1);
      }

      const isGit = await isGitRepo(targetDir);
      if (!isGit) {
        logger.warn('This directory is not a git repository. Proceeding anyway.');
      }

      let projectName = path.basename(targetDir);
      let aiTool: AITool = 'claude_code';
      let tmuxMode: TmuxMode = 'disabled';
      let spaceName = 'Default';

      if (!opts?.quick) {
        const answers = await inquirer.prompt([
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
        aiTool = answers.aiTool as AITool;
        tmuxMode = answers.tmuxMode as TmuxMode;
      }

      const spinner = ora('Saving project configuration…').start();
      const config = await loadConfig();

      let space = config.spaces.find(s => s.name === spaceName);
      if (!space) {
        space = { id: generateId(), name: spaceName, projects: [] };
        config.spaces.push(space);
      }

      const existing = space.projects.find(p => path.resolve(p.path) === targetDir);
      if (existing) {
        spinner.warn(`Project already registered in space "${spaceName}"`);
      } else {
        space.projects.push({
          id: generateId(),
          name: projectName,
          path: targetDir,
          aiTool,
          tmuxMode,
          createdAt: new Date().toISOString(),
        });
        await saveConfig(config);
        spinner.succeed(`Project "${projectName}" saved to space "${spaceName}"`);
      }

      // Create .agentignore if missing
      const agentignorePath = path.join(targetDir, '.agentignore');
      if (!(await fs.pathExists(agentignorePath))) {
        await fs.writeFile(agentignorePath, AGENTIGNORE_TEMPLATE);
        logger.step('Created .agentignore');
      }

      // Create/update handoff.md
      const handoffPath = path.join(targetDir, 'handoff.md');
      if (!(await fs.pathExists(handoffPath))) {
        await fs.writeFile(handoffPath, handoffTemplate(projectName));
        logger.step('Created handoff.md');
      }

      // Check AI tools
      const claudeInstalled = await commandExists('claude');
      const codexInstalled = await commandExists('codex');
      logger.blank();
      logger.section('AI Tool Status', [
        `Claude Code: ${claudeInstalled ? '✓ installed' : '✗ not found (npm i -g @anthropic-ai/claude-code)'}`,
        `Codex: ${codexInstalled ? '✓ installed' : '✗ not found (npm i -g @openai/codex)'}`,
      ]);

      logger.blank();
      logger.success('Project initialized! Run `mt doctor` to check environment health.');
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

function handoffTemplate(projectName: string): string {
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
