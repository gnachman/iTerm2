import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import * as fs from 'fs-extra';
import * as path from 'path';
import { logger } from '../utils/logger.js';
import { loadRegistry, saveRegistry, generateId, SKILLS_DIR } from '../utils/config.js';
import type { SkillRecord } from '../types.js';

// Built-in skill catalog
const BUILTIN_SKILLS = [
  { id: 'db-supabase', name: 'db-supabase', description: 'Supabase database setup guide & scaffold' },
  { id: 'db-neon', name: 'db-neon', description: 'Neon serverless Postgres setup' },
  { id: 'deploy-vercel', name: 'deploy-vercel', description: 'Vercel deployment configuration' },
  { id: 'deploy-ci', name: 'deploy-ci', description: 'GitHub Actions CI/CD setup' },
  { id: 'github-init', name: 'github-init', description: 'GitHub repo initialization & best practices' },
  { id: 'mcp-setup', name: 'mcp-setup', description: 'MCP server setup & Claude Code integration' },
  { id: 'harness', name: 'harness', description: 'Harness Engineering environment setup' },
  { id: 'vibe-check', name: 'vibe-check', description: 'Vibe-ready analysis & readiness report' },
];

export function skillsCommand(program: Command): void {
  const skills = program
    .command('skills')
    .description('Manage MomenTerm skills');

  skills
    .command('list')
    .description('List available and installed skills')
    .option('--installed', 'Show only installed skills')
    .action(async (opts: { installed?: boolean }) => {
      const registry = await loadRegistry();
      logger.header('Skills');

      if (!opts.installed) {
        logger.section('Built-in Skills (available to install)', []);
        for (const s of BUILTIN_SKILLS) {
          const installed = registry.skills.some(r => r.id === s.id);
          const tag = installed ? chalk.green('[installed]') : chalk.dim('[available]');
          console.log(`    ${chalk.bold(s.name)} ${tag}`);
          console.log(`    ${chalk.dim(s.description)}`);
          console.log();
        }
      }

      if (registry.skills.length > 0) {
        logger.section('Installed Skills', []);
        for (const s of registry.skills) {
          console.log(`    ${chalk.bold(s.name)} ${chalk.dim(`v${s.version}`)} ${chalk.dim(`(${s.source})`)}`);
        }
      } else if (opts.installed) {
        logger.info('No skills installed. Run `mt skills install <name>`');
      }
    });

  skills
    .command('install <name>')
    .description('Install a skill by name or source')
    .action(async (name: string) => {
      const spinner = ora(`Installing skill "${name}"…`).start();
      const registry = await loadRegistry();

      if (registry.skills.some(s => s.name === name)) {
        spinner.warn(`Skill "${name}" is already installed.`);
        return;
      }

      const builtin = BUILTIN_SKILLS.find(s => s.name === name || s.id === name);
      const skillDir = path.join(SKILLS_DIR, name);
      await fs.ensureDir(skillDir);

      // Generate skill scaffold
      if (builtin) {
        await generateSkillScaffold(skillDir, name);
      }

      const record: SkillRecord = {
        id: builtin?.id ?? generateId(),
        name,
        version: '0.1.0',
        source: builtin ? 'builtin' : name,
        installedAt: new Date().toISOString(),
      };

      registry.skills.push(record);
      registry.lastUpdated = new Date().toISOString();
      await saveRegistry(registry);

      spinner.succeed(`Skill "${name}" installed.`);
      logger.step(`Location: ${skillDir}`);
      logger.step(`Run: mt skills run ${name}`);
    });

  skills
    .command('run <name> [directory]')
    .description('Run a skill in the current or specified directory')
    .action(async (name: string, directory?: string) => {
      const targetDir = path.resolve(directory ?? process.cwd());
      const registry = await loadRegistry();

      const skill = registry.skills.find(s => s.name === name);
      if (!skill) {
        logger.error(`Skill "${name}" not installed. Run: mt skills install ${name}`);
        return;
      }

      logger.header(`Running skill: ${name}`);
      logger.info(`Target: ${targetDir}`);
      logger.blank();

      const skillDir = path.join(SKILLS_DIR, name);
      const runScript = path.join(skillDir, 'run.js');

      if (await fs.pathExists(runScript)) {
        const { runSkill } = await import(runScript);
        await runSkill(targetDir);
      } else {
        logger.warn('Skill runner not yet implemented for this skill.');
        logger.step('Check the generated scaffold at: ' + skillDir);
      }
    });

  skills
    .command('remove <name>')
    .description('Remove an installed skill')
    .action(async (name: string) => {
      const registry = await loadRegistry();
      const idx = registry.skills.findIndex(s => s.name === name);

      if (idx === -1) {
        logger.error(`Skill "${name}" not found.`);
        return;
      }

      registry.skills.splice(idx, 1);
      registry.lastUpdated = new Date().toISOString();
      await saveRegistry(registry);

      const skillDir = path.join(SKILLS_DIR, name);
      if (await fs.pathExists(skillDir)) {
        await fs.remove(skillDir);
      }

      logger.success(`Skill "${name}" removed.`);
    });
}

async function generateSkillScaffold(dir: string, name: string): Promise<void> {
  const indexContent = `# Skill: ${name}

Generated by MomenTerm mt CLI.

## Description
${BUILTIN_SKILLS.find(s => s.name === name)?.description ?? 'Custom skill'}

## Usage
\`\`\`
mt skills run ${name} [directory]
\`\`\`

## Files Generated
See the generated docs and config files in the target directory.
`;
  await fs.writeFile(path.join(dir, 'README.md'), indexContent);
  await fs.writeFile(path.join(dir, 'run.js'), `
// Skill: ${name}
// Auto-generated scaffold
async function runSkill(targetDir) {
  console.log('Running ${name} skill in: ' + targetDir);
  // TODO: implement skill logic
}
module.exports = { runSkill };
`);
}
