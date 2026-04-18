"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.logger = void 0;
const chalk_1 = __importDefault(require("chalk"));
const PREFIX = chalk_1.default.bold.cyan('mt');
exports.logger = {
    info: (msg) => console.log(`${PREFIX} ${chalk_1.default.blue('ℹ')} ${msg}`),
    success: (msg) => console.log(`${PREFIX} ${chalk_1.default.green('✓')} ${msg}`),
    warn: (msg) => console.log(`${PREFIX} ${chalk_1.default.yellow('⚠')} ${msg}`),
    error: (msg) => console.error(`${PREFIX} ${chalk_1.default.red('✗')} ${msg}`),
    step: (msg) => console.log(`  ${chalk_1.default.dim('→')} ${msg}`),
    header: (msg) => {
        const line = '─'.repeat(Math.min(msg.length + 4, 60));
        console.log();
        console.log(chalk_1.default.bold.cyan(`  ${msg}`));
        console.log(chalk_1.default.dim(`  ${line}`));
    },
    section: (title, items) => {
        console.log();
        console.log(chalk_1.default.bold(`  ${title}`));
        items.forEach(item => console.log(`    ${chalk_1.default.dim('•')} ${item}`));
    },
    table: (rows) => {
        const maxKey = Math.max(...rows.map(([k]) => k.length));
        rows.forEach(([key, val]) => {
            console.log(`    ${chalk_1.default.dim(key.padEnd(maxKey + 2))} ${val}`);
        });
    },
    blank: () => console.log(),
};
//# sourceMappingURL=logger.js.map