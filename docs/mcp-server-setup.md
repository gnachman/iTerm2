# MCP Server Setup — MomenTerm

> Model Context Protocol (MCP) lets Claude Code access external tools and data sources.

## Quick Start

```bash
mt mcp setup          # Interactive setup wizard
mt mcp list           # List available servers
mt mcp status         # Show configured servers
```

## Available Servers

| Server | Purpose | Package |
|---|---|---|
| filesystem | Local file access | @modelcontextprotocol/server-filesystem |
| github | GitHub API | @modelcontextprotocol/server-github |
| postgres | PostgreSQL access | @modelcontextprotocol/server-postgres |
| slack | Slack workspace | @modelcontextprotocol/server-slack |
| brave-search | Web search | @modelcontextprotocol/server-brave-search |
| puppeteer | Browser automation | @modelcontextprotocol/server-puppeteer |

## Configuration Location

`.claude/mcp.json` in the project root.

## Security Policy

- Grant minimal required permissions per server
- Rotate API keys every 90 days
- Do not commit API keys — use environment variables
- Review scope settings in Claude Code preferences

## Restart After Changes

```bash
# Restart Claude Code to load new MCP servers
claude restart
```

## Troubleshooting

- Verify Node.js >= 18: `node --version`
- Test server directly: `npx @modelcontextprotocol/server-filesystem --help`
- Check Claude Code logs: `~/.claude/logs/`
