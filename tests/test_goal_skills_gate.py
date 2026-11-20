"""Checks for goal_skills_gate: deny until the six skills load, stay silent otherwise."""
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import goal_skills_gate as gate  # noqa: E402

GOAL = "<command-name>/goal</command-name>\n<command-args>x</command-args>"


def write(tmp: Path, prompt: str, skills: tuple[str, ...]) -> str:
    """Write a transcript with one human prompt and one Skill call per skill."""
    rows: list[dict[str, Any]] = [{"type": "user", "promptId": "p1", "uuid": "u1", "message": {"content": prompt}}]
    for s in skills:
        rows.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": s}}]}})
    path = tmp / "t.jsonl"
    path.write_text("\n".join(json.dumps(r) for r in rows))
    return str(path)


def payload(transcript: str, **extra: Any) -> dict[str, Any]:
    return {"transcript_path": transcript, "session_id": "s-test", "tool_name": "Bash", **extra}


def test_gate(tmp_path: Path, monkeypatch: Any) -> None:
    monkeypatch.setattr(gate, "STATE_DIR", tmp_path)
    none = write(tmp_path, GOAL, ())
    out = gate.decide(payload(none), "pretool")
    assert out and out["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert gate.decide(payload(none), "stop")["decision"] == "block"
    assert gate.decide(payload(none, tool_name="Skill"), "pretool") is None
    assert gate.decide(payload(none, agent_id="a1"), "pretool") is None
    some = write(tmp_path, GOAL, gate.REQUIRED[:5])
    assert "git-guidelines" in gate.decide(payload(some), "stop")["reason"]
    assert gate.decide(payload(write(tmp_path, GOAL, gate.REQUIRED)), "stop") is None
    assert gate.decide(payload(write(tmp_path, "oi", ())), "stop") is None


def test_safety_valve(tmp_path: Path, monkeypatch: Any) -> None:
    monkeypatch.setattr(gate, "STATE_DIR", tmp_path)
    t = write(tmp_path, GOAL, ())
    results = [gate.decide(payload(t), "stop") for _ in range(gate.MAX_BLOCKS + 1)]
    assert all("decision" in r for r in results[:-1])
    assert "systemMessage" in results[-1] and "decision" not in results[-1]
