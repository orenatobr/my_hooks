#!/usr/bin/env bash
# Smoke test: installs into a throwaway HOME, checks idempotence and that hook output is en-US.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude" "$HOME/proj"
echo '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}' > "$HOME/.claude/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }

"$REPO/install.sh" --with-iterm --with-mod >/dev/null
s="$HOME/.claude/settings.json"
jq empty "$s" || fail "settings.json invalid"
[ "$(jq -r .theme "$s")" = dark ] || fail "existing keys were not preserved"
[ "$(jq '.hooks.Stop | length' "$s")" = 3 ] || fail "Stop should hold the original plus 2 new groups"
sha1="$(shasum "$s" | cut -d' ' -f1)"
"$REPO/install.sh" --with-iterm --with-mod >/dev/null
[ "$(shasum "$s" | cut -d' ' -f1)" = "$sha1" ] || fail "second install changed settings.json (not idempotent)"
for f in "$HOME"/.claude/scripts/*.sh; do bash -n "$f" || fail "syntax error in $f"; done
for f in "$HOME"/.claude/scripts/*.py; do python3 -I -m py_compile "$f" || fail "syntax error in $f"; done
for sk in git-guidelines attack-protection programming-best-practices tests-guidelines quality-gate llm-as-judge; do
  [ -f "$HOME/.claude/skills/$sk/SKILL.md" ] || fail "skill $sk missing"
done

out="$(printf '{"prompt":"/goal x","cwd":"%s"}' "$HOME/proj" | "$HOME/.claude/scripts/goal-start-trigger.sh")"
msg="$(printf '%s' "$out" | jq -r .systemMessage)"
printf '%s' "$msg" | grep -q 'Writing text with /humanizer' || fail "UserPromptSubmit message is not the en-US text"
printf '%s\n%s' "$msg" "$(printf '%s' "$out" | jq -r .hookSpecificOutput.additionalContext)" | python3 -I -c '
import re, sys
t = sys.stdin.read()
sys.exit(1 if re.search(r"[\u00c0-\u00ff]|OBRIGATORIO", t) else 0)' || fail "Portuguese text found in goal hook output"
python3 -I - "$REPO" <<'PY' || fail "accented characters or em dashes in shipped files"
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
bad = []
for p in list(root.glob("scripts/*")) + list(root.glob("skills/**/*.md")) + list(root.glob("settings/*")) + [root / "install.sh", root / "README.md", root / "AGENTS.md"]:
    if p.is_file() and re.search(r"[\u00c0-\u00ff\u2014]", p.read_text(encoding="utf-8")):
        bad.append(str(p))
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
echo "smoke: OK"
