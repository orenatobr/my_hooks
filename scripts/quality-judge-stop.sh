#!/usr/bin/env bash
# Stop hook: on EVERY stop, make the session run /quality-gate (deterministic
# checks) and then /llm-as-judge (Fable 5.1, fallback Opus 5.5), and only
# release the stop once both left a passing result for this turn.
# A hook cannot load a skill, so it blocks and instructs the model to call
# the Skill tool. Pass/fail never comes from what the model writes: it comes
# from <state>/gate.json and <state>/judge.json, produced by quality-gate.sh
# and llm-judge.sh and stamped with the turn id (promptId of the current turn).
# Flow per turn:
#   no gate.json            -> block: run /quality-gate, then /llm-as-judge
#   gate fail               -> block: fix and rerun (counts a failed round)
#   gate ok, no judge.json  -> block: run /llm-as-judge
#   judge fail              -> block: iterate with the session model, rerun both
#   both ok, code task      -> block once: ask commit / branch / PR via /git-guidelines
#   both ok                 -> block once: persist findings in the Obsidian vault
#   done                    -> release
# Safety valves: 3 failed rounds or 8 blocks in one turn release with a warning.
set -u

# The judge's own `claude -p` session runs through this global hook on exit.
[ "${FABLE_JUDGE_ACTIVE:-0}" = "1" ] && exit 0

PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_FAIL_ROUNDS=3
MAX_BLOCKS=8

# "systemMessage" is shown to the user on every path; "reason" goes to the model.
sysmsg() { jq -n --arg m "$1" '{systemMessage: $m}'; exit 0; }

payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0
transcript_path="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || session_id="$(printf '%s' "$transcript_path" | shasum | cut -d' ' -f1)"

state="/tmp/qjs-${session_id}"
mkdir -p "$state"

tq() { python3 -I "$SCRIPT_DIR/qjs_transcript.py" "$1" "$transcript_path" 2>/dev/null; }
turn="$(tq turn)"
[ -n "$turn" ] || sysmsg "quality-judge: no human prompt found in the transcript, nothing to verify: stop allowed."

# New turn: reset counters and flags. gate.json/judge.json carry their own turn id, so stale ones
# are ignored and a gate the user ran before the first Stop still counts. persisted_session survives.
if [ "$(cat "$state/turn" 2>/dev/null)" != "$turn" ]; then
  rm -f "$state"/judge-raw.txt "$state"/git_asked "$state"/persisted_turn "$state"/fail_rounds "$state"/blocks
  printf '%s' "$turn" > "$state/turn"
fi

counter() { local v; v="$(cat "$state/$1" 2>/dev/null)"; case "$v" in ''|*[!0-9]*) v=0 ;; esac; printf '%s' "$v"; }
bump() { printf '%s' "$(( $(counter "$1") + 1 ))" > "$state/$1"; }

blocks="$(counter blocks)"; fail_rounds="$(counter fail_rounds)"
if [ "$blocks" -ge "$MAX_BLOCKS" ] || [ "$fail_rounds" -ge "$MAX_FAIL_ROUNDS" ]; then
  sysmsg "
    ⚠️ quality-judge: round limit reached this turn ($fail_rounds failures, $blocks blocks): stop allowed as a safety valve.
        Review manually what is still pending."
fi

BANNER="
    Running quality gate with /quality-gate
    Running llm-as-judge with /llm-as-judge # Using Fable 5.1 with fallback to Opus 5.5."

block() {  # reason, user message
  bump blocks
  jq -n --arg r "$1" --arg m "$2" '{decision: "block", reason: ($m + "\n\n" + $r), systemMessage: $m}'
  exit 0
}

q() { printf '%q' "$1"; }
GATE_CMD="$SCRIPT_DIR/quality-gate.sh --state $(q "$state") --turn $turn --cwd $(q "$cwd")"
JUDGE_CMD="$SCRIPT_DIR/llm-judge.sh --state $(q "$state") --turn $turn --transcript $(q "$transcript_path") --cwd $(q "$cwd")"

# Same vault folder rule as goal-start-trigger.sh: climb from where the session
# started to the first folder with a MEMORY.md; ~ is "renato".
origin_cwd="$(head -50 "$transcript_path" 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null | head -1)"
[ -d "$origin_cwd" ] || origin_cwd="$cwd"
vault_folder() {
  local folder d
  folder="$(basename "$origin_cwd")"
  d="$origin_cwd"
  while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
    if [ -f "$HOME/Documents/Obsidian Vault/$(basename "$d")/MEMORY.md" ]; then folder="$(basename "$d")"; break; fi
    d="$(dirname "$d")"
  done
  [ "$origin_cwd" = "$HOME" ] && folder="renato"
  printf '%s' "$folder"
}

result() { jq -r --arg t "$turn" "select(.turn == \$t) | $2" "$state/$1" 2>/dev/null; }
gate_pass="$(result gate.json '.pass')"
judge_pass="$(result judge.json '.pass')"

# 1. Nothing ran yet this turn.
if [ -z "$gate_pass" ]; then
  block "quality-judge: run both skills now, in this order. This applies to every Stop.
1. Call the Skill tool with \"quality-gate\" and run (Bash, timeout 300000): $GATE_CMD
   If it fails, fix the root cause (do not edit a test to make it pass, do not silence a rule) and rerun until it passes.
