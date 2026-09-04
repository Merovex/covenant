---
name: triage-errors
description: Triage production errors for Covenant — pull unresolved Honeybadger faults, separate bot noise from real bugs, fix root causes in the codebase (never suppress), verify, and prepare the fix for deploy. Use when asked to triage, check, or fix production errors, Honeybadger faults, or error alerts.
---

# Triage production errors

Covenant reports production errors to Honeybadger (project **141023**,
https://app.honeybadger.io/projects/141023). This skill turns unresolved
faults into verified fixes.

## 1. Gather unresolved faults

In order of preference:

1. **Honeybadger MCP tools** (`mcp__honeybadger__*`), if configured: list
   unresolved faults for project 141023, then pull each fault's details,
   backtrace, and recent occurrences (headers, params, URL, IP).
2. **Pasted alert email**: the user may paste a Honeybadger notification;
   it contains the fault URL, exception class, message, and trace.
3. **Browser**: open the fault list at
   `https://app.honeybadger.io/projects/141023/faults?q=-is%3Aresolved+-is%3Aignored`.
4. **Production logs**: `kamal app logs --lines 500` (grep for the
   exception class). Note: Rails load-hook warnings at boot print long
   "Called from:" backtraces that look like crashes but aren't.

## 2. Classify each fault

**Bot noise** — scanners probing paths that don't exist here (WordPress
`/wp/`, `.php`, `.env`, `/admin` probes) or sending malformed/forged
headers. The app is Rails behind kamal-proxy on Docker; in forwarding
chains, `172.18.x.x` is the Docker network (kamal-proxy/Thruster hops),
not a client. For bot noise the fix is configuration that makes the
request fail cheaply and quietly (404, not 500) — e.g. the
`ip_spoofing_check = false` fix in `config/environments/production.rb`.
Never fix noise by ignoring the error class in Honeybadger while real
requests could still raise it.

**Real bugs** — anything reachable by legitimate users. Reproduce in a
test first when practical, then fix the root cause.

**Dependency/CVE failures** — CI's `scan_ruby` step runs
`bundler-audit`; fix by updating the affected gem to the patched version
(`bundle update <gem>`), never by ignoring the advisory. Same for
`bin/brakeman` — it passes `--ensure-latest`, so an outdated brakeman
gem itself fails CI; `bundle update brakeman` fixes that.

## 3. Fix and verify

- Fix root causes. Do not add `brakeman.ignore` entries, Honeybadger
  ignore rules, or rescue-and-swallow handlers to make a symptom
  disappear.
- Run the full check suite locally before declaring a fix done:
  `bin/rails test`, `bin/brakeman`, `bundle exec bundler-audit check --update`.
- Comment non-obvious config fixes in place (see the RemoteIp block in
  `production.rb` for the house style: what breaks without it and why
  it's safe).

## 4. Hand off

- **Leave changes uncommitted** and report what changed — commit, push,
  and `kamal deploy` only when the user explicitly asks (global rule).
- Remind the user that a fault stops recurring only after deploy;
  Honeybadger faults can then be marked resolved (via MCP tool, the
  dashboard, or replying `@resolve` to the alert email).
- If a fault is left open intentionally (e.g. waiting on upstream),
  say so explicitly rather than letting it linger silently.
