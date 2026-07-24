# Configuration Templates

Copy these templates to `~/.claude/` and customize for your environment:

```bash
cp project-sessions.json.template ~/.claude/project-sessions.json
cp accounts.json.template ~/.claude/accounts.json
```

## project-sessions.json

Maps project names to directory paths and settings.

**Example**:
```json
{
  "sessions": {
    "myproject": {
      "path": "${HOME}/src/myproject",
      "model": "haiku"
    }
  }
}
```

**Usage in skill**:
```bash
start-claude-project myproject
# Opens ~/src/myproject in Claude
```

## accounts.json

Tracks Claude accounts and their configuration.

**Environment variable override**:
```bash
PROJECT_CONFIG_FILE=/custom/path/project-sessions.json start-claude-project myproject
```
