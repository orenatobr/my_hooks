---
name: git-guidelines
description: Use when naming a branch, writing a commit message, titling a PR or drafting a PR description. Applies Conventional Commits and git best practices, output in EN-US. Trigger on /git-guidelines, "PR template", "commit message", "branch name", "PR description".
---

# /git-guidelines

Produce branch name, commit message, PR title and PR description in **EN-US**, following the rules below. If the user passes context (diff, ticket, summary), fill the templates with it; otherwise show the blank templates. Never use em dashes.

## Branch name

```
<type>/[<ticket-id>-]<short-kebab-description>
```

The ticket id is optional. Examples: `feat/PROJ-123-add-oauth-login`, `fix/PROJ-456-null-user-on-checkout`, `chore/bump-0.1.82`

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

## Commit message (Conventional Commits)

```
<type>(<scope>): <imperative summary, max 72 chars, no period>

<body: what and why, wrapped at 72 chars>

BREAKING CHANGE: <description, only if applicable>
Refs: PROJ-123 (optional)
```

- The `(<scope>)` is mandatory (`feat(auth): ...`, never `feat: ...`): the module, area or component touched.
- Imperative mood ("add", not "added").
- One logical change per commit.
- Use `!` after the type (`feat(api)!:`) for breaking changes.

## PR title

Same format as the commit header, scope included, because it becomes the squash commit. The ticket suffix is optional. The 72-char limit applies, ticket included:

```
feat(auth): add OAuth2 login with Google (PROJ-123)
```

## PR description

```markdown
## Summary
<!-- What does this PR do and why? 1-3 sentences. -->

## Type of change
- [ ] feat (new feature)
- [ ] fix (bug fix)
- [ ] refactor / perf
- [ ] docs / test / chore / ci
- [ ] Breaking change

## Related issues
Closes #123

## Changes
- Added ...
- Changed ...
- Removed ...

## How to test
1. Check out the branch
2. Run `...`
3. Expected result: ...

## Screenshots / logs (if applicable)

## Risks and rollback
<!-- Impact, migrations, feature flags. How to revert safely. -->

## Checklist
- [ ] Title follows Conventional Commits
- [ ] Branch is up to date with the base branch
- [ ] Tests added or updated and passing
- [ ] Lint and type checks pass
- [ ] Docs / changelog updated
- [ ] No secrets or debug code committed
- [ ] Self-reviewed the diff
```

If the repo has `.github/pull_request_template.md`, use it instead of the block above.

## Best practices

- Small PRs (under ~400 changed lines), one purpose each.
- Rebase on the base branch before merge to keep history linear.
- Squash merge when branch commits are noisy; the PR title becomes the message.
- Open a draft PR for work in progress.
- Protect `main`: required review and green CI.
