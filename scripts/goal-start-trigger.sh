#!/usr/bin/env bash
# UserPromptSubmit hook: whenever the user runs /goal, re-fire the
# always-on SessionStart hooks (karpathy guidelines, graphify autobuild)
# and read the Obsidian vault's MEMORY.md for this folder, so a new goal
# gets the same context-grounding a fresh session gets.
# There's no native "goal created" hook event, so this detects it from
# the raw prompt text instead.
set -u

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"

case "$prompt" in
  /goal) : ;;
  /goal[[:space:]]*) : ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty')"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

context=""
lines=""
add_line() { lines="${lines}
    $1"; }
for hook in karpathy-guidelines-hook.sh graphify-autobuild-hook.sh; do
  case "$hook" in
    karpathy-*) label="/andrej-karpathy-skills:karpathy-guidelines"; verb="Avoiding over engineering with" ;;
    graphify-*) label="/graphify"; verb="Reading local files with" ;;
  esac
  out="$(cd "$cwd" && KARPATHY_NO_INSTR=1 "$HOME/.claude/scripts/$hook" 2>/dev/null)"
  piece="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  if [ -z "$piece" ] && [ "$hook" = graphify-autobuild-hook.sh ]; then
    piece="graphify: no git repo or graphify-out in $cwd. If this goal involves code, use the /graphify skill (e.g. /graphify . to index, /graphify query \"...\") before grep/find."
  fi
  [ -n "$piece" ] || { add_line "Skipped $label (no context to load here)"; continue; }
  if [ -n "$context" ]; then
    context="$context

$piece"
  else
    context="$piece"
  fi
  add_line "$verb $label"
done

append_ctx() { if [ -n "$context" ]; then context="$context

$1"; else context="$1"; fi; }

append_ctx "humanizer: when writing prose (replies, docs, notes, emails, commit/PR messages), apply the /humanizer skill (Skill tool) to remove AI writing patterns. Never use em dashes."
add_line "Writing text with /humanizer"

append_ctx "attack-protection: when writing or reviewing code, apply the /attack-protection skill (Skill tool) against XSS, exposed API routes, exposed API keys, open database, SQL injection, missing rate limits, prompt injection and hallucinated packages."
add_line "Avoiding attacks with /attack-protection"

append_ctx "programming-best-practices: when writing or reviewing code, apply the /programming-best-practices skill (Skill tool): TDD, SOLID without speculative abstractions, complete static typing, Google Style docstrings and linting."
append_ctx "git-guidelines: when naming a branch or writing a commit, PR title or PR description, apply the /git-guidelines skill (Skill tool): Conventional Commits, EN-US, no em dashes."
add_line "Following /programming-best-practices and /git-guidelines"

folder="$(basename "$cwd")"
d="$cwd"
while [ "$d" != "$HOME" ] && [ "$d" != "/" ]; do
  if [ -f "$HOME/Documents/Obsidian Vault/$(basename "$d")/MEMORY.md" ]; then folder="$(basename "$d")"; break; fi
  d="$(dirname "$d")"
done
[ "$cwd" = "$HOME" ] && folder="renato"
vault_memory="$HOME/Documents/Obsidian Vault/$folder/MEMORY.md"
if [ -r "$vault_memory" ]; then
  vault_content="$(head -c 8000 "$vault_memory" 2>/dev/null)"
  if [ -n "$vault_content" ]; then
    piece="Obsidian vault memory index for \"$folder\" (read per ~/.claude/CLAUDE.md: check before assuming context):

$vault_content"
    if [ -n "$context" ]; then
      context="$context

$piece"
    else
      context="$piece"
    fi
    notes="$(printf '%s' "$vault_content" | grep -o '\](' | wc -l | tr -d ' ')"
    add_line "Reading Obsidian vault: $folder/MEMORY.md ($notes linked notes in the index)"
  fi
else
  add_line "Obsidian vault: no $folder/MEMORY.md, nothing to read"
fi

instr='REQUIRED: before any other action, call the Skill tool once for each of: andrej-karpathy-skills:karpathy-guidelines, graphify, humanizer, attack-protection, programming-best-practices, git-guidelines. The user checks the native notice "Skill(...) Successfully loaded skill". Do not write that notice as text. goal_skills_gate.py denies every other tool and blocks the stop until all six were loaded, so call them first, in one message.'
context="$instr

$context"

if [ -z "$context" ]; then
  jq -n --arg l "$lines" '{systemMessage: $l}'
  exit 0
fi

msg="${lines}"
jq -n --arg m "$context" --arg sysmsg "$msg" \
  '{systemMessage: $sysmsg, hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}'
