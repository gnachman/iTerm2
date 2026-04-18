#!/usr/bin/env node
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
const commander_1 = require("commander");
const chalk_1 = __importDefault(require("chalk"));
const init_js_1 = require("./commands/init.js");
const doctor_js_1 = require("./commands/doctor.js");
const plugins_js_1 = require("./commands/plugins.js");
const skills_js_1 = require("./commands/skills.js");
const upgrade_js_1 = require("./commands/upgrade.js");
const harness_js_1 = require("./commands/harness.js");
const vibe_js_1 = require("./commands/vibe.js");
const handoff_js_1 = require("./commands/handoff.js");
const mcp_js_1 = require("./commands/mcp.js");
const projects_js_1 = require("./commands/projects.js");
const program = new commander_1.Command();
program
    .name('mt')
    .description(chalk_1.default.bold.cyan('MomenTerm') + ' — AI development orchestration hub\n' +
    chalk_1.default.dim('  Terminal + AI tools + tmux + hooks + docs, all in one flow.'))
    .version('0.1.0', '-v, --version')
    .addHelpText('after', `
${chalk_1.default.bold('Examples:')}
  ${chalk_1.default.cyan('mt init')}              Initialize project in current directory
  ${chalk_1.default.cyan('mt doctor')}            Check environment health
  ${chalk_1.default.cyan('mt harness')}           Run Harness Engineering setup
  ${chalk_1.default.cyan('mt vibe')}              Run vibe-readiness analysis
  ${chalk_1.default.cyan('mt projects list')}     List all registered projects
  ${chalk_1.default.cyan('mt plugins list')}      List installed plugins
  ${chalk_1.default.cyan('mt skills install db-supabase')}  Install Supabase skill
  ${chalk_1.default.cyan('mt mcp setup')}         Set up an MCP server
  ${chalk_1.default.cyan('mt handoff show')}      Show current work context
  ${chalk_1.default.cyan('mt upgrade')}           Check for and apply updates
`);
// Register all commands
(0, init_js_1.initCommand)(program);
(0, doctor_js_1.doctorCommand)(program);
(0, plugins_js_1.pluginsCommand)(program);
(0, skills_js_1.skillsCommand)(program);
(0, upgrade_js_1.upgradeCommand)(program);
(0, harness_js_1.harnessCommand)(program);
(0, vibe_js_1.vibeCommand)(program);
(0, handoff_js_1.handoffCommand)(program);
(0, mcp_js_1.mcpCommand)(program);
(0, projects_js_1.projectsCommand)(program);
// bootstrap alias
program
    .command('bootstrap [directory]')
    .description('Full bootstrap: init + harness + vibe (recommended for new projects)')
    .action(async (directory) => {
    const { execFileSync } = await Promise.resolve().then(() => __importStar(require('child_process')));
    const self = process.argv[1];
    const dir = directory ?? process.cwd();
    console.log(chalk_1.default.bold.cyan('\n  mt bootstrap — Full project setup\n'));
    execFileSync(process.execPath, [self, 'init', dir, '--quick'], { stdio: 'inherit' });
    execFileSync(process.execPath, [self, 'harness', dir, '--skip-interview'], { stdio: 'inherit' });
    execFileSync(process.execPath, [self, 'vibe', dir], { stdio: 'inherit' });
});
program.parse();
//# sourceMappingURL=index.js.map