import type { MTConfig, MTRegistry } from '../types.js';
export declare const MT_HOME: string;
export declare const CONFIG_PATH: string;
export declare const REGISTRY_PATH: string;
export declare const SKILLS_DIR: string;
export declare const PLUGINS_DIR: string;
export declare function ensureMTHome(): Promise<void>;
export declare function loadConfig(): Promise<MTConfig>;
export declare function saveConfig(config: MTConfig): Promise<void>;
export declare function loadRegistry(): Promise<MTRegistry>;
export declare function saveRegistry(registry: MTRegistry): Promise<void>;
export declare function generateId(): string;
export declare function findProjectByPath(targetPath: string): Promise<{
    spaceId: string;
    project: import('../types.js').MTProject;
} | null>;
//# sourceMappingURL=config.d.ts.map