#!/usr/bin/env bash
# LLM-as-judge: scores the turn 0-10 with Fable 5.1 (fallback Opus 5.5).
# Only runs after quality-gate.sh passed for the same turn (exit 3 otherwise).
# Evidence modes: diff (git diff vs HEAD), goal (active /goal), response
# (last request vs last answer). Writes <state>/judge.json; exit 0 = pass, 1 = fail.
# Usage: llm-judge.sh --state DIR --turn ID --transcript PATH [--cwd DIR]
set -u
PATH="/opt/homebrew/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

THRESHOLD=7
JUDGE_TIMEOUT=60
JUDGE_MODEL=claude-fable-5-1
FALLBACK_MODEL=claude-opus-5-5
judge_name="Fable 5.1"

state="/tmp/qjs-manual"; turn="manual"; transcript=""; cwd="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --state) state="$2"; shift 2 ;;
    --turn) turn="$2"; shift 2 ;;
    --transcript) transcript="$2"; shift 2 ;;
    --cwd) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$state"
cd "$cwd" || { echo "llm-judge: cwd not found: $cwd" >&2; exit 2; }

# Order is enforced here, not by the prompt: no gate pass for this turn, no judge.
if [ "$(jq -r --arg t "$turn" 'select(.turn == $t) | .pass' "$state/gate.json" 2>/dev/null)" != "true" ]; then
  echo "llm-judge: quality-gate has not passed for turn $turn. Run /quality-gate first." >&2
  exit 3
fi

tq() { [ -f "$transcript" ] && python3 -I "$SCRIPT_DIR/qjs_transcript.py" "$1" "$transcript"; }
request="$(tq request)"

diff=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  diff="$(git diff HEAD -- . 2>/dev/null || git diff 2>/dev/null)"
  diff="$(printf '%s' "$diff" | head -c 20000)"
fi
goal_json="$(tq goal)"; [ -n "$goal_json" ] || goal_json='{}'
goal_text="$(printf '%s' "$goal_json" | jq -r '.goal // empty')"

FMT='Reply in EXACTLY this format, nothing else:
SCORE: <integer 0-10>
FEEDBACK: <short bullet list of what to fix, or '"'none'"' if the score is 10>'

if [ -n "$diff" ]; then
  mode="diff"
  prompt="You are an independent code reviewer acting as an LLM judge. Use the /code-review skill to review this diff (the working tree is the current directory) for real correctness bugs (not style/nits/opinions). Also check that the diff does what the user asked for.
The user's request was:
\"$request\"

Score it from 0 to 10 (10 = flawless and does what was asked, 0 = fundamentally broken or off-request). $FMT

--- DIFF ---
$diff"
elif [ -n "$goal_text" ]; then
  mode="goal"
  evidence="$(printf '%s' "$goal_json" | jq -r '.evidence // empty')"
  prompt="You are an independent reviewer acting as an LLM judge. The user set this goal for the session:
\"$goal_text\"

Below is an excerpt of what the assistant did/said while working on it (text responses and [action: Tool] markers, in order). Score 0 to 10 how well the goal has been satisfied so far (10 = fully and correctly achieved, 0 = not addressed at all). $FMT

--- TRANSCRIPT EXCERPT ---
$evidence"
else
  mode="response"
  response="$(tq response)"
  prompt="You are an independent reviewer acting as an LLM judge. Below are the user's last request and the assistant's answer. Score 0 to 10 whether the answer follows the request (correct, complete, on topic) and whether the tone fits the user (10 = excellent, 0 = off-request or wrong). Do not reward length. $FMT

--- USER REQUEST ---
$request

--- ASSISTANT ANSWER (text and [action: Tool] markers) ---
${response:-(no assistant text captured)}"
fi

TO="$(command -v timeout || command -v gtimeout || true)"
judge() { printf '%s' "$prompt" | FABLE_JUDGE_ACTIVE=1 ${TO:+"$TO" "$JUDGE_TIMEOUT"} claude -p --model "$JUDGE_MODEL" 2>/dev/null; }
# Tolerates "SCORE: 8", "**Score:** 8/10", "score - 8".
parse_score() { printf '%s' "$1" | grep -m1 -oiE 'score\W{0,6}[0-9]+' | grep -oE '[0-9]+$'; }
# Unavailable = empty reply (timeout/crash), or limit/outage text with no SCORE.
judge_unavailable() {
  [ -z "$1" ] && return 0
  ! printf '%s' "$1" | grep -qiE 'score\W{0,6}[0-9]' && printf '%s' "$1" | grep -qiE "reached your .*limit|usage limit|rate limit|overloaded|credits|try again later"
}

write_result() {  # score(or "") pass judge feedback
  jq -nc --arg turn "$turn" --arg mode "$mode" --arg score "$1" --argjson pass "$2" --arg judge "$3" --arg fb "$4" \
    '{turn:$turn, mode:$mode, score:(if $score == "" then null else ($score|tonumber) end), pass:$pass, judge:$judge, feedback:$fb}' \
    > "$state/judge.json.tmp" && mv "$state/judge.json.tmp" "$state/judge.json"
}

verdict="$(judge)"
if judge_unavailable "$verdict"; then
  JUDGE_MODEL="$FALLBACK_MODEL"; judge_name="Opus 5.5"
  verdict="$(judge)"
  if judge_unavailable "$verdict"; then
    write_result "" true "unavailable" "Fable and fallback Opus 5.5 both unavailable (limit/outage/timeout): failing open."
    echo "JUDGE: unavailable (Fable and Opus 5.5), failing open"; exit 0
  fi
fi

score="$(parse_score "$verdict")"
if [ -z "$score" ]; then verdict="$(judge)"; score="$(parse_score "$verdict")"; fi
if [ -z "$score" ]; then
  printf '%s' "$verdict" > "$state/judge-raw.txt"
  write_result "" false "$judge_name" "Judge reply unparsable twice (raw in $state/judge-raw.txt). Run /llm-as-judge again."
  echo "JUDGE: $judge_name reply unparsable twice, raw in $state/judge-raw.txt"; exit 1
fi

feedback="$(printf '%s' "$verdict" | sed -n '/^FEEDBACK:/,$p' | sed '1s/^FEEDBACK:[[:space:]]*//' | sed '/^[[:space:]]*$/d')"
if [ "$score" -ge "$THRESHOLD" ]; then pass=true; else pass=false; fi
write_result "$score" "$pass" "$judge_name" "$feedback"
echo "JUDGE[$mode]: $judge_name scored $score/10 ($([ "$pass" = true ] && echo PASS || echo FAIL), minimum $THRESHOLD)"
[ -n "$feedback" ] && printf '%s\n' "$feedback"
[ "$pass" = true ]
