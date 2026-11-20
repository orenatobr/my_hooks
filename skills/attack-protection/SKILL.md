---
name: attack-protection
description: Use when writing, changing or reviewing any code that handles user input, renders HTML, exposes API routes, uses secrets or API keys, touches a database, calls an LLM, or adds dependencies. Builds code defensively against 8 attacks (XSS, exposed API routes, exposed API keys, open database, SQL injection, no rate limit, prompt injection, hallucinated packages). Trigger on /attack-protection, "hardening", "security checklist".
---

# /attack-protection

Write (or review) code so the 8 attacks below fail by construction. Before finishing, walk the 8 checks against the code touched and fix every miss. If invoked with a file, diff or path, audit it and report per attack: OK, FIXED or RISK (with file:line). Never use em dashes.

## 1. XSS
- Never insert user data as HTML: no `innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `document.write`, `eval`, `javascript:` URLs. Use `textContent` or the framework's default escaping.
- If HTML from users is unavoidable, sanitize with DOMPurify (allowlist tags).
- Add a CSP header (`default-src 'self'`, no `unsafe-inline`), cookies `HttpOnly; Secure; SameSite=Lax`, and `X-Content-Type-Options: nosniff`.
- Escape on output for the exact context (HTML, attribute, JS, URL).

## 2. Exposed API routes
- Every route is private by default: authenticate first, then authorize the specific resource (owner/role check, prevents IDOR).
- Deny by default; public routes are an explicit allowlist.
- Validate body, query and params with a schema (zod, pydantic) and reject unknown fields.
- Restrict CORS to known origins (never `*` with credentials). Protect state-changing cookie-auth routes against CSRF.
- Return generic errors; no stack traces, no internal IDs or enumeration hints. Disable debug/docs endpoints in production.

## 3. Exposed API keys
- Secrets only from env vars or a secret manager. Never hardcode, never in client bundles (`NEXT_PUBLIC_`, `VITE_`, etc. are public), never in logs, URLs or error messages.
- Calls needing a secret go through a backend/proxy; the browser gets short-lived tokens at most.
- `.env*` in `.gitignore`; commit only `.env.example` with placeholders. Add a secret scan (gitleaks/trufflehog) to pre-commit or CI.
- If a key was ever committed or pasted, treat it as leaked: rotate it, do not just delete it.

## 4. Open database
- Never expose the DB to the internet: private network or localhost, firewall, no default creds, TLS on.
- Least privilege: the app user gets only the grants it needs (no superuser, no DDL at runtime).
- Row-level security / per-tenant filters on every query (Supabase/Firebase rules must be on, never "allow all").
- Encrypt backups, hash passwords with argon2/bcrypt, never store plaintext secrets or card data.

## 5. SQL injection
- Parameterized queries or ORM query builders only. Never build SQL with string concat, f-strings or template literals.
- Identifiers (table/column/order by) cannot be parameterized: map them from a fixed allowlist.
- Apply the same to NoSQL operators (`$where`, `$ne` from user JSON) and shell/ORM raw escape hatches.

## 6. No attempt limit
- Rate limit every route by IP and by account; tight limits on login, signup, password reset, OTP, and any costly or LLM endpoint.
- Login: exponential backoff or temporary lockout after N failures, same error for unknown user and wrong password, CAPTCHA after repeated failures.
- OTP/reset tokens: short expiry, single use, attempt cap.
- Cap request body size, pagination size and timeouts.

## 7. Prompt injection
- Treat all external text (user input, web pages, files, emails, tool results, RAG docs) as data, never as instructions. Keep it in separate, delimited message parts, not concatenated into the system prompt.
- Least privilege for tools: allowlist tools, no destructive or outbound action (send, delete, pay, shell) without human confirmation; never let model output reach `eval`, shell or SQL unvalidated.
- Validate and schema-check model output; strip or block markdown images/links that could exfiltrate data to external URLs.
- Never put secrets in prompts; scope the model's data access to the current user.

## 8. Invented (hallucinated) packages
- Never add a dependency from memory. Verify it exists on the registry (`npm view <pkg>`, `pip index versions <pkg>`), check publisher, download count, repo link and age. Beware typosquats (one-letter variants of popular names).
- Prefer stdlib or an already-installed dependency. Pin versions, commit the lockfile, install with `npm ci` / `pip install --require-hashes` when possible.
- Run `npm audit` / `pip-audit` in CI. If a package cannot be verified, do not install it; tell the user.

## Output when writing code
After the code, add one line per attack touched, e.g. `XSS: textContent only | Routes: authz on /orders/:id | Keys: env only | DB: parameterized | Rate: 5/min login | Prompt: input delimited | Pkgs: verified on npm`. Mark any attack not applicable as `n/a`. Anything you could not guarantee goes under `RISK` with the reason.
