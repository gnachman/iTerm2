"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.pluginsCommand = pluginsCommand;
const chalk_1 = __importDefault(require("chalk"));
const ora_1 = __importDefault(require("ora"));
const logger_js_1 = require("../utils/logger.js");
const config_js_1 = require("../utils/config.js");
const fs = __importStar(require("fs-extra"));
const path = __importStar(require("path"));
function pluginsCommand(program) {
    const plugins = program
        .command('plugins')
        .description('Manage MomenTerm plugins');
    plugins
        .command('list')
        .description('List installed plugins')
        .action(async () => {
        const registry = await (0, config_js_1.loadRegistry)();
        logger_js_1.logger.header('Installed Plugins');
        if (registry.plugins.length === 0) {
            logger_js_1.logger.info('No plugins installed. Run `mt plugins install <name>` to add one.');
            return;
        }
        for (const p of registry.plugins) {
            const status = p.enabled ? chalk_1.default.green('enabled') : chalk_1.default.dim('disabled');
            console.log(`  ${chalk_1.default.bold(p.name)} ${chalk_1.default.dim(`v${p.version}`)} [${status}]`);
            console.log(`    ${chalk_1.default.dim(p.source)}`);
        }
        logger_js_1.logger.blank();
        logger_js_1.logger.info(`${registry.plugins.length} plugin(s) installed.`);
    });
    plugins
        .command('install <source>')
        .description('Install a plugin from npm or local path')
        .option('--name <name>', 'Override plugin name')
        .action(async (source, opts) => {
        const spinner = (0, ora_1.default)(`Installing plugin from ${source}…`).start();
        const registry = await (0, config_js_1.loadRegistry)();
        const name = opts.name ?? path.basename(source).replace(/^mt-plugin-/, '');
        const id = (0, config_js_1.generateId)();
        const pluginDir = path.join(config_js_1.PLUGINS_DIR, id);
        await fs.ensureDir(pluginDir);
        const record = {
            id,
            name,
            version: '0.1.0',
            source,
            installedAt: new Date().toISOString(),
            enabled: true,
        };
        registry.plugins.push(record);
        registry.lastUpdated = new Date().toISOString();
        await (0, config_js_1.saveRegistry)(registry);
        spinner.succeed(`Plugin "${name}" installed (id: ${id})`);
        logger_js_1.logger.step(`Location: ${pluginDir}`);
    });
    plugins
        .command('remove <name>')
        .description('Remove an installed plugin')
        .action(async (name) => {
        const registry = await (0, config_js_1.loadRegistry)();
        const idx = registry.plugins.findIndex(p => p.name === name || p.id === name);
        if (idx === -1) {
            logger_js_1.logger.error(`Plugin "${name}" not found.`);
            return;
        }
        const [removed] = registry.plugins.splice(idx, 1);
        registry.lastUpdated = new Date().toISOString();
        await (0, config_js_1.saveRegistry)(registry);
        const pluginDir = path.join(config_js_1.PLUGINS_DIR, removed.id);
        if (await fs.pathExists(pluginDir)) {
            await fs.remove(pluginDir);
        }
        logger_js_1.logger.success(`Plugin "${name}" removed.`);
    });
    plugins
        .command('enable <name>')
        .description('Enable a disabled plugin')
        .action(async (name) => {
        await setPluginEnabled(name, true);
    });
    plugins
        .command('disable <name>')
        .description('Disable a plugin without removing it')
        .action(async (name) => {
        await setPluginEnabled(name, false);
    });
    plugins
        .command('update [name]')
        .description('Update plugins (all or specific)')
        .action(async (name) => {
        const registry = await (0, config_js_1.loadRegistry)();
        const targets = name
            ? registry.plugins.filter(p => p.name === name)
            : registry.plugins;
        if (targets.length === 0) {
            logger_js_1.logger.warn('No plugins to update.');
            return;
        }
        const spinner = (0, ora_1.default)('Checking for updates…').start();
        spinner.succeed(`${targets.length} plugin(s) checked. (Update logic: connect to registry in future version)`);
        logger_js_1.logger.info('Plugin update support coming in v0.2.0');
    });
}
async function setPluginEnabled(name, enabled) {
    const registry = await (0, config_js_1.loadRegistry)();
    const plugin = registry.plugins.find(p => p.name === name || p.id === name);
    if (!plugin) {
        logger_js_1.logger.error(`Plugin "${name}" not found.`);
        return;
    }
    plugin.enabled = enabled;
    registry.lastUpdated = new Date().toISOString();
    await (0, config_js_1.saveRegistry)(registry);
    logger_js_1.logger.success(`Plugin "${name}" ${enabled ? 'enabled' : 'disabled'}.`);
}
//# sourceMappingURL=plugins.js.map