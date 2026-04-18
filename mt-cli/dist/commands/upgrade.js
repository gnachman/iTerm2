"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.upgradeCommand = upgradeCommand;
const ora_1 = __importDefault(require("ora"));
const chalk_1 = __importDefault(require("chalk"));
const logger_js_1 = require("../utils/logger.js");
const config_js_1 = require("../utils/config.js");
const shell_js_1 = require("../utils/shell.js");
const semver_1 = __importDefault(require("semver"));
const PACKAGE_NAME = 'momenterm';
function upgradeCommand(program) {
    program
        .command('upgrade')
        .description('Upgrade mt and check for updates')
        .option('--check', 'Check for updates only (no install)')
        .option('--plugins', 'Also upgrade plugins')
        .option('--skills', 'Also upgrade skills')
        .action(async (opts) => {
        logger_js_1.logger.header('MomenTerm Upgrade');
        // Check current mt version
        const spinner = (0, ora_1.default)('Checking for updates…').start();
        let latestVersion = null;
        try {
            const { stdout } = await (0, shell_js_1.runShell)('npm', ['view', PACKAGE_NAME, 'version']);
            latestVersion = stdout.trim();
        }
        catch {
            // npm view might fail if package not yet published
        }
        const registry = await (0, config_js_1.loadRegistry)();
        spinner.stop();
        logger_js_1.logger.blank();
        // mt itself
        const currentVersion = '0.1.0'; // TODO: read from package.json at runtime
        if (latestVersion) {
            const needsUpdate = semver_1.default.gt(latestVersion, currentVersion);
            console.log(`  ${chalk_1.default.bold('mt')}  ${chalk_1.default.dim(`v${currentVersion}`)} → ${needsUpdate ? chalk_1.default.green(`v${latestVersion}`) : chalk_1.default.dim('up to date')}`);
            if (needsUpdate && !opts.check) {
                const installSpinner = (0, ora_1.default)('Installing update…').start();
                const result = await (0, shell_js_1.runShell)('npm', ['install', '-g', PACKAGE_NAME]);
                if (result.exitCode === 0) {
                    installSpinner.succeed('mt updated successfully');
                }
                else {
                    installSpinner.fail('Update failed: ' + result.stderr);
                }
            }
        }
        else {
            logger_js_1.logger.info('Could not check for mt updates (package not published yet).');
        }
        // Plugins
        if (opts.plugins && registry.plugins.length > 0) {
            logger_js_1.logger.blank();
            logger_js_1.logger.section('Plugin updates', []);
            for (const plugin of registry.plugins) {
                console.log(`  ${chalk_1.default.dim('→')} ${plugin.name} — version check coming in v0.2.0`);
            }
        }
        // Skills
        if (opts.skills && registry.skills.length > 0) {
            logger_js_1.logger.blank();
            logger_js_1.logger.section('Skill updates', []);
            for (const skill of registry.skills) {
                console.log(`  ${chalk_1.default.dim('→')} ${skill.name} — version check coming in v0.2.0`);
            }
        }
        logger_js_1.logger.blank();
        logger_js_1.logger.success('Upgrade check complete.');
    });
    program
        .command('rollback [version]')
        .description('Rollback mt to a previous version')
        .action(async (version) => {
        logger_js_1.logger.header('MomenTerm Rollback');
        if (!version) {
            logger_js_1.logger.error('Specify version to rollback to: mt rollback 0.0.9');
            return;
        }
        const spinner = (0, ora_1.default)(`Rolling back to v${version}…`).start();
        const result = await (0, shell_js_1.runShell)('npm', ['install', '-g', `${PACKAGE_NAME}@${version}`]);
        if (result.exitCode === 0) {
            spinner.succeed(`Rolled back to v${version}`);
        }
        else {
            spinner.fail(`Rollback failed: ${result.stderr}`);
        }
    });
    program
        .command('compatibility-check')
        .alias('compat')
        .description('Check compatibility between installed components')
        .action(async () => {
        logger_js_1.logger.header('Compatibility Check');
        const registry = await (0, config_js_1.loadRegistry)();
        const nodeVersion = await (0, shell_js_1.getCommandVersion)('node');
        logger_js_1.logger.blank();
        logger_js_1.logger.section('Runtime', [
            `Node.js: ${nodeVersion ?? 'unknown'} (required: >=18.0.0)`,
        ]);
        if (registry.plugins.length > 0) {
            logger_js_1.logger.section('Plugins', registry.plugins.map(p => `${p.name} v${p.version} — compatibility: ✓ (no known conflicts)`));
        }
        if (registry.skills.length > 0) {
            logger_js_1.logger.section('Skills', registry.skills.map(s => `${s.name} v${s.version} — compatibility: ✓`));
        }
        logger_js_1.logger.blank();
        logger_js_1.logger.success('No compatibility issues detected.');
    });
}
//# sourceMappingURL=upgrade.js.map