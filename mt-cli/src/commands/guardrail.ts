import { Command } from 'commander';
import chalk from 'chalk';
import * as fs from 'fs-extra';
import * as path from 'path';
import { logger } from '../utils/logger.js';
import { runShell } from '../utils/shell.js';

interface GuardrailViolation {
  rule: string;
  severity: 'error' | 'warn';
  file?: string;
  detail: string;
}

interface GuardrailRule {
  id: string;
  description: string;
  severity: 'error' | 'warn';
  check: (targetDir: string, stagedFiles: string[], recentCommitFiles: string[]) => Promise<GuardrailViolation[]>;
}

export function guardrailCommand(program: Command): void {
  const gr = program
    .command('guardrail')
    .alias('guard')
    .description('Guardrail deviation detection — check project for AI scope violations');

  gr
    .command('check [directory]')
    .description('Scan staged files and recent commits for guardrail violations')
    .option('--commits <n>', 'Number of recent commits to scan', '5')
    .action(async (directory?: string, opts?: { commits?: string }) => {
      const targetDir = path.resolve(directory ?? process.cwd());
      logger.header('Guardrail Check');

      const stagedFiles = await getStagedFiles(targetDir);
      const recentFiles = await getRecentCommitFiles(targetDir, Number(opts?.commits ?? 5));

      logger.info(`Staged files: ${stagedFiles.length} | Recent commit files: ${recentFiles.length}`);
      logger.blank();

      const allViolations: GuardrailViolation[] = [];
      for (const rule of GUARDRAIL_RULES) {
        const violations = await rule.check(targetDir, stagedFiles, recentFiles);
        allViolations.push(...violations);
      }

      if (allViolations.length === 0) {
        logger.success('No guardrail violations detected.');
        return;
      }

      const errors = allViolations.filter(v => v.severity === 'error');
      const warns = allViolations.filter(v => v.severity === 'warn');

      if (errors.length > 0) {
        logger.section('Errors (must fix)', []);
        for (const v of errors) {
          console.log(`  ${chalk.red('✗')} ${chalk.bold(v.rule)}`);
          console.log(`    ${chalk.dim(v.detail)}${v.file ? chalk.dim(' — ' + v.file) : ''}`);
        }
        logger.blank();
      }

      if (warns.length > 0) {
        logger.section('Warnings (review)', []);
        for (const v of warns) {
          console.log(`  ${chalk.yellow('⚠')} ${chalk.bold(v.rule)}`);
          console.log(`    ${chalk.dim(v.detail)}${v.file ? chalk.dim(' — ' + v.file) : ''}`);
        }
        logger.blank();
      }

      logger.blank();
      if (errors.length > 0) {
        logger.error(`${errors.length} error(s), ${warns.length} warning(s). Fix errors before committing.`);
        process.exitCode = 1;
      } else {
        logger.warn(`${warns.length} warning(s). Review before committing.`);
      }
    });

  gr
    .command('report [directory]')
    .description('Generate a guardrail compliance report')
    .action(async (directory?: string) => {
      const targetDir = path.resolve(directory ?? process.cwd());
      logger.header('Guardrail Compliance Report');

      const stagedFiles = await getStagedFiles(targetDir);
      const recentFiles = await getRecentCommitFiles(targetDir, 10);
      const allViolations: GuardrailViolation[] = [];

      for (const rule of GUARDRAIL_RULES) {
        const violations = await rule.check(targetDir, stagedFiles, recentFiles);
        allViolations.push(...violations);
      }

      const score = Math.max(0, 100 - allViolations.filter(v => v.severity === 'error').length * 20 - allViolations.filter(v => v.severity === 'warn').length * 5);
      const grade = score >= 90 ? 'A' : score >= 75 ? 'B' : score >= 60 ? 'C' : 'F';

      const reportPath = path.join(targetDir, '.claude', 'guardrail-report.json');
      await fs.ensureDir(path.join(targetDir, '.claude'));
      await fs.writeJson(reportPath, {
        generatedAt: new Date().toISOString(),
        score,
        grade,
        rulesChecked: GUARDRAIL_RULES.length,
        violations: allViolations,
      }, { spaces: 2 });

      const gradeColor = grade === 'A' ? chalk.green : grade === 'B' ? chalk.cyan : grade === 'C' ? chalk.yellow : chalk.red;
      console.log(`  Compliance Score: ${gradeColor.bold(`${score}/100 (${grade})`)}`);
      console.log(`  Rules checked:   ${GUARDRAIL_RULES.length}`);
      console.log(`  Violations:      ${allViolations.length} (${allViolations.filter(v => v.severity === 'error').length} errors)`);
      logger.blank();
      logger.success(`Report saved: .claude/guardrail-report.json`);
    });

  gr
    .command('rules')
    .description('List all guardrail rules')
    .action(() => {
      logger.header('Guardrail Rules');
      logger.blank();
      for (const rule of GUARDRAIL_RULES) {
        const icon = rule.severity === 'error' ? chalk.red('✗') : chalk.yellow('⚠');
        console.log(`  ${icon} ${chalk.bold(rule.id)}`);
        console.log(`    ${chalk.dim(rule.description)}`);
        console.log();
      }
    });
}

// ── helpers ──────────────────────────────────────────────────────────────────

