# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, and similar) working with this repository. `CLAUDE.md` points here.

## Language rule

Everything these hooks print or send to a model is en-US: `systemMessage` text, `reason` text, `additionalContext`, banners and log lines. Do not add Portuguese or any other language. Never use em dashes (U+2014). `./tests/smoke.sh` fails on accented characters and em dashes in shipped files.

## Install on a machine (do this in order)

1. Run `./install.sh --check`. If it reports a missing required tool (`bash`, `jq`, `python3`, `git`), install it, then rerun. Tell the user about missing optional tools and plugins, but do not block on them.
2. Install the third-party pieces listed in README.md under Prerequisites if absent: the `andrej-karpathy-skills` plugin, the `humanizer` skill, the `graphify` skill and CLI. If you cannot fetch one, say so and continue.
3. Run `./install.sh --dry-run` and read the output.
4. Run `./install.sh`. Add `--with-iterm` only if the user runs iTerm2, and `--with-mod` only if they want `/diff` and the editor opened on session start.
5. Run `./tests/smoke.sh`. It must print `smoke: OK`.
6. Tell the user to restart Claude Code and run `/hooks`.

If a hook script edit is denied because the harness treats it as self-modification, do not work around it. Ask the user to run the command with the `!` prefix.

## Repository map

- `scripts/`: hook scripts and helpers, copied to `~/.claude/scripts`
- `skills/`: skills written for these hooks, copied to `~/.claude/skills`
- `settings/core.json`, `iterm.json`, `mod.json`: hook registrations merged into `~/.claude/settings.json`
- `mods/git-diff-on-start/`: optional Claude Code mod
- `tests/smoke.sh`: installer and en-US check in a temporary HOME
- `docs/my_hooks.md`: long design notes, decisions and pitfalls

## Changing the hooks

- Edit the file here, then rerun `./install.sh` so `~/.claude` matches. The repo is the source of truth.
- Keep `systemMessage` for the user and `reason` or `additionalContext` for the model.
- Pass or fail decisions must come from script exit codes or state files, never from text the model writes.
- Keep safety valves (round limits) in every Stop hook so a session can never be trapped.
- Run `./tests/smoke.sh` before opening a PR.

## Git rules

- Never push to `main`. Branch as `type/short-kebab-description`.
- Commits and PR titles: `type(scope): imperative summary`, 72 characters at most, no trailing period, scope required.
- Fill every section of `.github/PULL_REQUEST_TEMPLATE.md`.
- `main` requires a pull request with the owner's approval. Do not try to bypass it.
- Never commit secrets, `.env` files or machine-specific paths.
