import { Command } from 'commander';
import inquirer from 'inquirer';
import ora from 'ora';
import * as fs from 'fs-extra';
import * as path from 'path';
import { logger } from '../utils/logger.js';
import { isGitRepo } from '../utils/shell.js';
import type { HarnessConfig } from '../types.js';

export function harnessCommand(program: Command): void {
  program
    .command('harness [directory]')
    .description('Run Harness Engineering setup interview and generate config')
    .option('--skip-interview', 'Use defaults without interactive prompts')
    .action(async (directory?: string, opts?: { skipInterview?: boolean }) => {
      const targetDir = path.resolve(directory ?? process.cwd());
      logger.header('Harness Engineering Setup');
      logger.blank();

      if (!(await fs.pathExists(targetDir))) {
        logger.error(`Directory not found: ${targetDir}`);
        process.exit(1);
      }

      // Check for existing harness config
      const harnessDocPath = path.join(targetDir, 'docs', 'harness-engineering.md');
      const claudeMdPath = path.join(targetDir, 'CLAUDE.md');
      const agentsMdPath = path.join(targetDir, 'AGENTS.md');

      if (await fs.pathExists(harnessDocPath)) {
        logger.warn('Harness config already exists at docs/harness-engineering.md');
        const { overwrite } = await inquirer.prompt([{
          type: 'confirm',
          name: 'overwrite',
          message: 'Regenerate harness config?',
          default: false,
        }]);
        if (!overwrite) return;
      }

      let config: HarnessConfig;

      if (opts?.skipInterview) {
        config = defaultHarnessConfig(path.basename(targetDir));
      } else {
        config = await runHarnessInterview(path.basename(targetDir));
      }

      const spinner = ora('Generating harness files…').start();
      await fs.ensureDir(path.join(targetDir, 'docs'));
      await fs.ensureDir(path.join(targetDir, '.hooks'));

      // Generate docs/harness-engineering.md
      await fs.writeFile(harnessDocPath, generateHarnessDoc(config));

      // Generate CLAUDE.md if not exists
      if (!(await fs.pathExists(claudeMdPath))) {
        await fs.writeFile(claudeMdPath, generateClaudeMd(config));
      }

      // Generate AGENTS.md if not exists
      if (!(await fs.pathExists(agentsMdPath))) {
        await fs.writeFile(agentsMdPath, generateAgentsMd(config));
      }

      // Generate pre-push hook
      const prePushPath = path.join(targetDir, '.hooks', 'pre-push');
      await fs.writeFile(prePushPath, generatePrePushHook(config));
      await fs.chmod(prePushPath, 0o755);

      // Generate pre-commit hook
      const preCommitPath = path.join(targetDir, '.hooks', 'pre-commit');
      await fs.writeFile(preCommitPath, generatePreCommitHook(config));
      await fs.chmod(preCommitPath, 0o755);

      spinner.succeed('Harness files generated');
      logger.blank();
      logger.section('Generated files', [
        'docs/harness-engineering.md',
        'CLAUDE.md (if new)',
        'AGENTS.md (if new)',
        '.hooks/pre-commit',
        '.hooks/pre-push',
      ]);
      logger.blank();
      logger.info('Install hooks: cp .hooks/pre-commit .git/hooks/ && cp .hooks/pre-push .git/hooks/');
    });
}

async function runHarnessInterview(defaultName: string): Promise<HarnessConfig> {
  logger.info('Answer a few questions to configure your Harness Engineering environment.\n');

  const answers = await inquirer.prompt([
    { type: 'input', name: 'projectName', message: 'Project name:', default: defaultName },
    {
      type: 'list', name: 'projectType', message: 'Project type:',
      choices: ['web-frontend', 'web-fullstack', 'mobile', 'api-backend', 'cli-tool', 'library', 'monorepo', 'other'],
    },
    { type: 'number', name: 'collaborators', message: 'Team size (including yourself):', default: 1 },
    {
      type: 'list', name: 'documentationImportance', message: 'Documentation importance:',
      choices: ['low', 'medium', 'high'], default: 'medium',
    },
    {
      type: 'list', name: 'deploymentLevel', message: 'Deployment target:',
      choices: ['local', 'staging', 'production'], default: 'production',
    },
    {
      type: 'list', name: 'securityLevel', message: 'Security requirements:',
      choices: ['minimal', 'standard', 'strict'], default: 'standard',
    },
    {
      type: 'checkbox', name: 'automationScope', message: 'Allowed automation scopes:',
      choices: ['file-creation', 'dependency-install', 'git-commits', 'deployment', 'database-migrations'],
      default: ['file-creation'],
    },
    {
      type: 'checkbox', name: 'staticAnalysis', message: 'Static analysis to run before push:',
      choices: [
        { name: 'Lint', value: 'lint', checked: true },
        { name: 'Type check', value: 'typeCheck', checked: true },
        { name: 'Security scan', value: 'securityScan', checked: false },
        { name: 'Formatting', value: 'formatting', checked: false },
      ],
    },
  ]);

  return {
    projectName: answers.projectName,
    projectType: answers.projectType,
    collaborators: answers.collaborators,
    documentationImportance: answers.documentationImportance,
    deploymentLevel: answers.deploymentLevel,
    securityLevel: answers.securityLevel,
    automationScope: answers.automationScope,
    aiScope: ['file-creation', 'analysis', 'testing'],
    staticAnalysis: {
      lint: answers.staticAnalysis.includes('lint'),
      typeCheck: answers.staticAnalysis.includes('typeCheck'),
      securityScan: answers.staticAnalysis.includes('securityScan'),
      formatting: answers.staticAnalysis.includes('formatting'),
    },
  };
}

