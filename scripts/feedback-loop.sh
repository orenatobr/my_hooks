#!/usr/bin/env bash
# PostToolUse feedback loop: after Edit/Write/MultiEdit, run the touched
# project's own lint/typecheck/test commands and hand failures back to
# Claude via stderr + exit 2 so it can self-correct next turn.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" && source ./feedback-loop-lib.sh

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -n "$file_path" ] && [ -f "$file_path" ] || exit 0

case "$file_path" in
  */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/.venv/*) exit 0 ;;
esac

find_project_root "$(dirname "$file_path")" || exit 0
cd "$project_root" || exit 0
run_checks

if [ -n "$failures" ]; then
  printf 'feedback-loop: checks failed in %s\n%b' "$project_root" "$failures" >&2
  exit 2
fi

exit 0
