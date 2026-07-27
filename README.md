# tmux-claude-session-manager

[![screenshot](./docs/screenshot.jpg)](https://youtu.be/NnTV6r4l5D0)

Run many [Claude Code](https://claude.com/claude-code) sessions across your
projects, each in its own tmux session — then **list them, see which are done
vs. still working, and jump to one** from a single popup.

If you launch Claude per-directory (one nested session per project), you quickly
end up with a dozen of them and no way to tell which are finished without opening
each one. This plugin gives you:

- 🔢 **A central picker** (`prefix` + `u`) listing every running Claude agent —
  several in one project, and any running loose in an ordinary pane.
- 🟢 **Live status** per agent — `working` / `waiting` / `idle` — read straight
  from `claude agents --json`, so you instantly see which need you. No setup.
- 👁️ **A live preview** of each agent's screen right in the picker.
- 🎯 **Smart jump** — selecting an agent switches your client to the window it
  was launched from, then resumes it in a popup over it.
- 🚀 **A launcher** (`prefix` + `y`) that opens/attaches a Claude session for the
  current directory.
- ❌ **Quick kill** (`ctrl-x`) of a finished agent from the picker.

Status needs no configuration. Claude Code publishes each agent's own state and
the picker reads it — there are no hooks to install.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[jq](https://jqlang.org/)** — parses `claude agents --json`
- **[Claude Code](https://claude.com/claude-code)** ≥ 2.1.139 — for the
  `claude agents` command (`claude --version` to check)
- bash; macOS or Linux

## Install (tpm)

Add to `~/.tmux.conf` (or `~/.config/tmux/tmux.conf`):

```tmux
set -g @plugin 'craftzdog/tmux-claude-session-manager'
```

Then hit `prefix` + <kbd>I</kbd> to install.

> **Keybinding note:** by default the plugin binds `prefix` + `y` (launch) and
> `prefix` + `u` (list). If your config binds those elsewhere, either change the
> options below, or make sure the plugin loads **after** your own bindings (put
> `run '~/.tmux/plugins/tpm/tpm'` _after_ them) so the one you want wins.

### Manual install

```sh
git clone https://github.com/craftzdog/tmux-claude-session-manager ~/clone/path
```

Add to `~/.tmux.conf`, then reload (`prefix` + <kbd>r</kbd> or `tmux source ~/.tmux.conf`):

```tmux
run-shell ~/clone/path/claude_session_manager.tmux
```

## Usage

| Key            | Action                                                                          |
| -------------- | ------------------------------------------------------------------------------- |
| `prefix` + `y` | Launch (or re-attach to) a Claude session for the current directory, in a popup |
| `prefix` + `u` | Open the agent picker                                                           |

Inside the picker:

| Key                       | Action                                                |
| ------------------------- | ----------------------------------------------------- |
| `enter`                   | Jump to the agent (see [How it works](#how-it-works)) |
| `ctrl-x`                  | Kill the highlighted agent                            |
| `↑` / `↓`, type to filter | fzf navigation                                        |

Agents needing your attention (`waiting`, `idle`) sort to the top.

Every running Claude gets its own row — the picker identifies each by its process,
not by its tmux session. So several agents in one project all show up separately,
as does a Claude you started by hand in an ordinary pane.

## Options

Set any of these before the plugin loads (defaults shown):

```tmux
set -g @claude_launch_key     'y'        # prefix key: launch/open for current dir
set -g @claude_list_key       'u'        # prefix key: open the picker
set -g @claude_command        'claude'   # command run in new sessions
set -g @claude_args           ''         # extra args appended to the command
set -g @claude_session_prefix 'claude-'  # tmux session name prefix
set -g @claude_popup_width     '90%'     # popup width
set -g @claude_popup_height    '90%'     # popup height
set -g @claude_fzf_options    ''         # extra options passed to the fzf picker
```

For example, to skip permission prompts in launched sessions:

```tmux
set -g @claude_args '--dangerously-skip-permissions'
```

### Customizing the fzf picker

`@claude_fzf_options` is passed straight to `fzf`, so you can add your own bindings.

Here is a vim keybinding example:

```tmux
set -g @claude_fzf_options "\
  --prompt 'nav> ' \
  --bind 'j:down' \
  --bind 'k:up' \
  --bind 'q:abort' \
  --bind 'x:execute-silent(kill {3})+reload(sleep 0.3; \$CLAUDE_PICKER --list)' \
  --bind 'i:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'a:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'esc:rebind(j,k,q,i,a,x)+change-prompt(nav> )'"
```

The picker opens in **nav** mode:

| Key       | Action                                                  |
| --------- | ------------------------------------------------------- |
| `j` / `k` | move down / up                                          |
| `i` / `a` | switch to **filter** mode — type to fuzzy-match         |
| `x`       | kill the highlighted agent (like the built-in `ctrl-x`) |
| `q`       | close the picker                                        |
| `enter`   | jump to the agent (both modes)                          |
| `esc`     | filter mode → back to nav                               |

Only the bound keys are special in nav mode; any other key still filters as you
type. `x` reloads the list through `$CLAUDE_PICKER`, a path the picker exports for
exactly this — write it as `\$CLAUDE_PICKER` inside the double-quoted value above
so tmux stores a literal `$` (in a single-quoted value, use a bare
`$CLAUDE_PICKER`).

## How it works

- The **launcher** creates a detached `claude-<hash-of-dir>` tmux session running
  `claude`, records the window it came from in `@claude_origin`, and attaches to
  it in a popup.
- **`claude agents --json`** is the source of truth for what is running and how it
  is doing. Each Claude session self-reports its state (`busy` / `waiting` /
  `idle`) to a supervisor daemon, which that command publishes. Nothing here scans
  processes for a `claude` command name — on macOS a pane reports its parent shell,
  never the `claude` child running inside it.
- **`agents.sh`** pairs each running Claude with the tmux pane it occupies by
  joining `pid` → `tty` → pane. That join is why identity is the Claude _process_
  rather than the tmux session, and therefore why several agents in one project
  each get their own row. It costs three subprocesses per render, whatever the
  number of sessions or panes.
- The **age column** is the mtime of the agent's transcript — its last sign of
  life. `claude agents --json` reports only `startedAt`, never a last-activity
  time. A brand-new agent that has yet to take a turn shows `-`.
- The **picker** renders those rows with a live `capture-pane` preview. On `enter`
  a **dedicated** agent (in a `claude-*` session) resumes in the popup over the
  window it was launched from, while a **loose** one (any other pane) is focused in
  place. `ctrl-x` kills the Claude process itself: a dedicated session dies with
  its last window, and a loose pane keeps the shell that hosted it.
- Pressing `prefix` + `u` **from inside a session popup** detaches that popup
  first (closing it), then reopens the picker full-size on the outer host client —
  so you never end up with a cramped popup-in-popup.

## License

[MIT](LICENSE) © Takuya Matsuyama

---

## Fork Enhancements

This fork extends the upstream plugin with comprehensive session management tools, multi-VM support, and automated boot-time session restoration via systemd.

### New Features

#### 1. **TCSM Skill** (`skills/`)

A complete shell skill for managing Claude sessions across projects in TCSM (tmux-claude-session-manager) sessions:

```bash
source ~/.claude/skills/tcsm.sh

# Start a project session
tcsm-start myproject

# Stop a project session
tcsm-stop myproject

# Restart a project session
tcsm-restart myproject

# List all active sessions
tcsm-list

# Check session status
tcsm-status

# Attach to a session
tmux attach -t tcsm:myproject
```

**Features:**
- ✅ Interactive sessions in tmux windows (attachable)
- ✅ Start, stop, and restart sessions
- ✅ Auto-registration with Claude CLI
- ✅ Web UI integration via bridgeSessionId
- ✅ Workspace trust pre-configured (see [Known Issues & Workarounds](#known-issues--workarounds))
- ✅ Git-aware project discovery (auto-fallback to real source repos)
- ✅ Project path resolution from configuration
- ✅ Support for local and elevated (sudo) operations
- ✅ Multi-project support with flexible naming
- ✅ Multi-account support with rate-limit tracking
- ✅ Graceful session termination (signal escalation with timeout)

See `skills/README.md` for detailed documentation.

#### 1a. **Git-Aware Project Discovery**

When `tcsm-start` resolves a project directory, it checks whether that directory is under git control. If not, it automatically searches `TCSM_SEARCH_ROOTS` for a same-named directory that is and uses that instead.

**Use case**: Project stubs often exist in configuration directories (e.g., `~/.config/tenant/my-project` with just `config.sh`) before the actual source repository is cloned elsewhere (e.g., `~/src/my-project`). Running `tcsm-start my-project` will find and use the real git-controlled source automatically.

```bash
# Example: my-project doesn't exist as a git repo in the config stub, but tcsm-start finds it elsewhere
$ tcsm-start my-project
[INFO] No git-controlled source folder found for 'my-project'...
       continuing with ~/.config/tenant/my-project

# If it existed at ~/src/my-project, it would log:
[INFO] '~/.config/tenant/my-project' is not under git control;
       using git-controlled source instead: ~/src/my-project
```

Configure search roots via `TCSM_SEARCH_ROOTS` (space-separated paths where git-controlled sources are located).

#### 1b. **Multi-Account Support with Rate-Limit Tracking**

Each TCSM session can be associated with a specific Claude account for administrative and rate-limit tracking:

```bash
# Start session with primary account (default)
tcsm-start myproject

# Start session with secondary account
tcsm-start myproject --account secondary

# View which account each session uses
tcsm-list
# Displays: Project | Window | Status | Account | Rate Limit Tier | Path

tcsm-status
# Shows per-session account configuration
```

**Features:**
- Account selection via `--account <id>` parameter
- Account validation: only active accounts allowed
- Rate limit tier tracking from `~/.claude/accounts.json`
- Display account organization name and rate limit in CLI output
- **Note:** Account parameter is metadata-only; Claude CLI doesn't support account selection at launch

**Use case**: Distribute session load across multiple Claude accounts to manage rate limits when running many parallel sessions.

#### 2. **Configuration Management** (`config/`)

Portable configuration templates for projects and accounts:

```bash
# Copy templates to ~/.claude/
cp config/tcsm-projects.json.template ~/.claude/tcsm-projects.json
cp config/accounts.json.template ~/.claude/accounts.json

# Customize for your environment
vim ~/.claude/tcsm-projects.json
```

**Configuration files:**
- `tcsm-projects.json` - Project name → directory mappings
- `accounts.json` - Claude account configuration
- `.template` files - Templates with examples

Environment variable override example:
```bash
SKILLS_DEST=/custom/skills bash install.sh
```

#### 3. **Installation Script** (`install.sh`)

Automated setup for new VMs:

```bash
# Install everything in one command
bash install.sh

# Or specify tenant for multi-tenant setups
TENANT=staging bash install.sh

# This sets up:
# - Skills in ~/.claude/skills/
# - Config templates in ~/.claude/
# - Default tmux session: dev-tcsm (or $TENANT-tcsm)
```

#### 4. **Boot-Time Auto-Restoration** (`systemd/tcsm-restore.service`)

Optional systemd service that automatically restores all registered Claude sessions when the user logs in:

```bash
# Install and enable systemd service for auto-restoration
INSTALL_SYSTEMD=1 bash install.sh

# Or enable manually after install
systemctl --user enable --now tcsm-restore.service

# Monitor restoration at login
journalctl --user -u tcsm-restore.service -f
```

The service calls `tcsm-restore` directly, inheriting all TCSM features:
- **Persistent sessions** — all registered sessions restored across reboots
- **Git-aware discovery** — automatically finds real source repos
- **Workspace trust** — pre-configured to skip interactive prompts
- **Clean logs** — all activity logged to `~/.claude/tcsm.log`

No configuration needed — add sessions via `tcsm-start` and they auto-restore on next boot.

**What it replaces:** The old, broken `tmux-claude.service` that was duplicating 150+ lines of logic and silently failing due to renamed registry files. Now unified and consolidated.

### Default Session (`dev-tcsm`)

Each VM gets a default session named `<tenant>-tcsm` that runs in the repository root:

```bash
# Attach to default session
tmux attach -t dev-tcsm

# Inside, manage all Claude sessions
source ~/.claude/skills/tcsm.sh
tcsm-start myproject
tcsm-stop myproject
tcsm-restart myproject
tcsm-list
```

Session name format: `<tenant>-tcsm` (tcsm = tmux-claude-session-manager)

**Benefits:**
- Centralized workspace for managing Claude sessions
- Easy multi-VM setup: `TENANT=prod bash install.sh`
- Auto-starts on login (optional via systemd)
- Session persists across disconnects

### Multi-VM Workflow

Example across three development VMs:

**dev.myproject:**
```
Session: dev-tcsm
├─ myproject
├─ infrastructure-project
└─ synthesia
```

**staging.myproject:**
```
Session: staging-tcsm
├─ staging-myproject
└─ staging-api
```

**prod-infra:**
```
Session: prod-tcsm
├─ infrastructure-project
└─ infrastructure
```

Each VM independently manages its Claude sessions using the same skill.

### Configuration via Environment

All paths and settings support environment variable overrides:

```bash
# Custom skills directory
export SKILLS_DEST=/opt/claude/skills

# Custom config location
export CONFIG_DEST=/etc/claude

# Tenant identifier (for multi-tenant setups)
export TENANT=production

# Git-aware project discovery: search roots
# (space-separated paths where tcsm-start looks for git-controlled source folders)
export TCSM_SEARCH_ROOTS="$HOME/src $HOME/projects /custom/projects"

# Enable systemd unit for boot-time session auto-restoration (default: 0)
export INSTALL_SYSTEMD=1

bash install.sh
```

### Known Issues & Workarounds

#### Workspace Trust Dialog Reappears on Session Start

**Issue**: Claude Code has a [known bug](https://github.com/anthropics/claude-code/issues/9113) where the workspace trust dialog reappears even when `hasTrustDialogAccepted` is already set in `~/.claude.json`.

**Workaround**: `tcsm-start` includes an additional step after pre-configuring workspace trust: it explicitly calls `claude config set workspaceTrustSettings."$project_dir".hasTrustDialogAccepted true` to ensure Claude reads the trust setting before presenting the interactive confirmation dialog. This reduces (but doesn't fully eliminate) the prompt on first start.

**What to do**: If the trust prompt still appears on initial session start, answer "Yes, I trust this folder" once. Future restarts of the same project should skip the prompt.

**Note**: This is a workaround for an upstream Claude Code issue. If Claude Code fixes the underlying bug, this workaround becomes a harmless no-op.

### Documentation

- **`skills/README.md`** - Skill overview and features
- **`skills/tcsm.md`** - Comprehensive skill documentation
- **`skills/USAGE.txt`** - Quick reference card
- **`config/README.md`** - Configuration file reference
- **`install.sh`** - Installation and setup automation

### Compatibility

✅ Backward compatible with upstream  
✅ Works with tmux 3.2+  
✅ Supports macOS and Linux  
✅ Generic paths (no hardcoding)  
✅ Multi-VM ready  

### Contributing Back

Bug fixes and improvements are periodically contributed back to the upstream project:

- [craftzdog/tmux-claude-session-manager](https://github.com/craftzdog/tmux-claude-session-manager)

---

**Last Updated:** 2026-07-26  
**Repository:** https://github.com/ivomarino/tmux-claude-session-manager  
**Upstream:** https://github.com/craftzdog/tmux-claude-session-manager
