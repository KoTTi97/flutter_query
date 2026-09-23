# The query_kit documentation site

[Docusaurus 3](https://docusaurus.io). The prose lives in `docs/`, the landing
page in `src/pages/`. The site is built in CI on every push, so a broken link
or a failing build is caught, and deployed to GitHub Pages
(<https://dualmeta-gmbh.github.io/query_kit/>) on a release tag or by hand.

```bash
npm ci
npm start          # http://localhost:3000/query_kit/, hot reload
npm run build      # what CI runs
npm run serve      # serve the built output
```

## Live demos

A doc page embeds one of the example apps, running in the browser against its
in-memory backend, with

```mdx
<LiveDemo feature="optimistic-updates" />
<LiveDemo app="task_manager" height={720} />
```

— registered for every page in `src/theme/MDXComponents.tsx`, no import. It
shows a placeholder and creates the iframe only on a click (about 3 MB), with
"Open full screen" and "View source" links. `feature` is a showcase route id;
the list is `src/components/LiveDemo/showcase-features.json`, which the
showcase's `test/demo_mode_test.dart` keeps equal to its `lib/routes.dart`, and
`npm run build` fails on an id that is not in it
(`scripts/check-live-demos.mjs`).

The demos themselves are Flutter web builds, and they are not committed:

```bash
npm run demos      # tool/build_demos.sh: both apps into static/demo/ (needs Flutter)
```

Run it before `npm start` or `npm run build` to see them. Without it the site
still builds, and a demo's placeholder says the build is missing. The base
href comes from `baseUrl` in `docusaurus.config.ts`. CI builds the demos
before the site, and the `website-e2e` job runs `e2e/` — Playwright over the
built site: the demo on a page, and every showcase feature at its embed URL.

```bash
npm run demos && npm run build
cd e2e && npm ci && npx playwright install chromium && npx playwright test
```

`onBrokenLinks` and `onBrokenMarkdownLinks` are both `throw`, so a link that
points at a page that does not exist fails `npm run build`. That is the point
of building it in CI.

## Conventions

- **The package name reaches this directory through
  `tool/rename_packages.dart`.** The name is settled — `query_kit` — but it is
  still that one pass that would move it, this directory included, so do not
  write it in a way the pass cannot find.
- **Every Dart sample appears in `examples/doc_snippets/`**, compiled and
  analyzed at `--fatal-infos` in CI — and **a test checks that it still
  matches the page**, which nothing did until
  [#72](https://github.com/dualmeta-gmbh/query_kit/issues/72). A twin marks the
  region a page shows, and the fence names it:

  ```dart
  // >>> guides/render-optimizations.md#select-counts
  select: (tasks) => tasks.where((s) => s.done).length,
  // <<<
  ```

  ````md
  ```dart snippet="guides/render-optimizations.md#select-counts"
  ````

  The id rides on the fence's metastring rather than a nearby HTML comment,
  because an editor can move a comment away from its fence and cannot move an
  attribute off it. Docusaurus passes unknown metastring keys through, so it
  changes nothing about rendering. A fence that shows two declarations names
  both, separated by whitespace, and they are compared with a blank line
  between.

  Three forms, and `examples/doc_snippets/test/site_fences_test.dart` keeps
  them honest:

  | | what is checked |
  |---|---|
  | `snippet="<id>"` | **exact**, character for character, once the block's own indentation is out of the way — plus one allowance: the twin's last line may carry the trailing `;` or `,` that makes it a statement where the page shows an expression |
  | `snippet="excerpt: <id>"` | the id resolves, so the sample is anchored to code that compiles; the lines are not compared, and the fence **must** show a `…` — which is what stops `excerpt:` becoming a way to silence a real drift |
  | `snippet="prose-only: <reason>"` | no twin, and the reason is recorded rather than remembered. Every current one is a third-party package (`dio`, `connectivity_plus`, `signals_flutter`) that neither published package may depend on |

  It stands at **39 exact, 6 excerpts, 5 prose-only** across 50 fences and 13
  pages, against 48 marked regions (counted before the release-1.0 docs pass;
  the two package READMEs are held to the same rule, as pages named by their
  repository path). Writing the check is what found that the
  old claim — *"a sample and its twin are kept identical"* — was never true of
  about a third of them, and should not have been: a page introducing
  `QueryBuilder` shows `builder: (context, result) => switch (result) { /* … */ }`
  on purpose, and spelling the switch out to satisfy a checker would make the
  page worse.

  Two things the same pass turned up, both fixed rather than declared
  excerpts: `the-query-client.md` called an `api.get` that does not exist, and
  `mutations.md` showed a closure this repository's own lints reject
  (`unnecessary_lambdas`). Neither would have been caught by compiling the
  twins alone.
- **Admonitions put their title in brackets**: `:::note[Title]`, not
  `:::note Title`. The site runs with Docusaurus's v4 flags, which drop the
  MDX 1 form, and a page using it renders the `:::` line as a paragraph.
- **Numbers are measured, not remembered.** The test counts on the landing
  page and in `docs/project/fidelity.md` come from actual runs. If you cannot
  re-measure one, do not restate it.
- Content that also exists in the repository — the migration guide, the
  feature matrix — is derived from those files rather than reinvented, so the
  two do not drift into disagreeing.

## `npm audit`

`npm audit` reports 26 advisories (8 moderate, 18 high) on a clean `npm ci` at
Docusaurus 3.10.2, and that is the state this repository accepts for now —
decided in [C30](https://github.com/dualmeta-gmbh/query_kit/issues/44) and
re-checked on 2026-09-12. What was checked:

- Every one of them is transitive and belongs to the **build** toolchain —
  `image-size` through `@docusaurus/mdx-loader`, `webpack-dev-server` →
  `sockjs` → `uuid`, `css-minimizer-webpack-plugin` → `serialize-javascript`.
  None of it is shipped: `npm run build` emits static HTML, CSS and JS, and
  nothing in `build/` is any of these packages. The dev server is a localhost
  tool.
- `npm audit fix` changes nothing (`up to date`): every fixed version is
  outside the range Docusaurus 3.10.2 pins. The remedy is a Docusaurus major
  bump, which is a site-wide migration and a deliberate step of its own — not
  something to slip into a release commit for a site that is built in CI and
  deployed nowhere.

So: re-check this when the site is actually deployed, and treat a Docusaurus
major as the ticket that closes it. An advisory that reaches the *built*
output, or one in a package the published Dart packages depend on, is a
different matter and blocks.

## When it is time to deploy

`npm run demos && npm run build` produces a static `build/` directory;
anything that serves files will do. For GitHub Pages, `url` and `baseUrl` in
the config already point at `https://dualmeta-gmbh.github.io/query_kit/` — the
path is the repository's name, written once as a constant at the top of
`docusaurus.config.ts`, so a rename is one edit there — and
`.github/workflows/pages.yml` builds and deploys it on a `query_kit-v*` tag or
by hand. Pages is switched on for the repository (source: GitHub Actions),
so the first such run publishes the site.
