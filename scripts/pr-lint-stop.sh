#!/usr/bin/env bash
# Stop hook (safety net behind pr-gate-pretool.py): lint every PR this session
# created/edited with pr_lint.py. Closed/merged PRs are skipped, so a replaced
# PR no longer loops. Pass/fail comes from the linter exit code, not from text
# the model writes. Safety valve: MAX_ROUNDS blocks, then the stop is allowed.
set -u

[ "${FABLE_JUDGE_ACTIVE:-0}" = "1" ] && exit 0

MAX_ROUNDS=3
here="$(cd "$(dirname "$0")" && pwd)"

payload="$(cat)"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
[ -f "$transcript" ] || exit 0
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[ -n "$session_id" ] || exit 0

urls="$(python3 - "$transcript" <<'PYEOF'
import json, re, sys

CMD = re.compile(r'(^|[;&|(]\s*|\n\s*)gh pr (create|edit)\b')
MCP = re.compile(r'create_pull_request|update_pull_request')
URL = re.compile(r'https://github\.com/[\w.-]+/[\w.-]+/pull/\d+')
pr_calls, urls = set(), []
for line in open(sys.argv[1]):
    try:
        d = json.loads(line)
    except Exception:
        continue
    content = (d.get('message') or {}).get('content')
    if not isinstance(content, list):
        continue
    for b in content:
        if not isinstance(b, dict):
            continue
        if d.get('type') == 'assistant' and b.get('type') == 'tool_use':
            if CMD.search((b.get('input') or {}).get('command', '') or '') or MCP.search(b.get('name', '')):
                pr_calls.add(b.get('id'))
        elif d.get('type') == 'user' and b.get('type') == 'tool_result' and b.get('tool_use_id') in pr_calls:
            for u in URL.findall(json.dumps(b.get('content', ''))):
                if u not in urls:
                    urls.append(u)
print('\n'.join(urls))
PYEOF
)"
[ -n "$urls" ] || exit 0

errors=""
while read -r url; do
  [ -n "$url" ] || continue
  out="$(python3 "$here/pr_lint.py" url "$url" 2>&1)" || errors="$errors
$out"
done <<< "$urls"
state_file="/tmp/pr-lint-round-${session_id}"
if [ -z "$errors" ]; then rm -f "$state_file"; exit 0; fi

round="$(cat "$state_file" 2>/dev/null || echo 0)"
if [ "$round" -ge "$MAX_ROUNDS" ]; then
  rm -f "$state_file"
  jq -n --arg m "pr-lint: $MAX_ROUNDS rounds without a clean PR, allowing stop as a safety valve:$errors" '{systemMessage: $m}'
  exit 0
fi
printf '%s' $((round + 1)) > "$state_file"

jq -n --arg r "pr-lint: open PR(s) from this session break /git-guidelines (round $((round + 1))/$MAX_ROUNDS):$errors

Fix with 'gh pr edit' (title/body from the template). A bad commit already pushed cannot be fixed without force push: open a replacement PR from a new branch with compliant commits and close the old one. Do not claim compliance in text, the linter decides." \
  --arg m "
    🔎 pr-lint: PR breaks /git-guidelines (iteration $((round + 1))/$MAX_ROUNDS)$errors" \
  '{decision: "block", reason: $r, systemMessage: $m}'
