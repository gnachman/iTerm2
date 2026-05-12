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
exports.vibeCommand = vibeCommand;
const ora_1 = __importDefault(require("ora"));
const chalk_1 = __importDefault(require("chalk"));
const fs = __importStar(require("fs-extra"));
const path = __importStar(require("path"));
const logger_js_1 = require("../utils/logger.js");
const shell_js_1 = require("../utils/shell.js");
function vibeCommand(program) {
    program
        .command('vibe [directory]')
        .alias('vibe-check')
        .description('Run vibe-readiness analysis and generate report.md')
        .option('--no-report', 'Print results only, skip writing report.md')
        .option('--open', 'Open report.md after generation')
        .action(async (directory, opts) => {
        const targetDir = path.resolve(directory ?? process.cwd());
        logger_js_1.logger.header('Vibe-Readiness Analysis');
        const spinner = (0, ora_1.default)('Analyzing project…').start();
        // Try vibe-ready-cli first (npm install -g vibe-ready-cli to enable)
        const vibeCliExists = await (0, shell_js_1.commandExists)('vibe-ready');
        if (vibeCliExists) {
            spinner.text = 'Running vibe-ready-cli…';
            const result = await (0, shell_js_1.runShell)('vibe-ready', ['--json'], targetDir);
            if (result.exitCode === 0) {
                try {
                    const data = JSON.parse(result.stdout);
                    spinner.succeed('vibe-ready-cli analysis complete');
                    printVibeReport(data);
                    if (opts?.report !== false) {
                        await writeReport(targetDir, data);
                    }
                    return;
                }
                catch {
                    spinner.warn('Could not parse vibe-ready-cli output — using built-in analysis.');
                }
            }
            else {
                spinner.warn('vibe-ready exited with error — using built-in analysis.');
            }
        }
        else {
            spinner.info('vibe-ready not found — using built-in analysis. Install: npm install -g vibe-ready-cli');
            spinner.start('Analyzing project…');
        }
        // Built-in analysis
        const report = await runBuiltinAnalysis(targetDir);
        spinner.succeed('Analysis complete');
        printVibeReport(report);
        if (opts?.report !== false) {
            await writeReport(targetDir, report);
            logger_js_1.logger.step(`Report saved: ${path.join(targetDir, 'report.md')}`);
        }
        if (opts?.open) {
            await (0, shell_js_1.runShell)('open', [path.join(targetDir, 'report.md')]);
        }
    });
}
async function runBuiltinAnalysis(dir) {
    const categories = [
        await checkDocumentation(dir),
        await checkHarness(dir),
        await checkTestCoverage(dir),
        await checkCICD(dir),
        await checkHooks(dir),
        await checkSecurity(dir),
    ];
    const totalScore = Math.round(categories.reduce((sum, c) => sum + (c.score * c.weight), 0) /
        categories.reduce((sum, c) => sum + c.weight, 0));
    const grade = totalScore >= 90 ? 'A' : totalScore >= 80 ? 'B' : totalScore >= 70 ? 'C' : totalScore >= 60 ? 'D' : 'F';
    const mustHaveItems = categories.flatMap(c => c.issues.filter((_, i) => c.score < 50));
    const niceToHaveItems = categories.flatMap(c => c.recommendations);
    const priorityActions = [...mustHaveItems, ...niceToHaveItems].slice(0, 5);
    return { totalScore, grade, categories, mustHaveItems, niceToHaveItems, priorityActions, generatedAt: new Date().toISOString() };
}
async function checkDocumentation(dir) {
    const issues = [];
    const recommendations = [];
    let score = 0;
    const docs = ['README.md', 'CLAUDE.md', 'AGENTS.md', 'handoff.md', 'docs/'];
    for (const doc of docs) {
        if (await fs.pathExists(path.join(dir, doc)))
            score += 20;
        else
            issues.push(`Missing: ${doc}`);
    }
    if (score < 100)
        recommendations.push('Add missing documentation files');
    return { name: 'Documentation', score, weight: 1.5, issues, recommendations };
}
async function checkHarness(dir) {
    const issues = [];
    const recommendations = [];
    let score = 0;
    if (await fs.pathExists(path.join(dir, 'docs/harness-engineering.md')))
        score += 50;
    else
        issues.push('Missing: docs/harness-engineering.md');
    if (await fs.pathExists(path.join(dir, '.agentignore')))
        score += 25;
    else
        recommendations.push('Add .agentignore to reduce AI context waste');
    if (await fs.pathExists(path.join(dir, 'CLAUDE.md')))
        score += 25;
    else
        issues.push('Missing: CLAUDE.md');
    return { name: 'Harness Engineering', score, weight: 1.5, issues, recommendations };
}
async function checkTestCoverage(dir) {
    const issues = [];
    const recommendations = [];
    let score = 0;
    const testDirs = ['tests/', 'test/', '__tests__/', 'spec/'];
    const hasTests = await Promise.any(testDirs.map(d => fs.pathExists(path.join(dir, d)).then(e => { if (!e)
        throw new Error(); return true; })));
    if (hasTests)
        score += 50;
    else
        issues.push('No test directory found');
    const pkgPath = path.join(dir, 'package.json');
    if (await fs.pathExists(pkgPath)) {
        const pkg = await fs.readJson(pkgPath);
        if (pkg.scripts?.test)
            score += 30;
        else
            recommendations.push('Add test script to package.json');
        if (pkg.devDependencies?.jest || pkg.devDependencies?.vitest || pkg.devDependencies?.mocha)
            score += 20;
        else
            recommendations.push('Add a test framework');
    }
    else {
        score += 50; // Non-JS project
    }
    return { name: 'Test Coverage', score, weight: 1.0, issues, recommendations };
}
async function checkCICD(dir) {
    const issues = [];
    const recommendations = [];
    let score = 0;
    const ciPaths = ['.github/workflows/', '.gitlab-ci.yml', '.circleci/', 'Jenkinsfile'];
    for (const ci of ciPaths) {
        if (await fs.pathExists(path.join(dir, ci))) {
            score = 100;
            break;
        }
    }
    if (score === 0)
        issues.push('No CI/CD configuration found');
    else
        recommendations.push('Ensure CI runs tests and static analysis');
    return { name: 'CI/CD', score, weight: 1.0, issues, recommendations };
}
async function checkHooks(dir) {
    const issues = [];
    const recommendations = [];
    let score = 0;
    const hookPaths = ['.hooks/pre-commit', '.git/hooks/pre-commit', '.hooks/pre-push', '.git/hooks/pre-push'];
    for (const h of hookPaths) {
        if (await fs.pathExists(path.join(dir, h)))
            score += 25;
    }
    if (score < 50) {
        issues.push('No git hooks configured');
        recommendations.push('Run: mt harness to configure hooks');
    }
    return { name: 'Hooks & Guardrails', score, weight: 1.0, issues, recommendations };
}
async function checkSecurity(dir) {
    const issues = [];
    const recommendations = [];
    let score = 100;
    const gitignorePath = path.join(dir, '.gitignore');
    if (await fs.pathExists(gitignorePath)) {
        const content = await fs.readFile(gitignorePath, 'utf-8');
        if (!content.includes('.env')) {
            score -= 30;
            issues.push('.env not in .gitignore');
        }
        if (!content.includes('node_modules')) {
            score -= 20;
            recommendations.push('Add node_modules to .gitignore');
        }
    }
    else {
        score = 0;
        issues.push('No .gitignore file');
    }
    return { name: 'Security & .gitignore', score: Math.max(0, score), weight: 1.5, issues, recommendations };
}
function printVibeReport(report) {
    const gradeColor = report.grade === 'A' ? chalk_1.default.green : report.grade === 'B' ? chalk_1.default.cyan : report.grade === 'C' ? chalk_1.default.yellow : chalk_1.default.red;
    logger_js_1.logger.blank();
    console.log(`  ${chalk_1.default.bold('Vibe-Readiness Score')}  ${gradeColor.bold(`${report.totalScore}/100 (${report.grade})`)}`);
    logger_js_1.logger.blank();
    for (const cat of report.categories) {
        const bar = '█'.repeat(Math.round(cat.score / 10)) + '░'.repeat(10 - Math.round(cat.score / 10));
        const color = cat.score >= 80 ? chalk_1.default.green : cat.score >= 60 ? chalk_1.default.yellow : chalk_1.default.red;
        console.log(`  ${cat.name.padEnd(24)} ${color(bar)} ${String(cat.score).padStart(3)}%`);
    }
    if (report.priorityActions.length > 0) {
        logger_js_1.logger.section('Priority Actions', report.priorityActions.map(a => chalk_1.default.yellow(a)));
    }
    logger_js_1.logger.blank();
}
async function writeReport(dir, report) {
    const gradeEmoji = report.grade === 'A' ? '🟢' : report.grade === 'B' ? '🔵' : report.grade === 'C' ? '🟡' : '🔴';
    const content = `# Vibe-Readiness Report

> Generated: ${new Date(report.generatedAt).toLocaleString('ko-KR')}
> Score: **${report.totalScore}/100** (${gradeEmoji} Grade ${report.grade})

## Category Scores

| Category | Score | Weight |
|---|---|---|
${report.categories.map(c => `| ${c.name} | ${c.score}% | ${c.weight}x |`).join('\n')}

## Must-Have Items
${report.mustHaveItems.length > 0 ? report.mustHaveItems.map(i => `- [ ] ${i}`).join('\n') : '- ✓ All critical items present'}

## Nice-to-Have Items
${report.niceToHaveItems.length > 0 ? report.niceToHaveItems.map(i => `- [ ] ${i}`).join('\n') : '- ✓ No outstanding improvements'}

## Priority Actions
${report.priorityActions.length > 0 ? report.priorityActions.map((a, i) => `${i + 1}. ${a}`).join('\n') : 'No urgent actions needed.'}

## Category Details
${report.categories.map(c => `
### ${c.name} — ${c.score}%
${c.issues.length > 0 ? c.issues.map(i => `- ⚠️ ${i}`).join('\n') : '- ✅ No issues'}
${c.recommendations.length > 0 ? '\n**Recommendations:**\n' + c.recommendations.map(r => `- 💡 ${r}`).join('\n') : ''}`).join('\n')}
`;
    await fs.writeFile(path.join(dir, 'report.md'), content);
}
//# sourceMappingURL=vibe.js.map