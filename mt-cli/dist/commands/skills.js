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
exports.skillsCommand = skillsCommand;
const chalk_1 = __importDefault(require("chalk"));
const ora_1 = __importDefault(require("ora"));
const fs = __importStar(require("fs-extra"));
const path = __importStar(require("path"));
const logger_js_1 = require("../utils/logger.js");
const config_js_1 = require("../utils/config.js");
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
    { id: 'gstack', name: 'gstack', description: 'Graphite stacked-PR workflow installer & config' },
    { id: 'omc', name: 'omc', description: 'oh-my-claudecode orchestration layer setup for a project' },
    { id: 'open-spec', name: 'open-spec', description: 'OpenAPI spec scaffold + Spectral linting config' },
];
function skillsCommand(program) {
    const skills = program
        .command('skills')
        .description('Manage MomenTerm skills');
    skills
        .command('list')
        .description('List available and installed skills')
        .option('--installed', 'Show only installed skills')
        .action(async (opts) => {
        const registry = await (0, config_js_1.loadRegistry)();
        logger_js_1.logger.header('Skills');
        if (!opts.installed) {
            logger_js_1.logger.section('Built-in Skills (available to install)', []);
            for (const s of BUILTIN_SKILLS) {
                const installed = registry.skills.some(r => r.id === s.id);
                const tag = installed ? chalk_1.default.green('[installed]') : chalk_1.default.dim('[available]');
                console.log(`    ${chalk_1.default.bold(s.name)} ${tag}`);
                console.log(`    ${chalk_1.default.dim(s.description)}`);
                console.log();
            }
        }
        if (registry.skills.length > 0) {
            logger_js_1.logger.section('Installed Skills', []);
            for (const s of registry.skills) {
                console.log(`    ${chalk_1.default.bold(s.name)} ${chalk_1.default.dim(`v${s.version}`)} ${chalk_1.default.dim(`(${s.source})`)}`);
            }
        }
        else if (opts.installed) {
            logger_js_1.logger.info('No skills installed. Run `mt skills install <name>`');
        }
    });
    skills
        .command('install <name>')
        .description('Install a skill by name or source')
        .action(async (name) => {
        const spinner = (0, ora_1.default)(`Installing skill "${name}"…`).start();
        const registry = await (0, config_js_1.loadRegistry)();
        if (registry.skills.some(s => s.name === name)) {
            spinner.warn(`Skill "${name}" is already installed.`);
            return;
        }
        const builtin = BUILTIN_SKILLS.find(s => s.name === name || s.id === name);
        const skillDir = path.join(config_js_1.SKILLS_DIR, name);
        await fs.ensureDir(skillDir);
        // Generate skill scaffold
        if (builtin) {
            await generateSkillScaffold(skillDir, name);
        }
        const record = {
            id: builtin?.id ?? (0, config_js_1.generateId)(),
            name,
            version: '0.1.0',
            source: builtin ? 'builtin' : name,
            installedAt: new Date().toISOString(),
        };
        registry.skills.push(record);
        registry.lastUpdated = new Date().toISOString();
        await (0, config_js_1.saveRegistry)(registry);
        spinner.succeed(`Skill "${name}" installed.`);
        logger_js_1.logger.step(`Location: ${skillDir}`);
        logger_js_1.logger.step(`Run: mt skills run ${name}`);
    });
    skills
        .command('run <name> [directory]')
        .description('Run a skill in the current or specified directory')
        .action(async (name, directory) => {
        const targetDir = path.resolve(directory ?? process.cwd());
        const registry = await (0, config_js_1.loadRegistry)();
        const skill = registry.skills.find(s => s.name === name);
        if (!skill) {
            logger_js_1.logger.error(`Skill "${name}" not installed. Run: mt skills install ${name}`);
            return;
        }
        logger_js_1.logger.header(`Running skill: ${name}`);
        logger_js_1.logger.info(`Target: ${targetDir}`);
        logger_js_1.logger.blank();
        const skillDir = path.join(config_js_1.SKILLS_DIR, name);
        const runScript = path.join(skillDir, 'run.js');
        if (await fs.pathExists(runScript)) {
            const { runSkill } = await Promise.resolve(`${runScript}`).then(s => __importStar(require(s)));
            await runSkill(targetDir);
        }
        else {
            logger_js_1.logger.warn('Skill runner not yet implemented for this skill.');
            logger_js_1.logger.step('Check the generated scaffold at: ' + skillDir);
        }
    });
    skills
        .command('remove <name>')
        .description('Remove an installed skill')
        .action(async (name) => {
        const registry = await (0, config_js_1.loadRegistry)();
        const idx = registry.skills.findIndex(s => s.name === name);
        if (idx === -1) {
            logger_js_1.logger.error(`Skill "${name}" not found.`);
            return;
        }
        registry.skills.splice(idx, 1);
        registry.lastUpdated = new Date().toISOString();
        await (0, config_js_1.saveRegistry)(registry);
        const skillDir = path.join(config_js_1.SKILLS_DIR, name);
        if (await fs.pathExists(skillDir)) {
            await fs.remove(skillDir);
        }
        logger_js_1.logger.success(`Skill "${name}" removed.`);
    });
}
async function generateSkillScaffold(dir, name) {
    const description = BUILTIN_SKILLS.find(s => s.name === name)?.description ?? 'Custom skill';
    const indexContent = `# Skill: ${name}\n\nGenerated by MomenTerm mt CLI.\n\n## Description\n${description}\n\n## Usage\n\`\`\`\nmt skills run ${name} [directory]\n\`\`\`\n`;
    await fs.writeFile(path.join(dir, 'README.md'), indexContent);
    let runScript;
    switch (name) {
        case 'gstack':
            runScript = GSTACK_RUNNER;
            break;
        case 'omc':
            runScript = OMC_RUNNER;
            break;
        case 'open-spec':
            runScript = OPENSPEC_RUNNER;
            break;
        default:
            runScript = `// Skill: ${name}\nasync function runSkill(targetDir) {\n  console.log('Running ${name} in: ' + targetDir);\n}\nmodule.exports = { runSkill };\n`;
    }
    await fs.writeFile(path.join(dir, 'run.js'), runScript);
}
// ── helpers shared by runners ────────────────────────────────────────────────
// All shell calls use spawnSync with explicit argument arrays — no shell=true.
const RUNNER_HELPERS = `
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function run(cmd, args, opts) {
  const r = spawnSync(cmd, args, { encoding: 'utf8', stdio: 'inherit', ...opts });
  if (r.error) throw r.error;
  return r.status === 0;
}
function installed(cmd) {
  const r = spawnSync('which', [cmd], { encoding: 'utf8' });
  return r.status === 0;
}
`;
// ── gstack runner ────────────────────────────────────────────────────────────
const GSTACK_RUNNER = RUNNER_HELPERS + `
async function runSkill(targetDir) {
  console.log('\\n[gstack] Setting up Graphite stacked-PR workflow in:', targetDir);

  if (!installed('gt')) {
    console.log('[gstack] Installing @withgraphite/graphite-cli via npm...');
    run('npm', ['install', '-g', '@withgraphite/graphite-cli']);
  } else {
    console.log('[gstack] gt already installed.');
  }

  const gitDir = path.join(targetDir, '.git');
  if (!fs.existsSync(gitDir)) {
    console.error('[gstack] Not a git repo:', targetDir);
    process.exit(1);
  }

  run('gt', ['repo', 'init', '--trunk', 'main'], { cwd: targetDir });

  const ignoreFile = path.join(targetDir, '.graphite_ignore');
  if (!fs.existsSync(ignoreFile)) {
    fs.writeFileSync(ignoreFile, '# Branches to exclude from Graphite stacks\\n');
    console.log('[gstack] Created .graphite_ignore');
  }

  console.log('\\n[gstack] Quick reference:');
  console.log('  gt create -m "feat: ..."   Create stacked branch');
  console.log('  gt sync                     Sync stack with remote');
  console.log('  gt submit                   Open PRs for entire stack');
  console.log('  gt log short                Visual stack overview');
}
module.exports = { runSkill };
`;
// ── omc runner ───────────────────────────────────────────────────────────────
const OMC_RUNNER = RUNNER_HELPERS + `
async function runSkill(targetDir) {
  console.log('\\n[omc] Setting up oh-my-claudecode for:', targetDir);

  const commandsDir = path.join(targetDir, '.claude', 'commands');
  fs.mkdirSync(commandsDir, { recursive: true });

  const claudeMd = path.join(targetDir, 'CLAUDE.md');
  if (!fs.existsSync(claudeMd)) {
    fs.writeFileSync(claudeMd, [
      '# Project AI Instructions',
      '',
      '## Conventions',
      '- (fill in language / framework specifics)',
      '',
      '## Key Paths',
      '- src/   — main source',
      '- tests/ — test suite',
      '',
      '## Agent Guidelines',
      '- Prefer evidence over assumptions.',
      '- Delegate complex multi-file work to executor agent.',
    ].join('\\n') + '\\n');
    console.log('[omc] Created CLAUDE.md');
  } else {
    console.log('[omc] CLAUDE.md already exists — skipped.');
  }

  const reviewCmd = path.join(commandsDir, 'review.md');
  if (!fs.existsSync(reviewCmd)) {
    fs.writeFileSync(reviewCmd, [
      '# /review',
      '',
      'Run a full code review of recent changes.',
      '',
      'Steps:',
      '1. git diff HEAD~1 to see changes',
      '2. Launch oh-my-claudecode:code-reviewer agent',
      '3. Report findings with severity ratings',
    ].join('\\n') + '\\n');
    console.log('[omc] Created .claude/commands/review.md');
  }

  const agentIgnore = path.join(targetDir, '.agentignore');
  if (!fs.existsSync(agentIgnore)) {
    fs.writeFileSync(agentIgnore, [
      '# Files excluded from AI context',
      'node_modules/', 'dist/', '.git/', '*.lock', '*.log', '.env*', 'coverage/',
    ].join('\\n') + '\\n');
    console.log('[omc] Created .agentignore');
  }

  console.log('\\n[omc] Setup complete. Edit CLAUDE.md and .claude/commands/ as needed.');
}
module.exports = { runSkill };
`;
// ── open-spec runner ─────────────────────────────────────────────────────────
const OPENSPEC_RUNNER = RUNNER_HELPERS + `
async function runSkill(targetDir) {
  console.log('\\n[open-spec] Setting up OpenAPI scaffold in:', targetDir);

  if (!installed('spectral')) {
    console.log('[open-spec] Installing @stoplight/spectral-cli...');
    run('npm', ['install', '-g', '@stoplight/spectral-cli']);
  } else {
    console.log('[open-spec] spectral already installed.');
  }

  const specFile = path.join(targetDir, 'openapi.yaml');
  if (!fs.existsSync(specFile)) {
    let appName = path.basename(targetDir);
    const pkgPath = path.join(targetDir, 'package.json');
    if (fs.existsSync(pkgPath)) {
      try { appName = JSON.parse(fs.readFileSync(pkgPath, 'utf8')).name || appName; } catch {}
    }
    fs.writeFileSync(specFile, [
      'openapi: "3.1.0"',
      'info:',
      '  title: ' + appName,
      '  version: "0.1.0"',
      '  description: "API for ' + appName + '"',
      'servers:',
      '  - url: http://localhost:3000',
      '    description: Local development',
      'paths: {}',
      'components:',
      '  schemas: {}',
      '  securitySchemes: {}',
    ].join('\\n') + '\\n');
    console.log('[open-spec] Created openapi.yaml');
  } else {
    console.log('[open-spec] openapi.yaml already exists — skipped.');
  }

  const spectralConfig = path.join(targetDir, '.spectral.yaml');
  if (!fs.existsSync(spectralConfig)) {
    fs.writeFileSync(spectralConfig, 'extends: ["spectral:oas"]\\nrules:\\n  operation-description: warn\\n  operation-tags: warn\\n');
    console.log('[open-spec] Created .spectral.yaml');
  }

  console.log('\\n[open-spec] Linting openapi.yaml...');
  run('spectral', ['lint', specFile], { cwd: targetDir });

  console.log('\\n[open-spec] Done. Edit openapi.yaml and run: spectral lint openapi.yaml');
}
module.exports = { runSkill };
`;
//# sourceMappingURL=skills.js.map