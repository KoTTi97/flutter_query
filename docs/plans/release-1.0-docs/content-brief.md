# Content brief for the site's wave-3 chunks (C4a–d, C5, C6a–b)

Binding for every agent writing pages under `website/docs/`. Decisions D1–D8
in [README.md](README.md) apply.

## The model

TanStack Query's React docs (`query/docs/framework/react/`, read them from
`query/docs/framework/react`) are the
bar: one concept per page, opening with the problem in the reader's words,
then the smallest working code, then the variations, then the traps. Adapt,
never copy: no sentence of TanStack's text is reproduced; the ideas and order
are fair game, the prose is ours.

## Every guide page

1. Front matter: `title`, `description` (one sentence, used in search and
   link previews), `sidebar_label` only when the title is long.
2. Remove the `{/* depth: todo */}` marker when the page is done. Replace
   each `{/* demo: … */}` marker with `<LiveDemo feature="<id>" />` (registered
   globally; ids are the showcase routes in
   `website/src/components/LiveDemo/showcase-features.json`), placed where the
   reader has just read what the demo shows, with one sentence saying what to
   try in it ("Toggle *fail next request* and watch …"). Read the feature's
   screen in `examples/showcase/lib/features/<id_with_underscores>/` so the
   sentence matches what the screen really offers.
3. At least one **real-project** example per page: not `fetchTodos`, but the
   shape of an app — a repository class with dio, a product list with a
   detail screen, a settings form, a device list. Show where the code lives in
   an app (`lib/data/…_queries.dart`, a widget), not only the call.
4. Show Flutter first (the binding), and when a page's concept is call-style
   specific, show the four call styles as **equal alternatives**, never one as
   the default (a maintainer rule), e.g. with Docusaurus `<Tabs>` whose
   default tab rotates or is `context.query` only because it is shortest —
   say nothing that ranks them.
5. A short `:::note[In React Query]` aside naming the TanStack API this
   corresponds to, and any behavioural difference as behaviour, linking
   `/docs/reference/differences-from-tanstack`.
6. Cross-links: "Next" pointers are handled by the sidebar; link related
   concepts inline where a reader would ask.
7. No internal history (D3): no review rounds, IDs, tickets, dates, ADRs.
   `dart run tool/check_docs_jargon.dart` must report 0 hits for your pages.
8. Admonitions use the v4 syntax `:::tip[Title]` — `:::tip Title` renders as
   plain text.

## Every Dart sample compiles (D6)

Read the header of `examples/doc_snippets/test/site_fences_test.dart`. Every
` ```dart ` fence carries `snippet="<page>#<name>"` (exact twin),
`snippet="excerpt: <page>#<name>"` (elided, must show `…`) or
`snippet="prose-only: <reason>"` (needs dio/connectivity_plus/etc. — neither
package may depend on those; the doc_snippets package also may not add them).
**Put your twins in your own file** `examples/doc_snippets/lib/<chunk>.dart`
(e.g. `c4a_guides.dart`) so parallel chunks don't collide; export or import it
wherever the existing files do so it is analyzed. Prefer exact twins; use
`excerpt:` for elided samples. A sample using dio is prose-only but must still
be correct — check dio's API (`CancelToken`, `DioException`, interceptors) as
of dio 5.

## Facts come from the code

Before stating a default, an order, a throw, a timing: open
`packages/query_kit/lib` / `packages/query_kit_flutter/lib` and check. The
dartdoc there was just reviewed against the code and is a good first source.
A wrong statement is the worst bug a docs page can have.

## Your files only

Edit only the pages your chunk owns, your own snippet file, and (C5/C6 only)
your sidebar section. If you must touch a shared file (`sidebars.ts`,
`guides.dart`, another chunk's page) keep the edit minimal and say so in your
final message.

## Gates before committing

- `cd website && npm ci && npm run typecheck && npm run build` (broken links
  fail the build).
- `cd examples/doc_snippets && flutter test`, `dart analyze --fatal-infos
  examples/doc_snippets`, `dart format --set-exit-if-changed
  examples/doc_snippets/lib examples/doc_snippets/test` (run `flutter pub get`
  at the repo root first; if pub rewrites `pubspec.lock`, restore it with
  `git checkout pubspec.lock`).
- `dart run tool/check_docs_jargon.dart` — 0 hits in your pages.
- Visual: `bash tool/build_demos.sh` once (slow; needs Flutter), then build
  and serve the site (`npx docusaurus serve --port <unique> --no-open` in the
  background), and screenshot two of your pages with Playwright (installed in
  `website/e2e`), one with a demo started; look at the images. Stop the
  server.

Commit in your worktree with a message ending
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
