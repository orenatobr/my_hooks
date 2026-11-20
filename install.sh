#!/usr/bin/env bash
# Installs the my_hooks Claude Code hooks into ~/.claude (or $CLAUDE_DIR).
# Idempotent: re-running changes nothing. Existing files that differ are backed up first.
# Usage: ./install.sh [--dry-run] [--with-iterm] [--with-mod] [--check]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
dry=0; iterm=0; mod=0; check=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --with-iterm) iterm=1 ;;
    --with-mod) mod=1 ;;
    --check) check=1 ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
run() { if [ "$dry" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# 1. Prerequisites. Hard requirements fail, optional tools only warn.
missing=0
for t in bash jq python3 git; do
  command -v "$t" >/dev/null 2>&1 || { say "MISSING required tool: $t"; missing=1; }
done
for t in gh claude graphify pre-commit gitleaks; do
  command -v "$t" >/dev/null 2>&1 || say "note: optional tool not found: $t (see README, Prerequisites)"
done
for s in andrej-karpathy-skills humanizer graphify; do
  { [ -d "$CLAUDE_DIR/skills/$s" ] || ls -d "$CLAUDE_DIR"/plugins/cache/*/"$s"* >/dev/null 2>&1; } \
    || say "note: third-party skill not found: $s (see README, Prerequisites)"
done
[ "$missing" = 0 ] || exit 1
[ "$check" = 1 ] && { say "check: prerequisites OK"; exit 0; }

ts="$(date +%Y%m%d-%H%M%S)"
backup="$CLAUDE_DIR/backups/my_hooks-$ts"
backup_if_differs() {  # src dst
  if [ -e "$2" ] && ! diff -rq "$1" "$2" >/dev/null 2>&1; then
    run mkdir -p "$backup/$(dirname "${2#"$CLAUDE_DIR"/}")"
    run cp -R "$2" "$backup/${2#"$CLAUDE_DIR"/}"
    say "backed up $2"
  fi
}

# 2. Scripts.
run mkdir -p "$CLAUDE_DIR/scripts"
for f in "$REPO"/scripts/*; do
  dst="$CLAUDE_DIR/scripts/$(basename "$f")"
  backup_if_differs "$f" "$dst"
  run cp -p "$f" "$dst"
  run chmod +x "$dst"
done

# 3. Skills written for these hooks (third-party skills are NOT shipped here).
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"; dst="$CLAUDE_DIR/skills/$name"
  backup_if_differs "$d" "$dst"
  run mkdir -p "$dst"
  run cp -R "$d". "$dst/"
done

# 4. Optional mod (opens /diff and the editor on session start).
if [ "$mod" = 1 ]; then
  dst="$CLAUDE_DIR/mods/git-diff-on-start"
  backup_if_differs "$REPO/mods/git-diff-on-start" "$dst"
  run mkdir -p "$dst"
  run cp -R "$REPO/mods/git-diff-on-start/." "$dst/"
fi

# 5. Merge hook registrations into settings.json without touching other keys.
settings="$CLAUDE_DIR/settings.json"
[ -f "$settings" ] || { run mkdir -p "$CLAUDE_DIR"; [ "$dry" = 1 ] || echo '{}' > "$settings"; }
parts=("$REPO/settings/core.json")
[ "$iterm" = 1 ] && parts+=("$REPO/settings/iterm.json")
[ "$mod" = 1 ] && parts+=("$REPO/settings/mod.json")
if [ "$dry" = 1 ]; then
  say "[dry-run] would merge ${parts[*]##*/} into $settings"
else
  mkdir -p "$backup"; cp "$settings" "$backup/settings.json"
  fragment="$(jq -s 'reduce .[] as $p ({hooks: {}, env: {}};
      .env += ($p.env // {})
      | .hooks = (reduce (($p.hooks // {}) | to_entries[]) as $e (.hooks; .[$e.key] += $e.value)))' "${parts[@]}")"
  tmp="$(mktemp)"
  # A group is added only when no existing group already runs the same first command ($HOME-normalized).
  jq --arg home "$HOME" --argjson new "$fragment" '
    def norm: gsub("\\$HOME"; $home);
    def first_cmd: (.hooks[0].command // "") | norm;
    reduce ($new.hooks | to_entries[]) as $e (.;
      .hooks[$e.key] = ((.hooks[$e.key] // []) as $cur
        | $cur + [ $e.value[] | select(first_cmd as $c | ($cur | any(first_cmd == $c)) | not) ]))
    | .env = ((.env // {}) + $new.env)' "$settings" > "$tmp"
  jq empty "$tmp"
  mv "$tmp" "$settings"
fi

say "done. Restart Claude Code, then type /hooks to confirm. Backups (if any): $backup"
