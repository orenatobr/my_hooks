#!/bin/bash
# karpathy-guidelines, SessionStart hook.
# Injects the andrej-karpathy-skills CLAUDE.md content as context. It does NOT
# tell the model to call the Skill tool: the six-skill load happens only on
# /goal, via goal-start-trigger.sh (which calls this script with stdin at EOF
# => SessionStart, KARPATHY_NO_INSTR=1). Normal prompts (UserPromptSubmit) get
# nothing from here.
payload="$(cat)"
event="$(printf '%s' "$payload" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null)"
[ -n "$event" ] || event="SessionStart"
[ "$event" = "UserPromptSubmit" ] && exit 0
f=$(ls -d "$HOME"/.claude/plugins/cache/karpathy-skills/andrej-karpathy-skills/*/CLAUDE.md 2>/dev/null | sort -V | tail -1)
[ -f "$f" ] || exit 0
jq -Rs --arg e "$event" '{hookSpecificOutput:{hookEventName:$e,additionalContext:.}}' < "$f"
