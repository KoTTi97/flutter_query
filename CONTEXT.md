# Context: query_kit

A glossary of the terms this repository uses precisely. Implementation lives
in the packages; decisions live in [`docs/adr/`](docs/adr/).

## Terms

- **Query options** — what the cache layer needs to run a query: key, function,
  staleness, retry, network mode. One type argument: the query's data type.
- **Observer options** — query options plus what only an observer cares about
  (placeholder data, refetch triggers, polling). Come in two **shapes**:
  - **Plain** — no `select`; the observer reports the query's data as its own.
    One type argument.
  - **Select** — a required `select` projects the query's data into another
    type. Two type arguments: the query's data and the selected data.
- **Type slot** — a type argument on an options object or an entry point. A
  slot is *anchored* when a required parameter determines it; an unanchored
  slot infers to `dynamic` silently, which is the failure ADR-0001 rules out.
- **Call style** — one of the four equal ways the Flutter binding reads a
  query: builder widget, controller, `State` mixin, `context` extension. Each
  has a plain and a select entry point.
- **Teardown** — the five steps a widget test ends with so the client's
  `gcTime` timers are gone before the test binding checks for pending timers:
  drop the tree, settle, `clear()`, one more `pump()` for what a dropped
  mutation's callbacks write, `clear()` again (the last two since C11). A
  documented snippet, not an export (ADR-0002).
