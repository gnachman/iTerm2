import { execa, ExecaError } from 'execa';
import * as fs from 'fs-extra';

export async function commandExists(cmd: string): Promise<boolean> {
  try {
    await execa('which', [cmd]);
    return true;
  } catch {
    return false;
  }
}

export async function getCommandVersion(cmd: string, versionFlag = '--version'): Promise<string | null> {
  try {
    const { stdout } = await execa(cmd, [versionFlag]);
    const match = stdout.match(/(\d+\.\d+[\.\d]*)/);
    return match ? match[1] : stdout.trim().split('\n')[0];
  } catch {
    return null;
  }
}

export async function runShell(cmd: string, args: string[] = [], cwd?: string): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  try {
    const result = await execa(cmd, args, { cwd, all: true });
    return { stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode ?? 0 };
  } catch (err) {
    const e = err as ExecaError;
    return { stdout: e.stdout ?? '', stderr: e.stderr ?? '', exitCode: e.exitCode ?? 1 };
  }
}

export async function isGitRepo(dir: string): Promise<boolean> {
  try {
    await execa('git', ['-C', dir, 'rev-parse', '--is-inside-work-tree']);
    return true;
  } catch {
    return false;
  }
}

export async function getCurrentBranch(dir: string): Promise<string | null> {
  try {
    const { stdout } = await execa('git', ['-C', dir, 'rev-parse', '--abbrev-ref', 'HEAD']);
    return stdout.trim();
  } catch {
    return null;
  }
}

export async function getGitRoot(dir: string): Promise<string | null> {
  try {
    const { stdout } = await execa('git', ['-C', dir, 'rev-parse', '--show-toplevel']);
    return stdout.trim();
  } catch {
    return null;
  }
}

export async function pathExists(p: string): Promise<boolean> {
  return fs.pathExists(p);
}

export async function getNpmGlobalBin(): Promise<string> {
  try {
    const { stdout } = await execa('npm', ['bin', '-g']);
    return stdout.trim();
  } catch {
    return '/usr/local/bin';
  }
}
