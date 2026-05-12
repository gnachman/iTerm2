import { Command } from 'commander';
import inquirer from 'inquirer';
import ora from 'ora';
import * as fs from 'fs-extra';
import * as path from 'path';
import { logger } from '../utils/logger.js';

const MCP_SERVERS = [
  { id: 'filesystem', name: 'Filesystem', description: 'Local file access for Claude', pkg: '@modelcontextprotocol/server-filesystem' },
  { id: 'github', name: 'GitHub', description: 'GitHub API integration', pkg: '@modelcontextprotocol/server-github' },
  { id: 'slack', name: 'Slack', description: 'Slack workspace access', pkg: '@modelcontextprotocol/server-slack' },
  { id: 'postgres', name: 'PostgreSQL', description: 'PostgreSQL database access', pkg: '@modelcontextprotocol/server-postgres' },
  { id: 'brave-search', name: 'Brave Search', description: 'Web search via Brave', pkg: '@modelcontextprotocol/server-brave-search' },
  { id: 'puppeteer', name: 'Puppeteer', description: 'Browser automation', pkg: '@modelcontextprotocol/server-puppeteer' },
];

export function mcpCommand(program: Command): void {
  const mcp = program
    .command('mcp')
    .description('MCP server setup and management');

  mcp
    .command('list')
    .description('List available MCP servers')
    .action(async () => {
      logger.header('Available MCP Servers');
      logger.blank();
      for (const s of MCP_SERVERS) {
        console.log(`  ${chalk_bold(s.name).padEnd(20)} ${s.description}`);
        console.log(`  ${dim_text('npm: ' + s.pkg)}`);
        console.log();
      }
    });

  mcp
    .command('setup [server]')
    .description('Set up an MCP server with Claude Code integration')
    .option('--dir <path>', 'Project directory', process.cwd())
    .action(async (server?: string, opts?: { dir: string }) => {
      const targetDir = path.resolve(opts?.dir ?? process.cwd());
      logger.header('MCP Server Setup');

      let selectedServer = MCP_SERVERS.find(s => s.id === server);

      if (!selectedServer) {
        const { choice } = await inquirer.prompt([{
          type: 'list',
          name: 'choice',
          message: 'Select MCP server to configure:',
          choices: MCP_SERVERS.map(s => ({ name: `${s.name} — ${s.description}`, value: s.id })),
        }]);
        selectedServer = MCP_SERVERS.find(s => s.id === choice)!;
      }

      const spinner = ora(`Generating MCP config for ${selectedServer.name}…`).start();
      await fs.ensureDir(path.join(targetDir, 'docs'));

      // Generate MCP config
      const mcpConfigPath = path.join(targetDir, '.claude', 'mcp.json');
      await fs.ensureDir(path.join(targetDir, '.claude'));

      let existingConfig: Record<string, unknown> = {};
      if (await fs.pathExists(mcpConfigPath)) {
        existingConfig = await fs.readJson(mcpConfigPath);
      }

      const servers = (existingConfig.mcpServers as Record<string, unknown>) ?? {};
      servers[selectedServer.id] = {
        command: 'npx',
        args: ['-y', selectedServer.pkg],
      };
      existingConfig.mcpServers = servers;

      await fs.writeJson(mcpConfigPath, existingConfig, { spaces: 2 });

      // Generate docs
      await fs.writeFile(
        path.join(targetDir, `docs/mcp-${selectedServer.id}-setup.md`),
        generateMCPDoc(selectedServer)
      );

      spinner.succeed(`MCP config generated for ${selectedServer.name}`);
      logger.blank();
      logger.section('Files created', [
        '.claude/mcp.json (updated)',
        `docs/mcp-${selectedServer.id}-setup.md`,
      ]);
      logger.blank();
      logger.info('Restart Claude Code to load the new MCP server.');
      logger.step(`Run: claude restart`);
    });

  mcp
    .command('status [directory]')
    .description('Show configured MCP servers')
    .action(async (directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const mcpConfigPath = path.join(dir, '.claude', 'mcp.json');

      logger.header('MCP Server Status');

      if (!(await fs.pathExists(mcpConfigPath))) {
        logger.warn('No MCP configuration found. Run: mt mcp setup');
        return;
      }

      const config = await fs.readJson(mcpConfigPath);
      const servers = config.mcpServers ?? {};
      const keys = Object.keys(servers);

      if (keys.length === 0) {
        logger.info('No MCP servers configured.');
        return;
      }

      logger.blank();
      for (const key of keys) {
        const s = servers[key] as { command: string; args: string[] };
        console.log(`  ${chalk_bold(key)}`);
        console.log(`    ${dim_text(`${s.command} ${(s.args ?? []).join(' ')}`)}`);
      }
      logger.blank();
      logger.info(`${keys.length} server(s) configured.`);
    });

  mcp
    .command('remove <server> [directory]')
    .description('Remove an MCP server configuration')
    .action(async (server: string, directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const mcpConfigPath = path.join(dir, '.claude', 'mcp.json');

      if (!(await fs.pathExists(mcpConfigPath))) {
        logger.error('No MCP config found.');
        return;
      }

      const config = await fs.readJson(mcpConfigPath);
      if (!config.mcpServers?.[server]) {
        logger.error(`Server "${server}" not found in MCP config.`);
        return;
      }

      delete config.mcpServers[server];
      await fs.writeJson(mcpConfigPath, config, { spaces: 2 });
      logger.success(`MCP server "${server}" removed from config.`);
    });

  mcp
    .command('scope [directory]')
    .description('Apply least-privilege scope policy to all configured MCP servers')
    .option('--show', 'Show current policy without writing')
    .action(async (directory?: string, opts?: { show?: boolean }) => {
      const dir = path.resolve(directory ?? process.cwd());
      const mcpConfigPath = path.join(dir, '.claude', 'mcp.json');
      const scopePolicyPath = path.join(dir, '.claude', 'mcp-scope.json');

      logger.header('MCP Scope Policy');

      if (!(await fs.pathExists(mcpConfigPath))) {
        logger.warn('No MCP config found. Run: mt mcp setup');
        return;
      }

      const config = await fs.readJson(mcpConfigPath);
      const serverIds = Object.keys(config.mcpServers ?? {});

      if (serverIds.length === 0) {
        logger.info('No MCP servers configured.');
        return;
      }

      // Build least-privilege policy for each server
      const policy: Record<string, ScopePolicy> = {};
      for (const id of serverIds) {
        policy[id] = buildLeastPrivilegePolicy(id);
      }

      if (opts?.show) {
        logger.blank();
        console.log(JSON.stringify(policy, null, 2));
        return;
      }

      await fs.ensureDir(path.join(dir, '.claude'));
      await fs.writeJson(scopePolicyPath, {
        version: 1,
        generatedAt: new Date().toISOString(),
        note: 'Least-privilege MCP scope policy. Review before applying.',
        servers: policy,
      }, { spaces: 2 });

      logger.success(`Scope policy written to .claude/mcp-scope.json`);
      logger.blank();
      for (const [id, p] of Object.entries(policy)) {
        console.log(`  ${chalk_bold(id)}`);
        console.log(`    ${dim_text('allow: ' + p.allow.join(', '))}`);
        if (p.deny.length > 0) {
          console.log(`    ${dim_text('deny:  ' + p.deny.join(', '))}`);
        }
      }
      logger.blank();
      logger.info('Review and commit .claude/mcp-scope.json alongside mcp.json.');
    });

  mcp
    .command('audit [directory]')
    .description('Audit MCP servers for scope policy compliance')
    .action(async (directory?: string) => {
      const dir = path.resolve(directory ?? process.cwd());
      const mcpConfigPath = path.join(dir, '.claude', 'mcp.json');
      const scopePolicyPath = path.join(dir, '.claude', 'mcp-scope.json');

      logger.header('MCP Scope Audit');

      if (!(await fs.pathExists(mcpConfigPath))) {
        logger.warn('No MCP config found. Run: mt mcp setup');
        return;
      }

      const config = await fs.readJson(mcpConfigPath);
      const serverIds = Object.keys(config.mcpServers ?? {});
      let issues = 0;

      for (const id of serverIds) {
        const knownServer = MCP_SERVERS.find(s => s.id === id);
        const hasScopePolicy = await fs.pathExists(scopePolicyPath);

        if (!knownServer) {
          console.log(`  \x1b[33m⚠\x1b[0m ${chalk_bold(id)} — unknown server, review manually`);
          issues++;
        } else if (!hasScopePolicy) {
          console.log(`  \x1b[33m⚠\x1b[0m ${chalk_bold(id)} — no scope policy. Run: mt mcp scope`);
          issues++;
        } else {
          const policyFile = await fs.readJson(scopePolicyPath);
          const serverPolicy = policyFile.servers?.[id] as ScopePolicy | undefined;
          if (!serverPolicy) {
            console.log(`  \x1b[33m⚠\x1b[0m ${chalk_bold(id)} — missing from scope policy`);
            issues++;
          } else {
            console.log(`  \x1b[32m✓\x1b[0m ${chalk_bold(id)} — policy OK (${serverPolicy.allow.join(', ')})`);
          }
        }
      }

      logger.blank();
      if (issues === 0) {
        logger.success('All MCP servers have scope policies.');
      } else {
        logger.warn(`${issues} server(s) need scope policy review.`);
      }
    });
}

