#!/bin/bash
# SessionStart hook: in iTerm2, set the Session Name to the folder name and the
# Session Title to Session Name only (via the iTerm2 Python API, live).
# No-op outside iTerm2. Never blocks the session. Logs each run to
# ~/.claude/logs/iterm-session-name.log (event source, name, title read back).

[ -n "$ITERM_SESSION_ID" ] || exit 0

payload=$(cat)
dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
source_=$(printf '%s' "$payload" | jq -r '.source // "unknown"' 2>/dev/null)
uuid="${ITERM_SESSION_ID#*:}"

# Nested claude (judge `claude -p`, claude-mem, headless helpers) inherits the tab's
# ITERM_SESSION_ID and fires its own SessionStart with its own folder. Only the claude
# that owns the tab (no other claude among its ancestors) may name it.
n=0; p=$$
while [ "${p:-0}" -gt 1 ]; do
  [ "$(basename -- "$(ps -o comm= -p "$p" 2>/dev/null)")" = claude ] && n=$((n + 1))
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
if [ "$n" -gt 1 ]; then
  mkdir -p "$HOME/.claude/logs"
  printf '%s source=%s uuid=%s skipped=nested-claude(%s)\n' "$(date '+%F %T')" "$source_" "$uuid" "$n" >> "$HOME/.claude/logs/iterm-session-name.log"
  exit 0
fi
# Name from the folder the session was opened in; the payload cwd follows Claude's
# `cd` and would rename the tab. Order: first cwd in the transcript (the original
# folder, also on --resume, where CLAUDE_PROJECT_DIR is the old last cwd), then
# CLAUDE_PROJECT_DIR, then cwd. On /clear the name stored for this tab wins.
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
first=""
[ -f "$transcript" ] && first=$(jq -rn 'first(inputs | select(.cwd) | .cwd)' "$transcript" 2>/dev/null)
name=$(basename "${first:-${CLAUDE_PROJECT_DIR:-${dir:-$PWD}}}")
store="$HOME/.claude/state/iterm-names"
if [ "$source_" = clear ] && [ -s "$store/$uuid" ]; then name=$(cat "$store/$uuid"); fi

# Subagent worktrees (<project>/.claude/worktrees/agent-*) inherit ITERM_SESSION_ID
# from the user's tab; renaming here would replace the project name with agent-<id>.
case "${dir:-$PWD}" in
  */.claude/worktrees/*)
    mkdir -p "$HOME/.claude/logs"
    printf '%s source=%s name=%s skipped=worktree\n' "$(date '+%F %T')" "$source_" "$name" >> "$HOME/.claude/logs/iterm-session-name.log"
    exit 0 ;;
esac

osascript - "$uuid" "$name" <<'APPLESCRIPT' >/dev/null 2>&1
on run {uuid, nm}
  tell application "iTerm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if unique id of s is uuid then set name of s to nm
        end repeat
      end repeat
    end repeat
  end tell
end run
APPLESCRIPT

mkdir -p "$store" && printf '%s' "$name" > "$store/$uuid"

# Title: needs the iterm2 package in a venv and the API server enabled; skip silently otherwise.
PY="$HOME/.claude/venvs/iterm2/bin/python"
title=skipped
if [ -x "$PY" ] && command -v timeout >/dev/null; then
  title=$(timeout 8 "$PY" "$HOME/.claude/scripts/iterm-title-name.py" "$uuid" 2>&1 | tail -1)
  [ -n "$title" ] || title=ok
fi

mkdir -p "$HOME/.claude/logs"
printf '%s source=%s uuid=%s name=%s proj=%s %s\n' "$(date '+%F %T')" "$source_" "$uuid" "$name" "${CLAUDE_PROJECT_DIR:-unset}" "$title" >> "$HOME/.claude/logs/iterm-session-name.log"
exit 0
