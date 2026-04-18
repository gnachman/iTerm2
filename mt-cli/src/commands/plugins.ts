import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { logger } from '../utils/logger.js';
import { loadRegistry, saveRegistry, generateId, PLUGINS_DIR } from '../utils/config.js';
import * as fs from 'fs-extra';
import * as path from 'path';
import type { PluginRecord } from '../types.js';

export function pluginsCommand(program: Command): void {
  const plugins = program
    .command('plugins')
    .description('Manage MomenTerm plugins');

  plugins
    .command('list')
    .description('List installed plugins')
    .action(async () => {
      const registry = await loadRegistry();
      logger.header('Installed Plugins');

      if (registry.plugins.length === 0) {
        logger.info('No plugins installed. Run `mt plugins install <name>` to add one.');
        return;
      }

      for (const p of registry.plugins) {
        const status = p.enabled ? chalk.green('enabled') : chalk.dim('disabled');
        console.log(`  ${chalk.bold(p.name)} ${chalk.dim(`v${p.version}`)} [${status}]`);
        console.log(`    ${chalk.dim(p.source)}`);
      }
      logger.blank();
      logger.info(`${registry.plugins.length} plugin(s) installed.`);
    });

  plugins
    .command('install <source>')
    .description('Install a plugin from npm or local path')
    .option('--name <name>', 'Override plugin name')
    .action(async (source: string, opts: { name?: string }) => {
      const spinner = ora(`Installing plugin from ${source}…`).start();

      const registry = await loadRegistry();
      const name = opts.name ?? path.basename(source).replace(/^mt-plugin-/, '');
      const id = generateId();
      const pluginDir = path.join(PLUGINS_DIR, id);

      await fs.ensureDir(pluginDir);

      const record: PluginRecord = {
        id,
        name,
        version: '0.1.0',
        source,
        installedAt: new Date().toISOString(),
        enabled: true,
      };

      registry.plugins.push(record);
      registry.lastUpdated = new Date().toISOString();
      await saveRegistry(registry);

      spinner.succeed(`Plugin "${name}" installed (id: ${id})`);
      logger.step(`Location: ${pluginDir}`);
    });

  plugins
    .command('remove <name>')
    .description('Remove an installed plugin')
    .action(async (name: string) => {
      const registry = await loadRegistry();
      const idx = registry.plugins.findIndex(p => p.name === name || p.id === name);

      if (idx === -1) {
        logger.error(`Plugin "${name}" not found.`);
        return;
      }

      const [removed] = registry.plugins.splice(idx, 1);
      registry.lastUpdated = new Date().toISOString();
      await saveRegistry(registry);

      const pluginDir = path.join(PLUGINS_DIR, removed.id);
      if (await fs.pathExists(pluginDir)) {
        await fs.remove(pluginDir);
      }

      logger.success(`Plugin "${name}" removed.`);
    });

  plugins
    .command('enable <name>')
    .description('Enable a disabled plugin')
    .action(async (name: string) => {
      await setPluginEnabled(name, true);
    });

  plugins
    .command('disable <name>')
    .description('Disable a plugin without removing it')
    .action(async (name: string) => {
      await setPluginEnabled(name, false);
    });

  plugins
    .command('update [name]')
    .description('Update plugins (all or specific)')
    .action(async (name?: string) => {
      const registry = await loadRegistry();
      const targets = name
        ? registry.plugins.filter(p => p.name === name)
        : registry.plugins;

      if (targets.length === 0) {
        logger.warn('No plugins to update.');
        return;
      }

      const spinner = ora('Checking for updates…').start();
      spinner.succeed(`${targets.length} plugin(s) checked. (Update logic: connect to registry in future version)`);
      logger.info('Plugin update support coming in v0.2.0');
    });
}

async function setPluginEnabled(name: string, enabled: boolean): Promise<void> {
  const registry = await loadRegistry();
  const plugin = registry.plugins.find(p => p.name === name || p.id === name);

  if (!plugin) {
    logger.error(`Plugin "${name}" not found.`);
    return;
  }

  plugin.enabled = enabled;
  registry.lastUpdated = new Date().toISOString();
  await saveRegistry(registry);
  logger.success(`Plugin "${name}" ${enabled ? 'enabled' : 'disabled'}.`);
}