interface ScopePolicy {
  allow: string[];
  deny: string[];
  notes: string;
}

// Least-privilege default scopes per known server type
function buildLeastPrivilegePolicy(serverId: string): ScopePolicy {
  const policies: Record<string, ScopePolicy> = {
    filesystem: {
      allow: ['read'],
      deny: ['write', 'delete', 'execute'],
      notes: 'Read-only by default. Add write scope only for specific directories.',
    },
    github: {
      allow: ['repo:read', 'issues:read', 'pulls:read'],
      deny: ['repo:write', 'admin:org', 'delete_repo'],
      notes: 'Read-only repo access. Do not grant admin scopes.',
    },
    slack: {
      allow: ['channels:read', 'chat:write'],
      deny: ['admin', 'files:write', 'users:write'],
      notes: 'Send messages only. No admin or user management.',
    },
    postgres: {
      allow: ['SELECT'],
      deny: ['INSERT', 'UPDATE', 'DELETE', 'DROP', 'CREATE'],
      notes: 'Read-only SQL. Create a dedicated read-only DB user.',
    },
    'brave-search': {
      allow: ['search:web'],
      deny: [],
      notes: 'Web search only. No API key sharing.',
    },
    puppeteer: {
      allow: ['navigate', 'screenshot'],
      deny: ['download', 'file:write'],
      notes: 'Navigation and screenshots only. Disable file downloads.',
    },
  };
  return policies[serverId] ?? {
    allow: ['read'],
    deny: ['write', 'delete', 'admin'],
    notes: 'Unknown server — conservative read-only default applied.',
  };
}

function chalk_bold(s: string): string {
  return `\x1b[1m${s}\x1b[0m`;
}

function dim_text(s: string): string {
  return `\x1b[2m${s}\x1b[0m`;
}

function generateMCPDoc(server: typeof MCP_SERVERS[0]): string {
  return `# MCP Server Setup: ${server.name}

> Generated by MomenTerm mt CLI

## Overview
${server.description}

## Installation
The server is automatically started by Claude Code via npx.
No manual installation required.

## Configuration
The configuration has been added to \`.claude/mcp.json\`:

\`\`\`json
{
  "mcpServers": {
    "${server.id}": {
      "command": "npx",
      "args": ["-y", "${server.pkg}"]
    }
  }
}
\`\`\`

## Usage with Claude Code
Once configured, Claude Code can use the ${server.name} MCP server.
Restart Claude Code to activate: \`claude restart\`

## Scope Policy
- Only grant minimal required permissions
- Review scope settings in Claude Code settings
- Rotate API keys regularly if applicable

## Troubleshooting
- Ensure Node.js >= 18 is installed
- Run \`npx ${server.pkg} --help\` to test server directly
- Check Claude Code logs if server fails to start
`;
}
