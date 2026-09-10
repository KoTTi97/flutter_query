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

- **The package name is a codename.** `docusaurus.config.ts` names it once at
  the top, and `tool/rename_packages.dart` rewrites everything else, this
  directory included. Do not work around it.
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

## When it is time to deploy

`npm run build` produces a static `build/` directory; anything that serves
files will do. For GitHub Pages, `url` and `baseUrl` in the config already
point at `https://kotti97.github.io/flutter_query/`, and Docusaurus ships a
`deploy` script. Adding the workflow is a deliberate step, not a side effect
of merging this.
