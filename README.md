# flutter_query

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top.

The bet is fidelity: rather than reimplementing the *idea* of TanStack Query,
this ports the behavioral core and then ports upstream's test suite against it,
so the subtle things — request dedup across observers, revert-on-cancel, stale
timing, garbage collection, optimistic rollback — behave the way people who know
the library expect. Several existing Dart packages cover the idea; none has done
the fidelity work.

**Status (2026-09-08):** being re-planned from scratch as a wayfinder map on
[GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1). The
`flutter-port/` code is the previous attempt (`query_core` complete, 372 tests,
279 ported case-for-case); it is prior art the new plan may reuse where a
ticket evaluates it as suitable. Research behind the map is under
[`docs/research/`](docs/research/).

## Where to look

**The plan of record (active):**

| | |
|---|---|
| [GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1) | The wayfinder map: destination, standing rules, decisions so far, and the open decision tickets as sub-issues |
| [CLAUDE.md](CLAUDE.md) | Orientation for anyone (or any agent) picking the work up |
| [docs/research/](docs/research/) | Research behind the map's tickets |
| [docs/agents/](docs/agents/) | Tracker and domain-doc conventions |

**The previous attempt (prior art, frozen):**

| | |
|---|---|
| [flutter-port/README.md](flutter-port/README.md) | Its module map, test layout, how to run it |
| [flutter-port/DESIGN.md](flutter-port/DESIGN.md) | Its design doc — decisions D1–D13 and the amendments made while building |
| [flutter-port/PLAN.md](flutter-port/PLAN.md) | Its milestone plan M0–M9; M0–M6 built, the rest never started |
| [flutter-port/packages/query_core/test/PORTING_NOTES.md](flutter-port/packages/query_core/test/PORTING_NOTES.md) | Its fidelity audit — what is ported, what is not, and why |

## Repository layout

- `flutter-port/` — the previous attempt's code (prior art).
- `docs/` — research findings and agent conventions for the plan of record.
- `query/` — upstream TanStack Query, and the source of the ported tests.
  A nested clone, gitignored; the fresh port pins `50680b98c`, the existing code `5bb950be8`.
- `react-demo/` — the React sensor demo and its shared express gateway, which
  define the MVP acceptance bar. Vendored into this repo, so it is tracked;
  only its `node_modules` is ignored.

The `query/` checkout is needed to work on either; CLAUDE.md has the clone
command and both pinned revisions.

## Quick start (previous attempt's tests)

```bash
cd flutter-port/packages/query_core && dart test
```
