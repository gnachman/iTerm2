export type AITool = 'claude_code' | 'codex' | 'both' | 'none';
export type TmuxMode = 'disabled' | 'new_session' | 'existing_session';
export type OpenMode = 'new_tab' | 'new_window';
export interface MTProject {
    id: string;
    name: string;
    path: string;
    aiTool: AITool;
    tmuxMode: TmuxMode;
    tmuxSession?: string;
    createdAt: string;
    lastOpenedAt?: string;
}
export interface MTProjectSpace {
    id: string;
    name: string;
    projects: MTProject[];
}
export interface MTConfig {
    version: number;
    spaces: MTProjectSpace[];
    preferences: {
        defaultAITool: AITool;
        defaultTmuxMode: TmuxMode;
        defaultOpenMode: OpenMode;
        checkAIToolsOnOpen: boolean;
        statusBarItems: string[];
    };
}
export interface PluginRecord {
    id: string;
    name: string;
    version: string;
    source: string;
    installedAt: string;
    enabled: boolean;
}
export interface SkillRecord {
    id: string;
    name: string;
    version: string;
    source: string;
    installedAt: string;
}
export interface MTRegistry {
    version: number;
    plugins: PluginRecord[];
    skills: SkillRecord[];
    lastUpdated: string;
}
export interface HarnessConfig {
    projectName: string;
    projectType: string;
    collaborators: number;
    documentationImportance: 'low' | 'medium' | 'high';
    deploymentLevel: 'local' | 'staging' | 'production';
    securityLevel: 'minimal' | 'standard' | 'strict';
    automationScope: string[];
    aiScope: string[];
    staticAnalysis: {
        lint: boolean;
        typeCheck: boolean;
        securityScan: boolean;
        formatting: boolean;
    };
}
export interface VibeReadinessReport {
    totalScore: number;
    grade: 'A' | 'B' | 'C' | 'D' | 'F';
    categories: {
        name: string;
        score: number;
        weight: number;
        issues: string[];
        recommendations: string[];
    }[];
    mustHaveItems: string[];
    niceToHaveItems: string[];
    priorityActions: string[];
    generatedAt: string;
}
//# sourceMappingURL=types.d.ts.map