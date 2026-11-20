#!/bin/bash
# graphify-autobuild: always-on SessionStart hook.
# In a git repo without graphify-out/graph.json, kicks off a no-API-key
# code-only index in the background (non-blocking) and tells the model
# indexing is underway.
# If already indexed, nudges the model to query the graph before grep/find.

command -v graphify >/dev/null 2>&1 || exit 0

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
graph="$root/graphify-out/graph.json"

if [ -f "$graph" ]; then
  msg="graphify: this repo is indexed ($graph). Use the graphify skill (/graphify query \"...\") before grep/find to locate or understand code."
else
  log="$root/.graphify-autobuild.log"
  nohup graphify "$root" --code-only >"$log" 2>&1 &
  disown
  msg="graphify: no graphify-out/ found for this repo. Auto-indexing started in code-only mode (no LLM key required; log: $log). It may not be ready yet this turn, so check for graphify-out/graph.json before relying on it, and fall back to grep/find until it appears."
fi

jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
