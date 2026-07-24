# Configuration Templates

Copy these templates to `~/.claude/` and customize for your environment:

```bash
cp tcsm-projects.json.template ~/.claude/tcsm-projects.json
cp accounts.json.template ~/.claude/accounts.json
```

## tcsm-projects.json

Maps project names to directory paths and settings for TCSM (tmux-claude-session-manager).

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
tcsm-start myproject
# Opens ~/src/myproject in Claude
```

## accounts.json

Tracks Claude accounts and their configuration.

**Environment variable override**:
```bash
PROJECT_CONFIG_FILE=/custom/path/tcsm-projects.json tcsm-start myproject
```
