import { Command } from 'commander';
import ora from 'ora';
import chalk from 'chalk';
import { logger } from '../utils/logger.js';
import { commandExists, getCommandVersion } from '../utils/shell.js';
import { MT_HOME, CONFIG_PATH } from '../utils/config.js';
import * as fs from 'fs-extra';

interface CheckResult {
  label: string;
  status: 'ok' | 'warn' | 'error';
  detail: string;
}

export function doctorCommand(program: Command): void {
  program
    .command('doctor')
    .description('Check MomenTerm environment health')
    .option('--fix', 'Attempt to fix common issues automatically')
    .action(async (opts: { fix?: boolean }) => {
      logger.header('MomenTerm Doctor');
      const results: CheckResult[] = [];

      const spinner = ora('Running diagnostics…').start();

      // Node.js
      const nodeVersion = await getCommandVersion('node');
      results.push({
        label: 'Node.js',
        status: nodeVersion ? 'ok' : 'error',
        detail: nodeVersion ? `v${nodeVersion}` : 'Not found. Install from nodejs.org',
      });

      // npm
      const npmVersion = await getCommandVersion('npm');
      results.push({
        label: 'npm',
        status: npmVersion ? 'ok' : 'warn',
        detail: npmVersion ? `v${npmVersion}` : 'Not found',
      });

      // git
      const gitVersion = await getCommandVersion('git');
      results.push({
        label: 'git',
        status: gitVersion ? 'ok' : 'error',
        detail: gitVersion ? `v${gitVersion}` : 'Not found. Install Xcode Command Line Tools',
      });

      // Claude Code
      const claudeInstalled = await commandExists('claude');
      const claudeVersion = claudeInstalled ? await getCommandVersion('claude') : null;
      results.push({
        label: 'Claude Code',
        status: claudeInstalled ? 'ok' : 'warn',
        detail: claudeInstalled
          ? `v${claudeVersion ?? 'unknown'}`
          : 'Not found. Run: npm install -g @anthropic-ai/claude-code',
      });

      // Codex
      const codexInstalled = await commandExists('codex');
      const codexVersion = codexInstalled ? await getCommandVersion('codex') : null;
      results.push({
        label: 'Codex',
        status: codexInstalled ? 'ok' : 'warn',
        detail: codexInstalled
          ? `v${codexVersion ?? 'unknown'}`
          : 'Not found (optional). Run: npm install -g @openai/codex',
      });

      // tmux
      const tmuxInstalled = await commandExists('tmux');
      results.push({
        label: 'tmux',
        status: tmuxInstalled ? 'ok' : 'warn',
        detail: tmuxInstalled
          ? 'Available'
          : 'Not found (optional). Run: brew install tmux',
      });

      // brew
      const brewInstalled = await commandExists('brew');
      results.push({
        label: 'Homebrew',
        status: brewInstalled ? 'ok' : 'warn',
        detail: brewInstalled ? 'Available' : 'Not found. Visit brew.sh',
      });

      // mt config dir
      const configExists = await fs.pathExists(CONFIG_PATH);
      results.push({
        label: 'mt config',
        status: configExists ? 'ok' : 'warn',
        detail: configExists ? CONFIG_PATH : `Not initialized. Run: mt init`,
      });

      // mt home
      const homeExists = await fs.pathExists(MT_HOME);
      results.push({
        label: 'mt home',
        status: homeExists ? 'ok' : 'warn',
        detail: MT_HOME,
      });

      spinner.stop();
      logger.blank();

      const maxLabel = Math.max(...results.map(r => r.label.length));
      let errorCount = 0;
      let warnCount = 0;

      for (const r of results) {
        const icon =
          r.status === 'ok' ? chalk.green('✓') :
          r.status === 'warn' ? chalk.yellow('⚠') :
          chalk.red('✗');
        const label = r.label.padEnd(maxLabel + 2);
        console.log(`  ${icon} ${chalk.bold(label)} ${chalk.dim(r.detail)}`);
        if (r.status === 'error') errorCount++;
        if (r.status === 'warn') warnCount++;
      }

      logger.blank();
      if (errorCount === 0 && warnCount === 0) {
        logger.success('All checks passed!');
      } else if (errorCount > 0) {
        logger.error(`${errorCount} error(s), ${warnCount} warning(s). Fix errors to proceed.`);
      } else {
        logger.warn(`${warnCount} warning(s). Optional items missing.`);
      }

      if (opts.fix && !claudeInstalled) {
        logger.blank();
        logger.info('Auto-fix: Claude Code not found. To install, run:');
        logger.step('npm install -g @anthropic-ai/claude-code');
      }
    });
}
