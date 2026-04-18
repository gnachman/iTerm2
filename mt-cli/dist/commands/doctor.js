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
exports.doctorCommand = doctorCommand;
const ora_1 = __importDefault(require("ora"));
const chalk_1 = __importDefault(require("chalk"));
const logger_js_1 = require("../utils/logger.js");
const shell_js_1 = require("../utils/shell.js");
const config_js_1 = require("../utils/config.js");
const fs = __importStar(require("fs-extra"));
function doctorCommand(program) {
    program
        .command('doctor')
        .description('Check MomenTerm environment health')
        .option('--fix', 'Attempt to fix common issues automatically')
        .action(async (opts) => {
        logger_js_1.logger.header('MomenTerm Doctor');
        const results = [];
        const spinner = (0, ora_1.default)('Running diagnostics…').start();
        // Node.js
        const nodeVersion = await (0, shell_js_1.getCommandVersion)('node');
        results.push({
            label: 'Node.js',
            status: nodeVersion ? 'ok' : 'error',
            detail: nodeVersion ? `v${nodeVersion}` : 'Not found. Install from nodejs.org',
        });
        // npm
        const npmVersion = await (0, shell_js_1.getCommandVersion)('npm');
        results.push({
            label: 'npm',
            status: npmVersion ? 'ok' : 'warn',
            detail: npmVersion ? `v${npmVersion}` : 'Not found',
        });
        // git
        const gitVersion = await (0, shell_js_1.getCommandVersion)('git');
        results.push({
            label: 'git',
            status: gitVersion ? 'ok' : 'error',
            detail: gitVersion ? `v${gitVersion}` : 'Not found. Install Xcode Command Line Tools',
        });
        // Claude Code
        const claudeInstalled = await (0, shell_js_1.commandExists)('claude');
        const claudeVersion = claudeInstalled ? await (0, shell_js_1.getCommandVersion)('claude') : null;
        results.push({
            label: 'Claude Code',
            status: claudeInstalled ? 'ok' : 'warn',
            detail: claudeInstalled
                ? `v${claudeVersion ?? 'unknown'}`
                : 'Not found. Run: npm install -g @anthropic-ai/claude-code',
        });
        // Codex
        const codexInstalled = await (0, shell_js_1.commandExists)('codex');
        const codexVersion = codexInstalled ? await (0, shell_js_1.getCommandVersion)('codex') : null;
        results.push({
            label: 'Codex',
            status: codexInstalled ? 'ok' : 'warn',
            detail: codexInstalled
                ? `v${codexVersion ?? 'unknown'}`
                : 'Not found (optional). Run: npm install -g @openai/codex',
        });
        // tmux
        const tmuxInstalled = await (0, shell_js_1.commandExists)('tmux');
        results.push({
            label: 'tmux',
            status: tmuxInstalled ? 'ok' : 'warn',
            detail: tmuxInstalled
                ? 'Available'
                : 'Not found (optional). Run: brew install tmux',
        });
        // brew
        const brewInstalled = await (0, shell_js_1.commandExists)('brew');
        results.push({
            label: 'Homebrew',
            status: brewInstalled ? 'ok' : 'warn',
            detail: brewInstalled ? 'Available' : 'Not found. Visit brew.sh',
        });
        // mt config dir
        const configExists = await fs.pathExists(config_js_1.CONFIG_PATH);
        results.push({
            label: 'mt config',
            status: configExists ? 'ok' : 'warn',
            detail: configExists ? config_js_1.CONFIG_PATH : `Not initialized. Run: mt init`,
        });
        // mt home
        const homeExists = await fs.pathExists(config_js_1.MT_HOME);
        results.push({
            label: 'mt home',
            status: homeExists ? 'ok' : 'warn',
            detail: config_js_1.MT_HOME,
        });
        spinner.stop();
        logger_js_1.logger.blank();
        const maxLabel = Math.max(...results.map(r => r.label.length));
        let errorCount = 0;
        let warnCount = 0;
        for (const r of results) {
            const icon = r.status === 'ok' ? chalk_1.default.green('✓') :
                r.status === 'warn' ? chalk_1.default.yellow('⚠') :
                    chalk_1.default.red('✗');
            const label = r.label.padEnd(maxLabel + 2);
            console.log(`  ${icon} ${chalk_1.default.bold(label)} ${chalk_1.default.dim(r.detail)}`);
            if (r.status === 'error')
                errorCount++;
            if (r.status === 'warn')
                warnCount++;
        }
        logger_js_1.logger.blank();
        if (errorCount === 0 && warnCount === 0) {
            logger_js_1.logger.success('All checks passed!');
        }
        else if (errorCount > 0) {
            logger_js_1.logger.error(`${errorCount} error(s), ${warnCount} warning(s). Fix errors to proceed.`);
        }
        else {
            logger_js_1.logger.warn(`${warnCount} warning(s). Optional items missing.`);
        }
        if (opts.fix && !claudeInstalled) {
            logger_js_1.logger.blank();
            logger_js_1.logger.info('Auto-fix: Claude Code not found. To install, run:');
            logger_js_1.logger.step('npm install -g @anthropic-ai/claude-code');
        }
    });
}
//# sourceMappingURL=doctor.js.map