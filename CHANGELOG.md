# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not publish versioned releases yet, so entries live under
`Unreleased` until the first tag.

## [Unreleased]

### Added

- en-US Claude Code hooks (Stop, goal start trigger, quality gate, LLM judge,
  PR lint) in `scripts/`.
- Skills written for these hooks in `skills/`.
- `install.sh` with `--check`, `--dry-run`, `--with-iterm` and `--with-mod`.
- Hook registrations in `settings/core.json`, `iterm.json` and `mod.json`.
- Optional `git-diff-on-start` Claude Code mod in `mods/`.
- `tests/smoke.sh`, which checks the installer and the en-US rule in a
  temporary HOME.
- `AGENTS.md`, `CLAUDE.md` and `docs/my_hooks.md` with install steps and
  design notes.
- `CHANGELOG.md`.
