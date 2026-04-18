# Database Setup Guide — MomenTerm

## Recommended Options

### Supabase (Recommended for new projects)

```bash
mt skills install db-supabase
mt skills run db-supabase
```

1. Create project at supabase.com
2. Copy connection string from Settings > Database
3. Add to `.env`: `DATABASE_URL=postgresql://...`
4. Initialize schema: `npx supabase db push`

### Neon (Serverless PostgreSQL)

```bash
mt skills install db-neon
mt skills run db-neon
```

1. Create project at neon.tech
2. Copy connection string
3. Add to `.env`: `DATABASE_URL=postgresql://...`

## Environment Variables

Never commit database credentials. Use `.env` (which is in `.gitignore`):

```env
DATABASE_URL=postgresql://user:password@host:5432/dbname
DATABASE_POOL_SIZE=10
```

## MCP Integration

Connect Claude Code to your database via MCP:

```bash
mt mcp setup postgres
```

This adds the PostgreSQL MCP server to `.claude/mcp.json`.
