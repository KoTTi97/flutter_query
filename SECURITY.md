# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | yes |

Before 1.0 only the latest published version gets fixes. A security fix ships
as a new patch release; there are no backports to earlier 0.x lines.

## Reporting a vulnerability

**Please do not open a public issue for a vulnerability.**

Use GitHub's private reporting — *Security* → *Report a vulnerability* on
<https://github.com/KoTTi97/flutter_query/security/advisories/new> — or email
christian@dualmeta.io. Either way, please include:

- which package and version,
- what an attacker can do, and what they need in order to do it,
- a reproduction: the smallest program or test that shows it.

You will get an acknowledgement within a week. If the report holds up, the fix
and the advisory go out together, and you are credited unless you would rather
not be.

## What is in scope

These are client-side libraries: they hold data in memory, keep timers, and
call a function you supply. The realistic classes of problem are

- data from one cache key becoming readable under another,
- a cancelled or superseded request's result still being applied,
- an error or a key ending up somewhere it is logged or displayed unescaped,
- unbounded growth that a remote peer can drive.

Out of scope: whatever your `queryFn` does with the network is your
transport's business, not the library's — this package has no HTTP client and
no dependency that does. The examples' express backends
(`examples/*/server/`) are deliberately hostile toy servers for tests and
demos; they are not published, and holes in them are not vulnerabilities.
