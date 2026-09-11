# The documentation site

[Docusaurus 3](https://docusaurus.io). The prose lives in `docs/`, the landing
page in `src/pages/`. Nothing here is deployed — the site is built in CI so a
broken link or a failing build is caught, and where it goes is the
maintainer's call.

```bash
npm ci
npm start          # http://localhost:3000/flutter_query/, hot reload
npm run build      # what CI runs
npm run serve      # serve the built output
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
  analyzed at `--fatal-infos` in CI, under a comment naming the page it is on.
  A sample and its twin are kept identical; that is the only reason to trust
  either. The exceptions are the samples that need a third-party package
  (`dio`, `connectivity_plus`, `signals_flutter`) — neither published package
  may depend on one, so those stay prose-only.
- **Numbers are measured, not remembered.** The test counts on the landing
  page and in `docs/project/fidelity.md` come from actual runs. If you cannot
  re-measure one, do not restate it.
- Content that also exists in the repository — the migration guide, the
  feature matrix — is derived from those files rather than reinvented, so the
  two do not drift into disagreeing.

## `npm audit`

`npm audit` reports 26 advisories (8 moderate, 18 high) on a clean `npm ci` at
Docusaurus 3.10.2, and that is the state this repository accepts for now —
decided in [C30](https://github.com/KoTTi97/flutter_query/issues/44) and
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

`npm run build` produces a static `build/` directory; anything that serves
files will do. For GitHub Pages, `url` and `baseUrl` in the config already
point at `https://kotti97.github.io/flutter_query/`, and Docusaurus ships a
`deploy` script. Adding the workflow is a deliberate step, not a side effect
of merging this.
