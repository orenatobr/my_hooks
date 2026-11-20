#!/usr/bin/env python3
"""Enforce that a /goal turn loads its required skills through the Skill tool.

goal-start-trigger.sh can only inject text, so the model may ignore it. This
gate reads the transcript and decides from the Skill tool calls actually made
in the current turn, never from what the model writes.

Usage (hook command, payload on stdin): goal_skills_gate.py <pretool|stop>

pretool  deny every tool except Skill until all REQUIRED skills were loaded
stop     block the stop until all REQUIRED skills were loaded

Safety valve: after MAX_BLOCKS blocks in one turn the gate lets go, so a skill
that cannot load never traps the session.
"""
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qjs_transcript import last_human, load, text_of  # noqa: E402

REQUIRED = (
    "andrej-karpathy-skills:karpathy-guidelines",
    "graphify",
    "humanizer",
    "attack-protection",
    "programming-best-practices",
    "git-guidelines",
)
MAX_BLOCKS = 4
STATE_DIR = Path("/tmp")


def is_goal_prompt(text: str) -> bool:
    """True when the turn's human prompt is a /goal command."""
    return "<command-name>/goal</command-name>" in text or text.lstrip().startswith("/goal")


def missing_skills(entries: list[dict[str, Any]], start: int) -> list[str]:
    """REQUIRED skills with no Skill tool call after entries[start]."""
    loaded: set[str] = set()
    for d in entries[start:]:
        content = (d.get("message") or {}).get("content")
        if d.get("type") != "assistant" or not isinstance(content, list):
            continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill":
                loaded.add(str((b.get("input") or {}).get("skill", "")))
    return [s for s in REQUIRED if s not in loaded]


def bump_blocks(session_id: str, turn: str) -> int:
    """Count one more block for this turn and return the new total."""
    path = STATE_DIR / f"goal-skills-gate-{session_id}"
    try:
        saved_turn, _, count = path.read_text().partition(":")
        n = int(count) if saved_turn == turn else 0
    except (OSError, ValueError):
        n = 0
    path.write_text(f"{turn}:{n + 1}")
    return n + 1


def decide(payload: dict[str, Any], mode: str) -> dict[str, Any] | None:
    """Return the hook JSON to emit, or None to stay silent and allow."""
    if payload.get("agent_id") or (mode == "pretool" and payload.get("tool_name") == "Skill"):
        return None
    transcript = payload.get("transcript_path") or ""
    if not transcript or not Path(transcript).is_file():
        return None
    entries = load(transcript)
    start = last_human(entries)
    if start < 0 or not is_goal_prompt(text_of((entries[start].get("message") or {}).get("content"))):
        return None
    missing = missing_skills(entries, start)
    if not missing:
        return None
    turn = str(entries[start].get("promptId") or entries[start].get("uuid"))
    if bump_blocks(str(payload.get("session_id", "")), turn) > MAX_BLOCKS:
        return {"systemMessage": f"goal-skills-gate: {MAX_BLOCKS} blocks without loading {', '.join(missing)}, letting go as a safety valve."}
    reason = (
        "goal-skills-gate: this /goal turn must first load, with the Skill tool, "
        f"the skills still missing: {', '.join(missing)}. Call Skill once for each, "
        "all in a single message, then continue. Do not write the load notice as text."
    )
    if mode == "pretool":
        return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason}}
    return {"decision": "block", "reason": reason}


def main() -> None:
    """Read the hook payload from stdin and print the decision, if any."""
    mode = sys.argv[1] if len(sys.argv) > 1 else "stop"
    try:
        out = decide(json.load(sys.stdin), mode)
    except (ValueError, OSError):
        out = None
    if out:
        sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    main()