async function getStagedFiles(dir: string): Promise<string[]> {
  const result = await runShell('git', ['diff', '--cached', '--name-only'], dir);
  return result.exitCode === 0
    ? result.stdout.split('\n').filter(Boolean)
    : [];
}

async function getRecentCommitFiles(dir: string, n: number): Promise<string[]> {
  const result = await runShell('git', ['diff', '--name-only', `HEAD~${n}`, 'HEAD'], dir);
  return result.exitCode === 0
    ? result.stdout.split('\n').filter(Boolean)
    : [];
}

async function grepFiles(dir: string, files: string[], pattern: RegExp): Promise<string[]> {
  const matches: string[] = [];
  for (const file of files) {
    const fullPath = path.join(dir, file);
    if (!(await fs.pathExists(fullPath))) continue;
    try {
      const content = await fs.readFile(fullPath, 'utf-8');
      if (pattern.test(content)) matches.push(file);
    } catch {
      // binary or unreadable
    }
  }
  return matches;
}

// ── guardrail rules ───────────────────────────────────────────────────────────

const GUARDRAIL_RULES: GuardrailRule[] = [
  {
    id: 'no-secrets-staged',
    description: 'Staged files must not contain raw secrets or credentials',
    severity: 'error',
    async check(_dir, staged) {
      const SECRET_PATTERN = /(?:PRIVATE_KEY|SECRET_KEY|API_KEY|PASSWORD|ACCESS_TOKEN)\s*=\s*[^\s"']{8,}/i;
      const matches = await grepFiles(_dir, staged, SECRET_PATTERN);
      return matches.map(f => ({
        rule: 'no-secrets-staged',
        severity: 'error' as const,
        file: f,
        detail: 'Possible credential detected. Move to .env and add to .gitignore.',
      }));
    },
  },
  {
    id: 'no-env-committed',
    description: '.env files must not be staged or in recent commits',
    severity: 'error',
    async check(_dir, staged, recent) {
      const all = [...staged, ...recent];
      const envFiles = all.filter(f => /^\.env(\.|$)/.test(path.basename(f)));
      return envFiles.map(f => ({
        rule: 'no-env-committed',
        severity: 'error' as const,
        file: f,
        detail: '.env file committed. Remove with: git rm --cached ' + f,
      }));
    },
  },
  {
    id: 'no-ai-markdown-committed',
    description: 'AI-generated summaries/plans should not be committed',
    severity: 'warn',
    async check(_dir, staged, recent) {
      const AI_MD_PATTERN = /^(plan|summary|analysis|todo|scratch|notes?|output)\./i;
      const all = [...staged, ...recent];
      const suspicious = all.filter(f => AI_MD_PATTERN.test(path.basename(f)) && f.endsWith('.md'));
      return suspicious.map(f => ({
        rule: 'no-ai-markdown-committed',
        severity: 'warn' as const,
        file: f,
        detail: 'Looks like an AI-generated markdown file. Remove from commit unless intentional.',
      }));
    },
  },
  {
    id: 'no-node-modules-committed',
    description: 'node_modules must not be committed',
    severity: 'error',
    async check(_dir, staged, recent) {
      const all = [...staged, ...recent];
      const nmFiles = all.filter(f => f.startsWith('node_modules/'));
      return nmFiles.length > 0 ? [{
        rule: 'no-node-modules-committed',
        severity: 'error' as const,
        detail: `${nmFiles.length} node_modules file(s) committed. Add node_modules to .gitignore.`,
      }] : [];
    },
  },
  {
    id: 'gitignore-covers-env',
    description: '.gitignore must include .env and node_modules',
    severity: 'warn',
    async check(dir) {
      const gitignorePath = path.join(dir, '.gitignore');
      if (!(await fs.pathExists(gitignorePath))) {
        return [{ rule: 'gitignore-covers-env', severity: 'warn', detail: 'No .gitignore found.' }];
      }
      const content = await fs.readFile(gitignorePath, 'utf-8');
      const violations: GuardrailViolation[] = [];
      if (!content.includes('.env')) violations.push({ rule: 'gitignore-covers-env', severity: 'warn', detail: '.env not in .gitignore' });
      if (!content.includes('node_modules')) violations.push({ rule: 'gitignore-covers-env', severity: 'warn', detail: 'node_modules not in .gitignore' });
      return violations;
    },
  },
  {
    id: 'harness-doc-present',
    description: 'docs/harness-engineering.md must exist',
    severity: 'warn',
    async check(dir) {
      const exists = await fs.pathExists(path.join(dir, 'docs', 'harness-engineering.md'));
      return exists ? [] : [{
        rule: 'harness-doc-present',
        severity: 'warn',
        detail: 'Missing docs/harness-engineering.md. Run: mt harness',
      }];
    },
  },
  {
    id: 'no-large-binary-files',
    description: 'Binary files larger than 1MB should not be committed',
    severity: 'warn',
    async check(dir, staged) {
      const violations: GuardrailViolation[] = [];
      for (const file of staged) {
        const fullPath = path.join(dir, file);
        try {
          const stat = await fs.stat(fullPath);
          if (stat.size > 1_000_000) {
            violations.push({
              rule: 'no-large-binary-files',
              severity: 'warn',
              file,
              detail: `File is ${(stat.size / 1_000_000).toFixed(1)}MB. Use Git LFS for large assets.`,
            });
          }
        } catch { /* missing */ }
      }
      return violations;
    },
  },
];
