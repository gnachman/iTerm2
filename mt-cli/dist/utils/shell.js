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
exports.commandExists = commandExists;
exports.getCommandVersion = getCommandVersion;
exports.runShell = runShell;
exports.isGitRepo = isGitRepo;
exports.getCurrentBranch = getCurrentBranch;
exports.getGitRoot = getGitRoot;
exports.pathExists = pathExists;
exports.getNpmGlobalBin = getNpmGlobalBin;
const execa_1 = require("execa");
const fs = __importStar(require("fs-extra"));
async function commandExists(cmd) {
    try {
        await (0, execa_1.execa)('which', [cmd]);
        return true;
    }
    catch {
        return false;
    }
}
async function getCommandVersion(cmd, versionFlag = '--version') {
    try {
        const { stdout } = await (0, execa_1.execa)(cmd, [versionFlag]);
        const match = stdout.match(/(\d+\.\d+[\.\d]*)/);
        return match ? match[1] : stdout.trim().split('\n')[0];
    }
    catch {
        return null;
    }
}
async function runShell(cmd, args = [], cwd) {
    try {
        const result = await (0, execa_1.execa)(cmd, args, { cwd, all: true });
        return { stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode ?? 0 };
    }
    catch (err) {
        const e = err;
        return { stdout: e.stdout ?? '', stderr: e.stderr ?? '', exitCode: e.exitCode ?? 1 };
    }
}
async function isGitRepo(dir) {
    try {
        await (0, execa_1.execa)('git', ['-C', dir, 'rev-parse', '--is-inside-work-tree']);
        return true;
    }
    catch {
        return false;
    }
}
async function getCurrentBranch(dir) {
    try {
        const { stdout } = await (0, execa_1.execa)('git', ['-C', dir, 'rev-parse', '--abbrev-ref', 'HEAD']);
        return stdout.trim();
    }
    catch {
        return null;
    }
}
async function getGitRoot(dir) {
    try {
        const { stdout } = await (0, execa_1.execa)('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
        return stdout.trim();
    }
    catch {
        return null;
    }
}
async function pathExists(p) {
    return fs.pathExists(p);
}
async function getNpmGlobalBin() {
    try {
        const { stdout } = await (0, execa_1.execa)('npm', ['bin', '-g']);
        return stdout.trim();
    }
    catch {
        return '/usr/local/bin';
    }
}
//# sourceMappingURL=shell.js.map