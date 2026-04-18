import { Command } from 'commander';
import chalk from 'chalk';
import inquirer from 'inquirer';
import ora from 'ora';
import * as path from 'path';
import * as fs from 'fs-extra';
import { logger } from '../utils/logger.js';
import { loadConfig, saveConfig, generateId } from '../utils/config.js';
import { commandExists, getCommandVersion } from '../utils/shell.js';
import type { AITool, TmuxMode, OpenMode } from '../types.js';

export function projectsCommand(program: Command): void {
  const proj = program
    .command('projects')
    .alias('p')
    .description('Manage MomenTerm projects');

  proj
    .command('list')
    .description('List all projects across all spaces')
    .action(async () => {
      const config = await loadConfig();
      logger.header('Projects');

      if (config.spaces.length === 0) {
        logger.info('No projects yet. Run: mt init [directory]');
        return;
      }

      for (const space of config.spaces) {
        console.log(`\n  ${chalk.bold.cyan(space.name)} (${space.projects.length} projects)`);
        for (const p of space.projects) {
          const aiLabel = chalk.dim(`[${p.aiTool}]`);
          const tmuxLabel = p.tmuxMode !== 'disabled' ? chalk.dim(`[tmux:${p.tmuxMode}]`) : '';
          const exists = await fs.pathExists(p.path);
          const pathColor = exists ? chalk.dim : chalk.red;
          console.log(`    ${chalk.bold(p.name)} ${aiLabel} ${tmuxLabel}`);
          console.log(`    ${pathColor(p.path)}`);
        }
      }
      logger.blank();
    });

  proj
    .command('add <directory>')
    .description('Add a directory as a project')
    .action(async (directory: string) => {
      const targetDir = path.resolve(directory);
      if (!(await fs.pathExists(targetDir))) {
        logger.error(`Directory not found: ${targetDir}`);
        return;
      }

      const answers = await inquirer.prompt([
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

      const config = await loadConfig();
      let space = config.spaces.find(s => s.name === answers.spaceName);
      if (!space) {
        space = { id: generateId(), name: answers.spaceName, projects: [] };
        config.spaces.push(space);
      }

      space.projects.push({
        id: generateId(),
        name: answers.name,
        path: targetDir,
        aiTool: answers.aiTool as AITool,
        tmuxMode: answers.tmuxMode as TmuxMode,
        createdAt: new Date().toISOString(),
      });

      await saveConfig(config);
      logger.success(`Project "${answers.name}" added to space "${answers.spaceName}"`);
    });

  proj
    .command('open <name>')
    .description('Open a project (print the cd command)')
    .option('--tab', 'Open in new iTerm2 tab (via it2 CLI)')
    .option('--window', 'Open in new iTerm2 window (via it2 CLI)')
    .action(async (name: string, opts: { tab?: boolean; window?: boolean }) => {
      const config = await loadConfig();
      let found: { spaceName: string; project: import('../types.js').MTProject } | null = null;

      for (const space of config.spaces) {
        const project = space.projects.find(p => p.name === name || p.id === name);
        if (project) { found = { spaceName: space.name, project }; break; }
      }

      if (!found) {
        logger.error(`Project "${name}" not found. Run: mt projects list`);
        return;
      }

      const { project } = found;

      if (opts.tab || opts.window) {
        const it2Available = await commandExists('it2');
        if (it2Available) {
          const mode = opts.window ? 'window new' : 'tab new';
          console.log(`it2 ${mode} && it2 session send "cd ${project.path} && ${getAILaunchCmd(project.aiTool)}"`);
          return;
        }
        logger.warn('it2 CLI not found. Printing cd command instead.');
      }

      logger.success(`Opening project: ${project.name}`);
      logger.blank();
      console.log(`  ${chalk.dim('Path:')} ${project.path}`);
      console.log(`  ${chalk.dim('AI Tool:')} ${project.aiTool}`);
      if (project.tmuxMode !== 'disabled') {
        console.log(`  ${chalk.dim('tmux:')} ${project.tmuxMode}`);
      }
      logger.blank();
      // Print the command to run
      const cmd = buildOpenCommand(project);
      console.log(chalk.bold('Run this command:'));
      console.log(`  ${chalk.cyan(cmd)}`);
    });

  proj
    .command('remove <name>')
    .description('Remove a project from registry')
    .action(async (name: string) => {
      const config = await loadConfig();
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
        logger.error(`Project "${name}" not found.`);
        return;
      }

      await saveConfig(config);
      logger.success(`Project "${name}" removed from registry.`);
    });
}

function getAILaunchCmd(tool: AITool): string {
  switch (tool) {
    case 'claude_code': return 'claude';
    case 'codex': return 'codex';
    case 'both': return 'claude & codex';
    default: return '';
  }
}

function buildOpenCommand(project: import('../types.js').MTProject): string {
  const parts: string[] = [`cd "${project.path}"`];
  if (project.tmuxMode === 'new_session') {
    parts.push(`tmux new-session -s "${project.name.replace(/\s+/g, '-').toLowerCase()}"`);
  } else if (project.tmuxMode === 'existing_session') {
    parts.push(`tmux attach -t "${project.tmuxSession ?? project.name.replace(/\s+/g, '-').toLowerCase()}"`);
  }
  const aiCmd = getAILaunchCmd(project.aiTool);
  if (aiCmd) parts.push(aiCmd);
  return parts.join(' && ');
}
