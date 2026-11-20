# my_hooks

Claude Code hooks for a disciplined AI coding workflow. Every message a hook shows to the user or sends to the model is en-US.

What you get:

| Event | Hook | What it does |
|---|---|---|
| UserPromptSubmit | `goal-start-trigger.sh` | On `/goal`, loads six skills, the Karpathy guidelines, graphify context and your Obsidian `MEMORY.md` |
| SessionStart | `karpathy-guidelines-hook.sh` | Injects the Karpathy coding guidelines as context |
| SessionStart | `graphify-autobuild-hook.sh` | Indexes a git repo in the background and points the model at `/graphify` |
| PreToolUse | `pr-gate-pretool.py` | Blocks commits, pushes and PRs that break `/git-guidelines` |
| PostToolUse | `feedback-loop.sh` | Runs the project's lint, type and test commands after every edit |
| Stop | `pr-lint-stop.sh` | Lints every PR the session opened |
| Stop | `quality-judge-stop.sh` | Makes the model run `/quality-gate`, then `/llm-as-judge`, before it can stop |
| SessionStart (optional) | `iterm-session-name.sh` | Names the iTerm2 tab after the project folder |
| SessionStart (optional mod) | `git-diff-on-start` | Opens `/diff` and the editor when a session starts in a git repo |

## Prerequisites

Install these first. `./install.sh --check` reports what is missing.

Required tools:

- `bash`, `jq`, `python3` (3.9 or newer), `git`
- `gh` (GitHub CLI), logged in with `gh auth login`
- `claude` (Claude Code CLI) on your `PATH`. The judge calls `claude -p` with `claude-fable-5-1` and falls back to `claude-opus-5-5`. If both are unavailable, the judge fails open.
- `timeout` from coreutils: `brew install coreutils` on macOS (not needed on Linux)

Optional tools (the hooks skip what is missing):

- `graphify` CLI, for repo indexing
- `pre-commit`, `pytest`, `ruff`, `mypy`, `eslint`: whatever your projects use
- `gitleaks`, for the secrets check (a regex fallback runs without it)

Claude Code plugin and skills that are NOT in this repo (install them yourself):

| Name | Used by | Source |
|---|---|---|
| `andrej-karpathy-skills` plugin | `karpathy-guidelines-hook.sh`, `/goal` | marketplace `multica-ai/andrej-karpathy-skills` |
| `humanizer` skill | `/goal` skill loading | upstream humanizer skill, copy to `~/.claude/skills/humanizer` |
| `graphify` skill and CLI | `graphify-autobuild-hook.sh`, `/goal` | upstream graphify, copy the skill to `~/.claude/skills/graphify` |

Install the Karpathy plugin inside Claude Code:

```
/plugin marketplace add multica-ai/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

Skills shipped here (the installer copies them): `git-guidelines`, `attack-protection`, `programming-best-practices`, `tests-guidelines`, `quality-gate`, `llm-as-judge`.

Optional extras:

- Obsidian vault at `~/Documents/Obsidian Vault/<folder>/MEMORY.md`. The hooks read it on `/goal` and ask the model to save notes there. Without it they print "no MEMORY.md" and carry on. `<folder>` is the working directory name, and `renato` when the directory is `~` (edit `goal-start-trigger.sh` and `quality-judge-stop.sh` to change that name).
- iTerm2 with its Python API enabled and `python3` venv at `~/.claude/venvs/iterm2` (only for `--with-iterm`).

## Install

```bash
git clone https://github.com/orenatobr/my_hooks.git
cd my_hooks
./install.sh --check          # verify prerequisites
./install.sh --dry-run        # preview, changes nothing
./install.sh                  # core hooks
./install.sh --with-iterm --with-mod   # also the iTerm2 and git-diff-on-start extras
```

The installer copies scripts to `~/.claude/scripts`, skills to `~/.claude/skills`, and merges the hook registrations from `settings/*.json` into `~/.claude/settings.json`. It keeps every other key, never adds a hook twice, and saves a backup of anything it replaces under `~/.claude/backups/my_hooks-<timestamp>/`. Set `CLAUDE_DIR` to install somewhere else.

Restart Claude Code, then run `/hooks` to confirm the entries. Run `./tests/smoke.sh` any time to check the installer and the en-US output in a throwaway home directory.

## How it behaves

- On every Stop the model must run `/quality-gate` (schema, lint, types, tests, pre-commit, secrets) and then `/llm-as-judge` (score 0 to 10, passes at 7). Results come from files the scripts write, not from what the model says. Safety valves release the stop after 3 failed rounds or 8 blocks in one turn.
- On `/goal` the user sees a short list such as:

```
UserPromptSubmit says:
    Avoiding over engineering with /andrej-karpathy-skills:karpathy-guidelines
    Reading local files with /graphify
    Writing text with /humanizer
    Avoiding attacks with /attack-protection
    Following /programming-best-practices and /git-guidelines
    Reading Obsidian vault: renato/MEMORY.md (5 linked notes in the index)
```

- Commits must look like `type(scope): imperative summary` (72 characters at most, scope required). PR bodies must fill every section of the template.

## Uninstall

Remove the `my_hooks` entries from `~/.claude/settings.json` (restore the `settings.json` backup the installer made) and delete the copied files from `~/.claude/scripts` and `~/.claude/skills`.

## For AI agents

Read [AGENTS.md](AGENTS.md). It has the exact install steps, the verification commands and the rules for changing these hooks.

The long design notes, decisions and pitfalls are in [docs/my_hooks.md](docs/my_hooks.md).

## Contributing

`main` is protected: merge by pull request only, with the owner's approval (the owner can bypass). Follow the PR template and `/git-guidelines`.

## License

MIT, see [LICENSE](LICENSE).
