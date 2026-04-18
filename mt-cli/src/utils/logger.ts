import chalk from 'chalk';

const PREFIX = chalk.bold.cyan('mt');

export const logger = {
  info: (msg: string) => console.log(`${PREFIX} ${chalk.blue('ℹ')} ${msg}`),
  success: (msg: string) => console.log(`${PREFIX} ${chalk.green('✓')} ${msg}`),
  warn: (msg: string) => console.log(`${PREFIX} ${chalk.yellow('⚠')} ${msg}`),
  error: (msg: string) => console.error(`${PREFIX} ${chalk.red('✗')} ${msg}`),
  step: (msg: string) => console.log(`  ${chalk.dim('→')} ${msg}`),
  header: (msg: string) => {
    const line = '─'.repeat(Math.min(msg.length + 4, 60));
    console.log();
    console.log(chalk.bold.cyan(`  ${msg}`));
    console.log(chalk.dim(`  ${line}`));
  },
  section: (title: string, items: string[]) => {
    console.log();
    console.log(chalk.bold(`  ${title}`));
    items.forEach(item => console.log(`    ${chalk.dim('•')} ${item}`));
  },
  table: (rows: [string, string][]) => {
    const maxKey = Math.max(...rows.map(([k]) => k.length));
    rows.forEach(([key, val]) => {
      console.log(`    ${chalk.dim(key.padEnd(maxKey + 2))} ${val}`);
    });
  },
  blank: () => console.log(),
};
