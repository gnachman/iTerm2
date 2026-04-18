import * as fs from 'fs-extra';
import * as path from 'path';
import * as os from 'os';
import type { MTConfig, MTRegistry } from '../types.js';

export const MT_HOME = path.join(os.homedir(), '.momenterm');
export const CONFIG_PATH = path.join(MT_HOME, 'config.json');
export const REGISTRY_PATH = path.join(MT_HOME, 'registry.json');
export const SKILLS_DIR = path.join(MT_HOME, 'skills');
export const PLUGINS_DIR = path.join(MT_HOME, 'plugins');

const DEFAULT_CONFIG: MTConfig = {
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

const DEFAULT_REGISTRY: MTRegistry = {
  version: 1,
  plugins: [],
  skills: [],
  lastUpdated: new Date().toISOString(),
};

export async function ensureMTHome(): Promise<void> {
  await fs.ensureDir(MT_HOME);
  await fs.ensureDir(SKILLS_DIR);
  await fs.ensureDir(PLUGINS_DIR);
}

export async function loadConfig(): Promise<MTConfig> {
  await ensureMTHome();
  if (!(await fs.pathExists(CONFIG_PATH))) {
    await fs.writeJson(CONFIG_PATH, DEFAULT_CONFIG, { spaces: 2 });
    return DEFAULT_CONFIG;
  }
  return await fs.readJson(CONFIG_PATH);
}

export async function saveConfig(config: MTConfig): Promise<void> {
  await ensureMTHome();
  await fs.writeJson(CONFIG_PATH, config, { spaces: 2 });
}

export async function loadRegistry(): Promise<MTRegistry> {
  await ensureMTHome();
  if (!(await fs.pathExists(REGISTRY_PATH))) {
    await fs.writeJson(REGISTRY_PATH, DEFAULT_REGISTRY, { spaces: 2 });
    return DEFAULT_REGISTRY;
  }
  return await fs.readJson(REGISTRY_PATH);
}

export async function saveRegistry(registry: MTRegistry): Promise<void> {
  await ensureMTHome();
  await fs.writeJson(REGISTRY_PATH, registry, { spaces: 2 });
}

export function generateId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

export async function findProjectByPath(targetPath: string): Promise<{ spaceId: string; project: import('../types.js').MTProject } | null> {
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
