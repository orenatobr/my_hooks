#!/usr/bin/env python3
"""Transcript queries shared by quality-judge-stop.sh and llm-judge.sh.

Usage: qjs_transcript.py <turn|request|response|edits|goal> <transcript.jsonl>

turn      promptId of the current turn (uuid of its first entry on old transcripts)
request   text of that prompt
response  assistant text and [action: Tool] markers since that prompt
edits     number of Edit/Write/NotebookEdit tool calls since that prompt
goal      JSON {goal, evidence} when a /goal Stop condition is active, else {}

Hook feedback, skill bodies, "already loaded" reminders and tool results are
also stored as "user" entries; they share the turn's promptId, so none of
them can start a new turn and a Stop block never resets the state.
"""
import json
import sys
from typing import Any

CAP = 20000
GOAL_PREFIX = 'A session-scoped Stop hook is now active with condition: "'
# Fallback when a transcript has no origin field at all (older versions).
INJECTED = ("Base directory for this skill", "Stop hook feedback", "<system-reminder", "<local-command", "<command-")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


def load(path: str) -> list[dict[str, Any]]:
    """Read a JSONL transcript, skipping unparsable lines."""
    entries: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue
    return entries


def text_of(content: Any) -> str:
    """Join the text blocks of a message content (str or list of blocks)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def last_human(entries: list[dict[str, Any]]) -> int:
    """Index of the first entry of the current turn, or -1.

    Claude Code stamps every entry of a turn (prompt, tool results, injected
    skill reminders, hook feedback) with the same promptId, so the turn starts
    at the first user entry carrying the last promptId. Without promptId
    (older transcripts) fall back to the last non-injected human prompt.
    """
    user = [(i, d) for i, d in enumerate(entries) if d.get("type") == "user" and not d.get("isSidechain")]
    for _, d in reversed(user):
        pid = d.get("promptId")
        if pid:
            return next(i for i, e in user if e.get("promptId") == pid)
    has_origin = any("origin" in d for _, d in user)
    for i, d in reversed(user):
        if d.get("isMeta") or d.get("turnCompanion"):
            continue
        text = text_of((d.get("message") or {}).get("content")).strip()
        if has_origin:
            if (d.get("origin") or {}).get("kind") == "human" and text:
                return i
        elif text and not text.startswith(INJECTED):
            return i
    return -1


def assistant_pieces(entries: list[dict[str, Any]], start: int) -> list[str]:
    """Assistant text blocks and tool markers after entries[start], in order."""
    pieces: list[str] = []
    for d in entries[start + 1:]:
        if d.get("type") != "assistant":
            continue
        content = (d.get("message") or {}).get("content")
        if isinstance(content, str):
            pieces.append(content)
        elif isinstance(content, list):
            for b in content:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text" and b.get("text"):
                    pieces.append(b["text"])
                elif b.get("type") == "tool_use":
                    pieces.append("[action: %s]" % b.get("name", "tool"))
    return pieces


def find_goal(entries: list[dict[str, Any]]) -> tuple[str, int] | None:
    """Last /goal condition set in the session, with the index of its message."""
    found: tuple[str, int] | None = None
    for i, d in enumerate(entries):
        if d.get("type") != "user":
            continue
        text = text_of((d.get("message") or {}).get("content"))
        if not text.startswith(GOAL_PREFIX):
            continue
        rest = text[len(GOAL_PREFIX):]
        end = rest.find('". ')
        found = (rest[:end] if end != -1 else rest, i)
    return found


def main(argv: list[str]) -> int:
    """Dispatch one query; prints the answer on stdout."""
    if len(argv) != 3 or argv[1] not in {"turn", "request", "response", "edits", "goal"}:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]
    try:
        entries = load(path)
    except OSError:
        entries = []
    idx = last_human(entries)

    if cmd == "turn":
        print((entries[idx].get("promptId") or entries[idx].get("uuid", "")) if idx >= 0 else "")
    elif cmd == "request":
        print(text_of((entries[idx].get("message") or {}).get("content")).strip() if idx >= 0 else "")
    elif cmd == "response":
        print("\n\n".join(assistant_pieces(entries, idx))[-CAP:])
    elif cmd == "edits":
        count = 0
        for d in entries[idx + 1:]:
            content = (d.get("message") or {}).get("content")
            if d.get("type") == "assistant" and isinstance(content, list):
                count += sum(1 for b in content if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in EDIT_TOOLS)
        print(count)
    else:  # goal
        goal = find_goal(entries)
        if goal is None:
            print(json.dumps({}))
        else:
            # Keep the END of the excerpt: the most recent work is what the judge must see.
            evidence = "\n\n".join(assistant_pieces(entries, goal[1]))[-CAP:]
            print(json.dumps({"goal": goal[0], "evidence": evidence}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
