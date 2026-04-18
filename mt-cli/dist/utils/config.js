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
exports.PLUGINS_DIR = exports.SKILLS_DIR = exports.REGISTRY_PATH = exports.CONFIG_PATH = exports.MT_HOME = void 0;
exports.ensureMTHome = ensureMTHome;
exports.loadConfig = loadConfig;
exports.saveConfig = saveConfig;
exports.loadRegistry = loadRegistry;
exports.saveRegistry = saveRegistry;
exports.generateId = generateId;
exports.findProjectByPath = findProjectByPath;
const fs = __importStar(require("fs-extra"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
exports.MT_HOME = path.join(os.homedir(), '.momenterm');
exports.CONFIG_PATH = path.join(exports.MT_HOME, 'config.json');
exports.REGISTRY_PATH = path.join(exports.MT_HOME, 'registry.json');
exports.SKILLS_DIR = path.join(exports.MT_HOME, 'skills');
exports.PLUGINS_DIR = path.join(exports.MT_HOME, 'plugins');
const DEFAULT_CONFIG = {
    version: 1,
    spaces: [],
    preferences: {
        defaultAITool: 'claude_code',
        defaultTmuxMode: 'disabled',
        defaultOpenMode: 'new_tab',
        checkAIToolsOnOpen: true,
        statusBarItems: ['project', 'branch', 'model', 'session'],
    },
};
const DEFAULT_REGISTRY = {
    version: 1,
    plugins: [],
    skills: [],
    lastUpdated: new Date().toISOString(),
};
async function ensureMTHome() {
    await fs.ensureDir(exports.MT_HOME);
    await fs.ensureDir(exports.SKILLS_DIR);
    await fs.ensureDir(exports.PLUGINS_DIR);
}
async function loadConfig() {
    await ensureMTHome();
    if (!(await fs.pathExists(exports.CONFIG_PATH))) {
        await fs.writeJson(exports.CONFIG_PATH, DEFAULT_CONFIG, { spaces: 2 });
        return DEFAULT_CONFIG;
    }
    return await fs.readJson(exports.CONFIG_PATH);
}
async function saveConfig(config) {
    await ensureMTHome();
    await fs.writeJson(exports.CONFIG_PATH, config, { spaces: 2 });
}
async function loadRegistry() {
    await ensureMTHome();
    if (!(await fs.pathExists(exports.REGISTRY_PATH))) {
        await fs.writeJson(exports.REGISTRY_PATH, DEFAULT_REGISTRY, { spaces: 2 });
        return DEFAULT_REGISTRY;
    }
    return await fs.readJson(exports.REGISTRY_PATH);
}
async function saveRegistry(registry) {
    await ensureMTHome();
    await fs.writeJson(exports.REGISTRY_PATH, registry, { spaces: 2 });
}
function generateId() {
    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}
async function findProjectByPath(targetPath) {
    const config = await loadConfig();
    const resolvedTarget = path.resolve(targetPath);
    for (const space of config.spaces) {
        for (const project of space.projects) {
            if (path.resolve(project.path) === resolvedTarget) {
                return { spaceId: space.id, project };
            }
        }
    }
    return null;
}
//# sourceMappingURL=config.js.map