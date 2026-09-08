# flutter_query

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a builder-first Flutter binding on top.

The bet is fidelity: rather than reimplementing the *idea* of TanStack Query,
this ports the behavioral core and then ports upstream's test suite against it,
so the subtle things — request dedup across observers, revert-on-cancel, stale
timing, garbage collection, optimistic rollback — behave the way people who know
the library expect. Several existing Dart packages cover the idea; none has done
the fidelity work.

**Status:** `query_core` is complete for the MVP and passing 372 tests, of which
279 are ported case-for-case from six upstream suites. The Flutter binding and
the demo app are next.

## Where to look

| | |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Orientation for anyone (or any agent) picking the work up: layout, current state, conventions, commands |
| [flutter-port/DESIGN.md](flutter-port/DESIGN.md) | Design doc of record — decisions D1–D13 and the amendments made while building |
| [flutter-port/PLAN.md](flutter-port/PLAN.md) | Milestone plan M0–M9 with current status |
| [flutter-port/packages/query_core/test/PORTING_NOTES.md](flutter-port/packages/query_core/test/PORTING_NOTES.md) | Fidelity audit — what is ported, what is not, and why |
| [flutter-port/README.md](flutter-port/README.md) | The port itself: module map, test layout, how to run it |

## Repository layout

- `flutter-port/` — the port. This is the tracked work.
- `query/` — upstream TanStack Query, and the source of the ported tests.
  A nested clone, gitignored; pinned to `5bb950be8`.
- `react-demo/` — the React sensor demo and its shared express gateway, which
  define the MVP acceptance bar. Also a nested clone, gitignored.

Both nested checkouts are needed to work on the port; CLAUDE.md has the clone
commands and the pinned revision.

## Quick start

```bash
cd flutter-port/packages/query_core && dart test
```
