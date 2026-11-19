#!/usr/bin/env python3
"""Turn agent definition files into the JSON that `claude --agents` takes.

Part of the Objective-C to Swift migration tooling. Python 3 standard
library only.

The migration's author and reviewer agents are defined in
.claude/agents/*.md (DEFAULT_DEFINITIONS_DIR, relative to the repository
root), the project location Claude Code reads subagents from: a frontmatter
block between "---" lines with one "key: value" per line, then the system
prompt as Markdown. The repository's .gitignore ignores .claude/* except
.claude/agents/, so these files are tracked, a clone has them, and an
interactive session started in the clone finds them by itself
(code.claude.com/docs/en/sub-agents, "Choose the subagent scope").

Claude Code also accepts the same definitions as JSON with `--agents`: an
object keyed by agent name, each value holding the frontmatter fields plus
"prompt" for the body; with `-p` the flag also accepts the path to a file
holding that object, and an interactive session refuses a file path. The
nightly start script does not pass --agents any more; it runs this tool
with --require-model opus only to check that the definitions parse and pin
Opus before it starts the session.

Only single-line values are supported; anything else is refused, as is any
field --agents does not document, so a typo cannot silently drop a setting.

Usage:
    agents_json.py [--require-model opus] [--output FILE] [DEFINITION.md...]
With no DEFINITION.md, every *.md in DEFAULT_DEFINITIONS_DIR is converted.
Exit status: 0 on success, 1 on any error (nothing is written).
"""

import argparse
import glob
import json
import os
import sys

DEFAULT_DEFINITIONS_DIR = os.path.join('.claude', 'agents')
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

# Fields the documentation lists for --agents, besides "prompt".
STRING_FIELDS = {'description', 'model', 'permissionMode', 'effort',
                 'isolation', 'initialPrompt', 'memory'}
LIST_FIELDS = {'tools', 'disallowedTools', 'skills', 'mcpServers'}
INT_FIELDS = {'maxTurns', 'autoCompactWindow'}
BOOL_FIELDS = {'background', 'omitClaudeMd'}
# Accepted in files but ignored by --agents, per the documentation.
IGNORED_FIELDS = {'color', 'experimental'}


class DefinitionError(Exception):
    pass


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
        return value[1:-1]
    return value


def parse_definition(path, text):
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        raise DefinitionError('%s: no frontmatter (first line must be ---)'
                              % path)
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
    except StopIteration:
        raise DefinitionError('%s: frontmatter is not closed with ---' % path)
    fields = {}
    for number, line in enumerate(lines[1:end], start=2):
        if not line.strip():
            continue
        if line[:1].isspace() or ':' not in line:
            raise DefinitionError('%s:%d: only single-line "key: value" '
                                  'fields are supported' % (path, number))
        key, value = line.split(':', 1)
        key = key.strip()
        value = unquote(value.strip())
        if value in ('>', '|', '>-', '|-', ''):
            raise DefinitionError('%s:%d: %s has no single-line value'
                                  % (path, number, key))
        if key in fields:
            raise DefinitionError('%s:%d: %s appears twice'
                                  % (path, number, key))
        fields[key] = value
    body = '\n'.join(lines[end + 1:]).lstrip('\n')

    name = fields.pop('name', None)
    if not name:
        raise DefinitionError('%s: no name' % path)
    if not fields.get('description'):
        raise DefinitionError('%s: no description' % path)
    agent = {}
    for key, value in fields.items():
        if key in STRING_FIELDS:
            agent[key] = value
        elif key in LIST_FIELDS:
            agent[key] = [item.strip() for item in value.split(',')
                          if item.strip()]
        elif key in INT_FIELDS:
            try:
                agent[key] = int(value)
            except ValueError:
                raise DefinitionError('%s: %s must be an integer' % (path, key))
        elif key in BOOL_FIELDS:
            if value not in ('true', 'false'):
                raise DefinitionError('%s: %s must be true or false'
                                      % (path, key))
            agent[key] = value == 'true'
        elif key in IGNORED_FIELDS:
            continue
        else:
            raise DefinitionError('%s: unknown field %r' % (path, key))
    agent['prompt'] = body
    return name, agent


def convert(paths, require_model=None):
    result = {}
    for path in paths:
        try:
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
        except OSError as e:
            raise DefinitionError('%s: %s' % (path, e))
        name, agent = parse_definition(path, text)
        if name in result:
            raise DefinitionError('%s: agent name %r is defined twice'
                                  % (path, name))
        if require_model and agent.get('model') != require_model:
            raise DefinitionError('%s: model is %r, not %r'
                                  % (path, agent.get('model'), require_model))
        result[name] = agent
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--output', help='write here instead of stdout')
    parser.add_argument('--require-model',
                        help='fail unless every definition sets this model')
    parser.add_argument('paths', nargs='*')
    args = parser.parse_args(argv)
    paths = args.paths or sorted(glob.glob(os.path.join(
        REPO_ROOT, DEFAULT_DEFINITIONS_DIR, '*.md')))
    if not paths:
        print('agents_json: no definitions in %s' % DEFAULT_DEFINITIONS_DIR,
              file=sys.stderr)
        return 1
    try:
        data = convert(paths, args.require_model)
    except DefinitionError as e:
        print('agents_json: %s' % e, file=sys.stderr)
        return 1
    text = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as fh:
                fh.write(text)
        except OSError as e:
            print('agents_json: %s' % e, file=sys.stderr)
            return 1
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
