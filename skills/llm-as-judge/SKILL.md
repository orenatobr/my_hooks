---
name: llm-as-judge
description: Use after /quality-gate passed, when finishing a turn or when a Stop hook asks for it. An independent model (Fable 5.1, fallback Opus 5.5) scores 0-10 what code cannot check: does the answer follow the request, is the tone right, does the code do what the PR says. Trigger on /llm-as-judge, "llm as judge", "judge", "score the answer".
---

# /llm-as-judge

Covers what cannot be coded: "does the answer follow the request?", "is the tone right?", "does the code do what the PR says?". It runs only after `/quality-gate` passed for the same turn; the script refuses to run otherwise (exit 3). Never use em dashes.

## Run

Use the exact command the Stop hook gave you (it carries `--state`, `--turn`, `--transcript` and `--cwd`). Use a Bash timeout of 300000 ms.

```bash
~/.claude/scripts/llm-judge.sh --state DIR --turn ID --transcript PATH
```

The judge model is Fable 5.1 with a fallback to Opus 5.5 when Fable is unavailable. If both are unavailable the script fails open and says so. Threshold: 7 out of 10.

## Evidence mode (automatic)

- **diff:** the git diff vs HEAD, reviewed with `/code-review` plus "does it do what the user asked?".
- **goal:** the active `/goal` condition against the work done since it was set.
- **response:** the last request against the last answer (follows the request, tone fits).

## If the score is below 7

Iterate with the session's own model (the default, Sonnet 1M). Do not switch models. Fix every point in the feedback, then run `/quality-gate` again and `/llm-as-judge` again. Do not argue with the judge in text; change the work.

If the reply was unparsable, just run the command again.

## If the score is 7 or higher

- **Code task** (a git repo with changes): ask the user three questions in one `AskUserQuestion` call: make a commit? create a branch? prepare a PR? For anything the user accepts, `/git-guidelines` is mandatory (branch name, Conventional Commits with scope, PR title and template, EN-US). Never commit to the default branch, no Claude attribution, no force push. Merge and deploy still ask for confirmation.
- **Not a code task:** go on without questions.

Finally, persist the relevant findings in the Obsidian vault folder of the working directory (existing note updated instead of duplicated, plus the `MEMORY.md` line; skip if nothing is worth keeping, and test that the directory accepts writes before claiming it did).

## Report

State the judge, the score and whether it passed, as printed by the script, for example `Fable 5.1 8/10 (response) PASS`. Say pass only when the command printed PASS (exit 0).
