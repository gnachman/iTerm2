import { Command } from 'commander';
import * as fs from 'fs-extra';
import * as path from 'path';
import chalk from 'chalk';
import { logger } from '../utils/logger.js';
import { getCurrentBranch } from '../utils/shell.js';

export function handoffCommand(program: Command): void {
  const handoff = program
    .command('handoff [directory]')
    .description('Manage handoff.md work context');

  handoff
    .command('show [directory]')
    .description('Show current handoff status')
    .action(async (directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const handoffPath = path.join(dir, 'handoff.md');

      if (!(await fs.pathExists(handoffPath))) {
        logger.warn('No handoff.md found. Run: mt init');
        return;
      }

      const content = await fs.readFile(handoffPath, 'utf-8');
      logger.header('Handoff Status');
      console.log(content);
    });

  handoff
    .command('update <section> <content> [directory]')
    .description('Update a section of handoff.md')
    .action(async (section: string, content: string, directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      await updateHandoffSection(dir, section, content);
    });

  handoff
    .command('sync [directory]')
    .description('Sync handoff.md with current git state')
    .action(async (directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const handoffPath = path.join(dir, 'handoff.md');

      if (!(await fs.pathExists(handoffPath))) {
        logger.warn('No handoff.md. Run: mt init');
        return;
      }

      const branch = await getCurrentBranch(dir);
      await updateHandoffSection(dir, '관련 브랜치', branch ?? 'unknown');
      await updateHandoffLastUpdated(dir);
      logger.success('handoff.md synced with current git state');
      if (branch) logger.step(`Branch: ${branch}`);
    });

  handoff
    .command('done <task> [directory]')
    .description('Mark a task as done in handoff.md')
    .action(async (task: string, directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const handoffPath = path.join(dir, 'handoff.md');

      if (!(await fs.pathExists(handoffPath))) {
        logger.warn('No handoff.md. Run: mt init');
        return;
      }

      let content = await fs.readFile(handoffPath, 'utf-8');
      // Mark in-progress items that match as done
      content = content.replace(
        new RegExp(`- \\[ \\] (.*${escapeRegex(task)}.*)`, 'gi'),
        `- [x] $1`
      );
      await fs.writeFile(handoffPath, content);
      await updateHandoffLastUpdated(dir);
      logger.success(`Marked "${task}" as done in handoff.md`);
    });

  handoff
    .command('reset [directory]')
    .description('Reset handoff.md for a new session')
    .action(async (directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const handoffPath = path.join(dir, 'handoff.md');

      if (!(await fs.pathExists(handoffPath))) {
        logger.warn('No handoff.md found.');
        return;
      }

      await updateHandoffLastUpdated(dir);
      logger.success('handoff.md updated for new session');
      logger.step('Update the "현재 목표" and "다음 액션" sections manually.');
    });
}

async function updateHandoffSection(dir: string, sectionName: string, content: string): Promise<void> {
  const handoffPath = path.join(dir, 'handoff.md');
  if (!(await fs.pathExists(handoffPath))) {
    logger.error('handoff.md not found');
    return;
  }

  let text = await fs.readFile(handoffPath, 'utf-8');
  const sectionRegex = new RegExp(`(## ${escapeRegex(sectionName)}\\n)([^#]*)`, 'm');
  const match = text.match(sectionRegex);

  if (match) {
    text = text.replace(sectionRegex, `$1${content}\n\n`);
  } else {
    text += `\n## ${sectionName}\n${content}\n`;
  }

  await fs.writeFile(handoffPath, text);
  logger.success(`Updated section "${sectionName}"`);
}

async function updateHandoffLastUpdated(dir: string): Promise<void> {
  const handoffPath = path.join(dir, 'handoff.md');
  let text = await fs.readFile(handoffPath, 'utf-8');
  const now = new Date().toLocaleString('ko-KR');
  text = text.replace(/> 마지막 업데이트:.*/, `> 마지막 업데이트: ${now}`);
  await fs.writeFile(handoffPath, text);
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