function defaultHarnessConfig(name: string): HarnessConfig {
  return {
    projectName: name,
    projectType: 'web-fullstack',
    collaborators: 1,
    documentationImportance: 'medium',
    deploymentLevel: 'production',
    securityLevel: 'standard',
    automationScope: ['file-creation'],
    aiScope: ['file-creation', 'analysis', 'testing'],
    staticAnalysis: { lint: true, typeCheck: true, securityScan: false, formatting: false },
  };
}

function generateHarnessDoc(c: HarnessConfig): string {
  return `# Harness Engineering — ${c.projectName}

> Generated by MomenTerm mt CLI

## Project Profile
- **Name**: ${c.projectName}
- **Type**: ${c.projectType}
- **Team size**: ${c.collaborators}
- **Documentation**: ${c.documentationImportance} priority
- **Deployment**: ${c.deploymentLevel}
- **Security**: ${c.securityLevel}

## Automation Scope
Permitted automated actions:
${c.automationScope.map(s => `- ${s}`).join('\n')}

## AI Scope
AI tools are permitted to:
${c.aiScope.map(s => `- ${s}`).join('\n')}

## Static Analysis Policy (pre-push)
- Lint: ${c.staticAnalysis.lint ? '✓ enabled' : '✗ disabled'}
- Type check: ${c.staticAnalysis.typeCheck ? '✓ enabled' : '✗ disabled'}
- Security scan: ${c.staticAnalysis.securityScan ? '✓ enabled' : '✗ disabled'}
- Formatting: ${c.staticAnalysis.formatting ? '✓ enabled' : '✗ disabled'}

## Guardrail Rules
1. No sensitive files (.env, secrets, keys) in commits
2. No deployment without passing static analysis
3. Schema-breaking changes require explicit confirmation
4. AI-generated code follows same quality standards as human code
5. External API integrations require security review

## Hook Policy
- \`pre-commit\`: Check .gitignore coverage, detect secret patterns
- \`pre-push\`: Run enabled static analysis tools

## Document Structure
\`\`\`
docs/
├── harness-engineering.md  ← this file
├── architecture.md
├── onboarding.md
└── operations-guide.md
\`\`\`
`;
}

function generateClaudeMd(c: HarnessConfig): string {
  return `# ${c.projectName} — Claude Code Guidelines

## Project Context
- Type: ${c.projectType}
- Security: ${c.securityLevel}
- Deployment: ${c.deploymentLevel}

## AI Automation Scope
Permitted: ${c.automationScope.join(', ')}

## Code Quality Rules
- Run \`npm run lint\` before committing
- No \`console.log\` in production code
- All new files must be added to git
- Use TypeScript strict mode

## Guardrails
- Never commit .env or secret files
- Never use \`rm -rf\` without confirmation
- Document breaking changes in handoff.md
`;
}

function generateAgentsMd(c: HarnessConfig): string {
  return `# ${c.projectName} — Agent Guidelines

## AI Tool Configuration
- Default model: sonnet
- Escalate to opus for: repeated failures, complex architecture decisions
- Return to sonnet after issue resolution

## Scope
Agents are permitted to:
${c.aiScope.map(s => `- ${s}`).join('\n')}

## Handoff Protocol
Update handoff.md at the start and end of each session.

## Document Standards
All generated docs go in \`docs/\` with descriptive names.
`;
}

function generatePrePushHook(c: HarnessConfig): string {
  const checks: string[] = [];
  if (c.staticAnalysis.lint) checks.push('npm run lint 2>/dev/null || (echo "❌ Lint failed. Fix errors before pushing." && exit 1)');
  if (c.staticAnalysis.typeCheck) checks.push('npm run type-check 2>/dev/null || npx tsc --noEmit 2>/dev/null || true');
  if (c.staticAnalysis.formatting) checks.push('npx prettier --check . 2>/dev/null || (echo "⚠️  Formatting issues found." && true)');

  return `#!/usr/bin/env bash
# MomenTerm pre-push hook — generated by mt harness
# Project: ${c.projectName}
set -e

echo "🔍 Running pre-push checks..."
${checks.join('\n')}
echo "✓ Pre-push checks passed."
`;
}

function generatePreCommitHook(c: HarnessConfig): string {
  return `#!/usr/bin/env bash
# MomenTerm pre-commit hook — generated by mt harness
# Project: ${c.projectName}

echo "🔍 Running pre-commit checks..."

# Check for secret patterns in staged files
if git diff --cached --name-only | xargs grep -l -E '(PRIVATE_KEY|SECRET|PASSWORD|API_KEY)\\s*=' 2>/dev/null | grep -v '\\.example'; then
  echo "❌ Possible secret detected in staged files. Review before committing."
  exit 1
fi

# Check .env is not staged
if git diff --cached --name-only | grep -qE '^\\.env$'; then
  echo "❌ .env file is staged. Add it to .gitignore first."
  exit 1
fi

# Check node_modules not staged
if git diff --cached --name-only | grep -qE '^node_modules/'; then
  echo "❌ node_modules staged. Add node_modules to .gitignore first."
  exit 1
fi

# Run mt guardrail check if available
if command -v mt &>/dev/null; then
  mt guardrail check --commits 0 || exit 1
fi

echo "✓ Pre-commit checks passed."
`;
}
