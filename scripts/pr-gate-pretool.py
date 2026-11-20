#!/usr/bin/env python3
"""PreToolUse gate: block non-compliant commits/pushes/PRs before they exist.

Covers `git commit -m`, `git push`, `gh pr create|edit` and the GitHub MCP
create/update_pull_request. Violations: exit 2 with the fixes on stderr.
Only mechanical fixes (em dash, trailing period in an MCP title) are applied
through updatedInput; a missing/incomplete PR body is denied with a
pre-filled template file to complete (nothing is invented).
"""
import hashlib
import json
import re
import shlex
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import pr_lint as L  # noqa: E402

START = r"(?:^|[;&|(]\s*|\n\s*)"
HEREDOC = re.compile(r"^\$\(cat <<-?['\"]?(\w+)['\"]?\n(.*?)\n\s*\1\s*\)$", re.S)


def tokens(cmd, pattern):
    """Tokens of the first command matching `pattern`, up to the next shell operator."""
    m = re.search(START + f"(?P<c>{pattern})", cmd)
    if not m:
        return None
    lex = shlex.shlex(cmd[m.start("c"):], posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    out = []
    for t in lex:
        if t in ("&&", "||", ";", "|", "&", "\n"):
            break
        out.append(t)
    return out


def val(tok):
    h = HEREDOC.match(tok)
    return h.group(2) if h else tok


def flag(toks, long, short=None):
    for i, t in enumerate(toks):
        if t == f"--{long}" or (short and t == f"-{short}") or (short and re.fullmatch(rf"-[a-zA-Z]*{short}", t)):
            return val(toks[i + 1]) if i + 1 < len(toks) else None
        if t.startswith(f"--{long}="):
            return val(t.split("=", 1)[1])
    return None


def all_flags(toks, long, short):
    vals, i = [], 0
    while i < len(toks):
        t = toks[i]
        if (t == f"--{long}" or re.fullmatch(rf"-[a-zA-Z]*{short}", t)) and i + 1 < len(toks):
            vals.append(val(toks[i + 1]))
            i += 1
        elif t.startswith(f"--{long}="):
            vals.append(val(t.split("=", 1)[1]))
        i += 1
    return vals


def deny(lines):
    print("pr-gate: blocked, fix and retry:\n  - " + "\n  - ".join(lines), file=sys.stderr)
    sys.exit(2)


def allow_updated(updated):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                             "updatedInput": updated}}))
    sys.exit(0)


def deny_body(title, body_errors, cwd, extra=()):
    base = L.default_base(cwd)
    commits = L.commits_in(f"{base}..HEAD", cwd) if base else []
    tpl = L.template(cwd)
    path = Path(tempfile.gettempdir()) / f"pr-body-{hashlib.md5((title or '').encode()).hexdigest()[:8]}.md"
    path.write_text(L.skeleton(title, commits, tpl, cwd))
    deny(list(extra) + body_errors + [
        f"template pre-filled at {path}: replace every {L.TODO}, then pass it with --body-file {path} "
        "(or as the MCP body)"])


def sanitize(s):
    return s.replace(f" {L.EM} ", ", ").replace(L.EM, ",") if s else s


def gate_commit(cmd, cwd):
    toks = tokens(cmd, r"git commit\b")
    if toks is None:
        return
    msgs = all_flags(toks, "message", "m")
    if not msgs:
        return  # editor, -F or --no-edit: nothing parseable here
    msg = "\n\n".join(msgs)
    head, _, body = msg.partition("\n")
    if head.startswith("Merge "):
        return
    e = L.lint_header(head, "commit header")
    if L.EM in body:
        e.append("commit body: contains an em dash")
    if not body.strip():
        e.append("commit: no body (explain what and why after a blank line)")
    if e:
        deny(e)


def gate_push(cmd, cwd):
    toks = tokens(cmd, r"git push\b")
    if toks is None or any(t in ("--delete", "-d", "--tags") or t.startswith(":") for t in toks):
        return
    branch = L.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd)
    base = L.default_base(cwd)
    if not branch or branch == "HEAD" or (base and base.split("/")[-1] == branch):
        return
    up = L.run(["git", "rev-parse", "--abbrev-ref", "@{u}"], cwd)
    rng = f"{up}..HEAD" if up else (f"{base}..HEAD" if base else "")
    if not rng:
        return
    e = L.lint_commits(L.commits_in(rng, cwd))
    if not up:
        e += L.lint_branch(branch, cwd)
    if e:
        deny(e + ["these commits are not pushed yet, so rewrite them now (git commit --amend, or "
                  "git reset --soft <base> && git commit); after the push it needs a force push"])


def gate_gh_pr(orig, cwd):
    cmd = sanitize(orig)
    toks = tokens(cmd, r"gh pr (?:create|edit)\b")
    if toks is None:
        return
    creating = toks[2] == "create"
    if "--web" in toks or "-w" in toks:
        return
    title, body = flag(toks, "title", "t"), flag(toks, "body", "b")
    bf = flag(toks, "body-file", "F")
    if bf and bf != "-" and Path(bf).is_file():
        body = Path(bf).read_text()
    if bf == "-":
        deny(["--body-file - (stdin) cannot be validated, write the body to a file"])
    if creating and (title is None or body is None):
        deny_body(title, [], cwd, extra=["gh pr create needs --title and --body/--body-file (no --fill/--web)"])
    if title is None and body is None:
        return
    e = L.lint_pr(title, body, cwd)
    if creating:
        base = L.default_base(cwd)
        e += L.lint_commits(L.commits_in(f"{base}..HEAD", cwd)) if base else []
    if e:
        if any(x.startswith("body") for x in e):
            deny_body(title, e, cwd)
        deny(e)
    if cmd != orig:
        allow_updated({"command": cmd})


def gate_mcp(name, ti, cwd):
    title, body = ti.get("title"), ti.get("body")
    creating = name.endswith("create_pull_request")
    if creating and (title is None or body is None):
        deny_body(title, [], cwd, extra=["create_pull_request needs title and body"])
    e = L.lint_pr(title, body, cwd)
    if e:
        if any(x.startswith("body") for x in e):
            deny_body(title, e, cwd)
        deny(e)


def main():
    p = json.load(sys.stdin)
    tool, ti, cwd = p.get("tool_name", ""), p.get("tool_input") or {}, p.get("cwd")
    if tool == "Bash":
        cmd = ti.get("command", "")
        try:
            gate_commit(cmd, cwd)
            gate_push(cmd, cwd)
            gate_gh_pr(cmd, cwd)
        except (ValueError, IndexError):
            pass  # unparseable shell: do not block on our own parsing limits
    elif tool.startswith("mcp__plugin_github_github__") and tool.endswith("_pull_request"):
        t, b = ti.get("title"), ti.get("body")
        st, sb = sanitize(t), sanitize(b)
        if st:
            st = st.rstrip(".")
        fixed = {**ti, **{k: v for k, v in (("title", st), ("body", sb)) if v is not None}}
        gate_mcp(tool, fixed, cwd)
        if fixed != ti:
            allow_updated(fixed)


main()
