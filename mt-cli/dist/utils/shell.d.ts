export declare function commandExists(cmd: string): Promise<boolean>;
export declare function getCommandVersion(cmd: string, versionFlag?: string): Promise<string | null>;
export declare function runShell(cmd: string, args?: string[], cwd?: string): Promise<{
    stdout: string;
    stderr: string;
    exitCode: number;
}>;
export declare function isGitRepo(dir: string): Promise<boolean>;
export declare function getCurrentBranch(dir: string): Promise<string | null>;
export declare function getGitRoot(dir: string): Promise<string | null>;
export declare function pathExists(p: string): Promise<boolean>;
export declare function getNpmGlobalBin(): Promise<string>;
//# sourceMappingURL=shell.d.ts.map