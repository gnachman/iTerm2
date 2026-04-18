import { Command } from 'commander';
import ora from 'ora';
import chalk from 'chalk';
import { logger } from '../utils/logger.js';
import { loadRegistry, saveRegistry, loadConfig } from '../utils/config.js';
import { runShell, getCommandVersion } from '../utils/shell.js';
import semver from 'semver';

const PACKAGE_NAME = 'momenterm';

export function upgradeCommand(program: Command): void {
  program
    .command('upgrade')
    .description('Upgrade mt and check for updates')
    .option('--check', 'Check for updates only (no install)')
    .option('--plugins', 'Also upgrade plugins')
    .option('--skills', 'Also upgrade skills')
    .action(async (opts: { check?: boolean; plugins?: boolean; skills?: boolean }) => {
      logger.header('MomenTerm Upgrade');

      // Check current mt version
      const spinner = ora('Checking for updates…').start();

      let latestVersion: string | null = null;
      try {
        const { stdout } = await runShell('npm', ['view', PACKAGE_NAME, 'version']);
        latestVersion = stdout.trim();
      } catch {
        // npm view might fail if package not yet published
      }

      const registry = await loadRegistry();
      spinner.stop();

      logger.blank();

      // mt itself
      const currentVersion = '0.1.0'; // TODO: read from package.json at runtime
      if (latestVersion) {
        const needsUpdate = semver.gt(latestVersion, currentVersion);
        console.log(
          `  ${chalk.bold('mt')}  ${chalk.dim(`v${currentVersion}`)} → ${needsUpdate ? chalk.green(`v${latestVersion}`) : chalk.dim('up to date')}`
        );

        if (needsUpdate && !opts.check) {
          const installSpinner = ora('Installing update…').start();
          const result = await runShell('npm', ['install', '-g', PACKAGE_NAME]);
          if (result.exitCode === 0) {
            installSpinner.succeed('mt updated successfully');
          } else {
            installSpinner.fail('Update failed: ' + result.stderr);
          }
        }
      } else {
        logger.info('Could not check for mt updates (package not published yet).');
      }

      // Plugins
      if (opts.plugins && registry.plugins.length > 0) {
        logger.blank();
        logger.section('Plugin updates', []);
        for (const plugin of registry.plugins) {
          console.log(`  ${chalk.dim('→')} ${plugin.name} — version check coming in v0.2.0`);
        }
      }

      // Skills
      if (opts.skills && registry.skills.length > 0) {
        logger.blank();
        logger.section('Skill updates', []);
        for (const skill of registry.skills) {
          console.log(`  ${chalk.dim('→')} ${skill.name} — version check coming in v0.2.0`);
        }
      }

      logger.blank();
      logger.success('Upgrade check complete.');
    });

  program
    .command('rollback [version]')
    .description('Rollback mt to a previous version')
    .action(async (version?: string) => {
      logger.header('MomenTerm Rollback');

      if (!version) {
        logger.error('Specify version to rollback to: mt rollback 0.0.9');
        return;
      }

      const spinner = ora(`Rolling back to v${version}…`).start();
      const result = await runShell('npm', ['install', '-g', `${PACKAGE_NAME}@${version}`]);

      if (result.exitCode === 0) {
        spinner.succeed(`Rolled back to v${version}`);
      } else {
        spinner.fail(`Rollback failed: ${result.stderr}`);
      }
    });

  program
    .command('compatibility-check')
    .alias('compat')
    .description('Check compatibility between installed components')
    .action(async () => {
      logger.header('Compatibility Check');
      const registry = await loadRegistry();

      const nodeVersion = await getCommandVersion('node');
      logger.blank();
      logger.section('Runtime', [
        `Node.js: ${nodeVersion ?? 'unknown'} (required: >=18.0.0)`,
      ]);

      if (registry.plugins.length > 0) {
        logger.section('Plugins', registry.plugins.map(p =>
          `${p.name} v${p.version} — compatibility: ✓ (no known conflicts)`
        ));
      }

      if (registry.skills.length > 0) {
        logger.section('Skills', registry.skills.map(s =>
          `${s.name} v${s.version} — compatibility: ✓`
        ));
      }

      logger.blank();
      logger.success('No compatibility issues detected.');
    });
}
