#!/usr/bin/env python3
"""Deterministic /git-guidelines linter for commits, PR title/body and branch.

Library for pr-gate-pretool.py; CLI for the Stop hook:
  pr_lint.py url <pr-url-or-number>   exit 0 = ok (or PR not OPEN), 1 = errors printed
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

TYPES = "feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
HEADER = re.compile(rf"^({TYPES})\([\w./-]+\)!?: \S.*[^.\s]$")
EM = "\u2014"
TODO = "TODO(fill)"
SKILL = pathlib.Path.home() / ".claude/skills/git-guidelines/SKILL.md"
GH = shutil.which("gh") or "/opt/homebrew/bin/gh"
HEADING = re.compile(r"(?m)^#{1,6}[ \t]+(.+?)[ \t]*$")
FENCE = re.compile(r"(?s)```.*?```")
COMMENT = re.compile(r"(?s)<!--.*?-->")


def run(cmd, cwd=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def template(cwd=None):
    top = run(["git", "rev-parse", "--show-toplevel"], cwd)
    for name in ("PULL_REQUEST_TEMPLATE.md", "pull_request_template.md"):
        p = pathlib.Path(top or ".") / ".github" / name
        if top and p.is_file():
            return p.read_text()
    m = re.search(r"## PR description\s+```markdown\n(.*?)\n```", SKILL.read_text(), re.S)
    return m.group(1) if m else ""


def sections(text):
    """Ordered [(heading, content)] outside code fences."""
    text = FENCE.sub("", text)
    hs = list(HEADING.finditer(text))
    return [(h.group(1).strip(), text[h.end(): hs[i + 1].start() if i + 1 < len(hs) else len(text)])
            for i, h in enumerate(hs)]


def optional(heading):
    return bool(re.search(r"if applicable|optional", heading, re.I))


def lint_header(h, label):
    e = []
    if len(h) > 72:
        e.append(f"{label}: {len(h)} chars, max 72")
    if not HEADER.match(h):
        e.append(f"{label}: must match 'type(scope): imperative summary' (types: {TYPES.replace('|', ', ')}), no trailing period")
    if EM in h:
        e.append(f"{label}: contains an em dash")
    return e


def lint_body(body, tpl):
    e = []
    if EM in body:
        e.append("body: contains an em dash")
    if TODO in body:
        e.append(f"body: still has {TODO} placeholders")
    want, got = sections(tpl), sections(body)
    names = [g[0].lower() for g in got]
    pos = -1
    for h, _ in want:
        if h.lower() not in names:
            e.append(f"body: missing section '{h}'")
            continue
        i = names.index(h.lower())
        if i < pos:
            e.append(f"body: section '{h}' is out of template order")
        pos = max(pos, i)
    for h, _ in want:
        if h.lower() not in names or optional(h):
            continue
        content = COMMENT.sub("", got[names.index(h.lower())][1]).strip()
        if not content:
            e.append(f"body: section '{h}' is empty")
        elif re.search(r"type of change", h, re.I) and "[ ]" in dict(want)[h] and not re.search(r"\[[xX]\]", content):
            e.append(f"body: section '{h}' has no checked box")
    return e


def lint_commits(commits):
    """commits: [(sha, subject, body)]"""
    e = []
    for sha, subj, body in commits:
        if subj.startswith("Merge "):
            continue
        e += lint_header(subj, f"commit {sha[:7]} header")
        if not body.strip():
            e.append(f"commit {sha[:7]}: no body (explain what and why)")
    return e


def lint_branch(name, cwd=None):
    if not name or re.match(rf"^({TYPES}|ai)/([A-Z][A-Z0-9]+-\d+-)?[a-z0-9][a-z0-9.-]*$", name):  # ai/ = autonomous daily runs
        return []
    return [f"branch '{name}': must be '<type>/[<TICKET-ID>-]<kebab-description>'"]


def default_base(cwd=None):
    ref = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd)
    if ref:
        return ref
    for r in ("origin/main", "origin/master", "main", "master"):
        if run(["git", "rev-parse", "--verify", r], cwd):
            return r
    return ""


def commits_in(rng, cwd=None):
    out = run(["git", "log", "--format=%H%x1f%s%x1f%b%x1e", rng], cwd)
    res = []
    for rec in filter(str.strip, out.split("\x1e")):
        sha, subj, body = (rec.strip("\n").split("\x1f") + ["", ""])[:3]
        res.append((sha, subj, body))
    return res


def skeleton(title, commits, tpl, cwd=None):
    """Template pre-filled with what is derivable; the rest is TODO(fill)."""
    tm = re.match(rf"^({TYPES})(\(.*?\))?(!)?:", title or "")
    typ, brk = (tm.group(1), bool(tm.group(3))) if tm else ("", False)
    checks = {"feat": "feat", "fix": "fix", "refactor": "refactor / perf", "perf": "refactor / perf"}
    refs = sorted({m for _, s, b in commits for m in re.findall(r"(?:Closes|Fixes|Refs):? (#?[\w-]+)", b)})
    first_body = next((b.strip().split("\n\n")[0] for _, _, b in commits if b.strip()), "")
    out = []
    for h, content in sections(tpl):
        k = h.lower()
        if "summary" in k:
            body = first_body or TODO
        elif "type of change" in k:
            body = "\n".join(
                f"- [{'x' if (l.lower().lstrip('- [ ]').startswith(checks.get(typ, 'docs')) or (brk and 'breaking' in l.lower())) else ' '}] "
                + re.sub(r"^- \[.\] ", "", l) for l in content.strip().splitlines() if l.strip().startswith("- ["))
        elif "related" in k:
            body = "\n".join(f"Closes {r}" if r.startswith("#") else f"Refs: {r}" for r in refs) or "None"
        elif k == "changes":
            body = "\n".join(f"- {s}" for _, s, _ in commits) or TODO
        elif optional(h):
            body = "N/A"
        elif "checklist" in k:
            body = COMMENT.sub("", content).strip().replace("- [ ] Title follows Conventional Commits", "- [x] Title follows Conventional Commits")
        else:
            body = TODO
        out.append(f"## {h}\n{body}\n")
    return "\n".join(out)


def lint_pr(title, body, cwd=None):
    e = lint_header(title, "title") if title is not None else []
    if body is not None:
        e += lint_body(body, template(cwd))
    return e


def cli_url(ref):
    r = run([GH, "pr", "view", ref, "--json", "state,title,body,headRefName,commits,additions,deletions,url"])
    if not r:
        return 0  # gh unavailable or PR unreachable: nothing to judge
    d = json.loads(r)
    if d["state"] != "OPEN":
        return 0
    cs = [(c["oid"], c["messageHeadline"], c["messageBody"]) for c in d["commits"]]
    e = lint_pr(d["title"], d["body"]) + lint_commits(cs) + lint_branch(d["headRefName"])
    if d["additions"] + d["deletions"] > 400:
        print(f"note (non-blocking): {d['additions'] + d['deletions']} changed lines, guideline is ~400")
    if e:
        print(f"{d['url']}\n  - " + "\n  - ".join(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(cli_url(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == "url" else 2)