2. Only then call the Skill tool with \"llm-as-judge\" and run (Bash, timeout 300000): $JUDGE_CMD
3. Stop again. The hook checks this turn's gate.json and judge.json; text you write saying it passed does not count." \
    "$BANNER"
fi

# 2. Gate failed.
if [ "$gate_pass" = "false" ]; then
  bump fail_rounds
  failures="$(jq -r '.checks[] | select(.status == "fail") | "- " + .name + ": " + .detail' "$state/gate.json" 2>/dev/null | head -c 3000)"
  block "quality-judge: the quality gate failed. Fix the root cause and rerun: $GATE_CMD
$failures" \
    "
    ❌ /quality-gate failed (round $(counter fail_rounds)/$MAX_FAIL_ROUNDS), iterating again:
$(printf '%s' "$failures" | sed 's/^/        /')"
fi

# 3. Gate passed, judge not run yet.
if [ -z "$judge_pass" ]; then
  block "quality-judge: the gate passed. Now call the Skill tool with \"llm-as-judge\" and run (Bash, timeout 300000): $JUDGE_CMD" \
    "$BANNER"
fi

# 4. Judge failed: iterate with the session model, then both must run again.
if [ "$judge_pass" = "false" ]; then
  bump fail_rounds
  verdict="$(jq -r '"score " + ((.score // "n/a")|tostring) + "/10 (" + .judge + "):\n" + .feedback' "$state/judge.json" 2>/dev/null)"
  model="$(tail -n 200 "$transcript_path" 2>/dev/null | jq -r 'select(.type=="assistant") | .message.model // empty' 2>/dev/null | grep -v '^<' | tail -1)"
  [ -n "$model" ] || model="session model"
  # claude-sonnet-5-5[1m] -> Sonnet 5.5 [1M]
  model="$(printf '%s' "$model" | sed -E 's/^claude-//;s/\[1m\]/ [1M]/;s/^([a-z]+)-([0-9]+)-([0-9]+)/\1 \2.\3/' | awk '{ $1=toupper(substr($1,1,1)) substr($1,2); print }')"
  rm -f "$state/gate.json" "$state/judge.json"
  block "quality-judge: the judge failed it ($verdict)
Fix the gaps with the session model and rerun, in this order: $GATE_CMD  then  $JUDGE_CMD" \
    "
    ❌ /llm-as-judge failed:
$(printf '%s' "$verdict" | sed 's/^/        /')
        # Loop of up to $MAX_FAIL_ROUNDS iterations with $model (iteration $(counter fail_rounds)/$MAX_FAIL_ROUNDS)"
fi

# 5. Both passed. Code task in a git repo: ask commit / branch / PR once.
edits="$(tq edits)"; edits="${edits:-0}"
code_task=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  { [ -n "$(git status --porcelain 2>/dev/null)" ] || [ "$edits" -gt 0 ]; } && code_task=1
fi
if [ "$code_task" = 1 ] && [ ! -f "$state/git_asked" ]; then
  touch "$state/git_asked"
  block "quality-judge: the gate and the judge approved a code task. Before stopping, ask the user the 3 questions in ONE AskUserQuestion call: (1) Make a commit? (2) Create a branch? (3) Prepare a PR?
If the user accepts any of them, call the Skill tool with \"git-guidelines\" and follow it strictly (branch, commit, PR title and description; check pull_request_template.md first). Never commit directly to the default branch, no Claude attribution, no em dashes, no force push, do not touch branches that are not yours. Merge and deploy still require confirmation.
If the user declines everything, stop." \
    "
    ✅ Gate and judge approved (code changed)
        Asking the user: commit? branch? PR? (following /git-guidelines)"
fi

# 6. Persist findings in the vault once: per turn when something was checked,
# per session on empty turns (so plain Q&A does not ask for a note every time).
all_na="$(jq -r 'all(.checks[]; .status == "na")' "$state/gate.json" 2>/dev/null)"
judge_mode="$(jq -r '.mode // empty' "$state/judge.json" 2>/dev/null)"
if [ "$all_na" = "true" ] && [ "$judge_mode" = "response" ] && [ "$code_task" = 0 ]; then
  flag="$state/persisted_session"
else
  flag="$state/persisted_turn"
fi
if [ ! -f "$flag" ]; then
  touch "$flag"
  folder="$(vault_folder)"
  block "quality-judge: the gate and the judge approved. Before finishing, persist this turn's relevant findings in the Obsidian vault (\"$HOME/Documents/Obsidian Vault/$folder\"), per your ~/.claude/CLAUDE.md (standard name/description/metadata.type frontmatter, update an existing note instead of duplicating, and the MEMORY.md line of that folder; test that the directory accepts writes before claiming you saved; skip if nothing is worth keeping). Then stop again." \
    "
    ✅ Gate and judge approved
        Persisting findings in the Obsidian vault: $folder"
fi

# 7. Done.
summary="$(jq -r '[.checks[] | .name + ": " + .status] | join(" | ")' "$state/gate.json" 2>/dev/null)"
judge_line="$(jq -r '(.judge) + " " + ((.score // "n/a")|tostring) + "/10 (" + (.mode) + ")"' "$state/judge.json" 2>/dev/null)"
sysmsg "
    ✅ quality-gate: $summary
    ✅ llm-as-judge: $judge_line
        Findings already persisted, stop allowed."
