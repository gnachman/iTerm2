#!/usr/bin/env node
import { Command } from 'commander';
import chalk from 'chalk';
import { initCommand } from './commands/init.js';
import { doctorCommand } from './commands/doctor.js';
import { pluginsCommand } from './commands/plugins.js';
import { skillsCommand } from './commands/skills.js';
import { upgradeCommand } from './commands/upgrade.js';
import { harnessCommand } from './commands/harness.js';
import { vibeCommand } from './commands/vibe.js';
import { handoffCommand } from './commands/handoff.js';
import { mcpCommand } from './commands/mcp.js';
import { projectsCommand } from './commands/projects.js';

const program = new Command();

program
  .name('mt')
  .description(
    chalk.bold.cyan('MomenTerm') + ' — AI development orchestration hub\n' +
    chalk.dim('  Terminal + AI tools + tmux + hooks + docs, all in one flow.')
  )
  .version('0.1.0', '-v, --version')
  .addHelpText('after', `
${chalk.bold('Examples:')}
  ${chalk.cyan('mt init')}              Initialize project in current directory
  ${chalk.cyan('mt doctor')}            Check environment health
  ${chalk.cyan('mt harness')}           Run Harness Engineering setup
  ${chalk.cyan('mt vibe')}              Run vibe-readiness analysis
  ${chalk.cyan('mt projects list')}     List all registered projects
  ${chalk.cyan('mt plugins list')}      List installed plugins
  ${chalk.cyan('mt skills install db-supabase')}  Install Supabase skill
  ${chalk.cyan('mt mcp setup')}         Set up an MCP server
  ${chalk.cyan('mt handoff show')}      Show current work context
  ${chalk.cyan('mt upgrade')}           Check for and apply updates
`);

// Register all commands
initCommand(program);
doctorCommand(program);
pluginsCommand(program);
skillsCommand(program);
upgradeCommand(program);
harnessCommand(program);
vibeCommand(program);
handoffCommand(program);
mcpCommand(program);
projectsCommand(program);

// bootstrap alias
program
  .command('bootstrap [directory]')
  .description('Full bootstrap: init + harness + vibe (recommended for new projects)')
  .action(async (directory?: string) => {
    const { execFileSync } = await import('child_process');
    const self = process.argv[1];
    const dir = directory ?? process.cwd();
    console.log(chalk.bold.cyan('\n  mt bootstrap — Full project setup\n'));
    execFileSync(process.execPath, [self, 'init', dir, '--quick'], { stdio: 'inherit' });
    execFileSync(process.execPath, [self, 'harness', dir, '--skip-interview'], { stdio: 'inherit' });
    execFileSync(process.execPath, [self, 'vibe', dir], { stdio: 'inherit' });
  });

program.parse();
