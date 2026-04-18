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
Object.defineProperty(exports, "__esModule", { value: true });
exports.handoffCommand = handoffCommand;
const fs = __importStar(require("fs-extra"));
const path = __importStar(require("path"));
const logger_js_1 = require("../utils/logger.js");
const shell_js_1 = require("../utils/shell.js");
function handoffCommand(program) {
    const handoff = program
        .command('handoff [directory]')
        .description('Manage handoff.md work context');
    handoff
        .command('show [directory]')
        .description('Show current handoff status')
        .action(async (directory) => {
        const dir = path.resolve(directory ?? process.cwd());
        const handoffPath = path.join(dir, 'handoff.md');
        if (!(await fs.pathExists(handoffPath))) {
            logger_js_1.logger.warn('No handoff.md found. Run: mt init');
            return;
        }
        const content = await fs.readFile(handoffPath, 'utf-8');
        logger_js_1.logger.header('Handoff Status');
        console.log(content);
    });
    handoff
        .command('update <section> <content> [directory]')
        .description('Update a section of handoff.md')
        .action(async (section, content, directory) => {
        const dir = path.resolve(directory ?? process.cwd());
        await updateHandoffSection(dir, section, content);
    });
    handoff
        .command('sync [directory]')
        .description('Sync handoff.md with current git state')
        .action(async (directory) => {
        const dir = path.resolve(directory ?? process.cwd());
        const handoffPath = path.join(dir, 'handoff.md');
        if (!(await fs.pathExists(handoffPath))) {
            logger_js_1.logger.warn('No handoff.md. Run: mt init');
            return;
        }
        const branch = await (0, shell_js_1.getCurrentBranch)(dir);
        await updateHandoffSection(dir, '관련 브랜치', branch ?? 'unknown');
        await updateHandoffLastUpdated(dir);
        logger_js_1.logger.success('handoff.md synced with current git state');
        if (branch)
            logger_js_1.logger.step(`Branch: ${branch}`);
    });
    handoff
        .command('done <task> [directory]')
        .description('Mark a task as done in handoff.md')
        .action(async (task, directory) => {
        const dir = path.resolve(directory ?? process.cwd());
        const handoffPath = path.join(dir, 'handoff.md');
        if (!(await fs.pathExists(handoffPath))) {
            logger_js_1.logger.warn('No handoff.md. Run: mt init');
            return;
        }
        let content = await fs.readFile(handoffPath, 'utf-8');
        // Mark in-progress items that match as done
        content = content.replace(new RegExp(`- \\[ \\] (.*${escapeRegex(task)}.*)`, 'gi'), `- [x] $1`);
        await fs.writeFile(handoffPath, content);
        await updateHandoffLastUpdated(dir);
        logger_js_1.logger.success(`Marked "${task}" as done in handoff.md`);
    });
    handoff
        .command('reset [directory]')
        .description('Reset handoff.md for a new session')
        .action(async (directory) => {
        const dir = path.resolve(directory ?? process.cwd());
        const handoffPath = path.join(dir, 'handoff.md');
        if (!(await fs.pathExists(handoffPath))) {
            logger_js_1.logger.warn('No handoff.md found.');
            return;
        }
        await updateHandoffLastUpdated(dir);
        logger_js_1.logger.success('handoff.md updated for new session');
        logger_js_1.logger.step('Update the "현재 목표" and "다음 액션" sections manually.');
    });
}
async function updateHandoffSection(dir, sectionName, content) {
    const handoffPath = path.join(dir, 'handoff.md');
    if (!(await fs.pathExists(handoffPath))) {
        logger_js_1.logger.error('handoff.md not found');
        return;
    }
    let text = await fs.readFile(handoffPath, 'utf-8');
    const sectionRegex = new RegExp(`(## ${escapeRegex(sectionName)}\\n)([^#]*)`, 'm');
    const match = text.match(sectionRegex);
    if (match) {
        text = text.replace(sectionRegex, `$1${content}\n\n`);
    }
    else {
        text += `\n## ${sectionName}\n${content}\n`;
    }
    await fs.writeFile(handoffPath, text);
    logger_js_1.logger.success(`Updated section "${sectionName}"`);
}
async function updateHandoffLastUpdated(dir) {
    const handoffPath = path.join(dir, 'handoff.md');
    let text = await fs.readFile(handoffPath, 'utf-8');
    const now = new Date().toLocaleString('ko-KR');
    text = text.replace(/> 마지막 업데이트:.*/, `> 마지막 업데이트: ${now}`);
    await fs.writeFile(handoffPath, text);
}
function escapeRegex(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
//# sourceMappingURL=handoff.js.map