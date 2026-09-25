import type * as Preset from '@docusaurus/preset-classic'
import type { Config } from '@docusaurus/types'
import { themes as prismThemes } from 'prism-react-renderer'
import { execSync } from 'node:child_process'
import dartSource from './plugins/dart-source'

// Nothing is deployed yet. The url/baseUrl below are the GitHub Pages
// coordinates the repository would use, so that `onBrokenLinks: 'throw'` has
// something real to check against rather than a placeholder.
//
// The path is the repository's name. It is written once, here, and the
// Pages project name and every hard-coded link that `baseUrl` does not reach
// (the announcement bar is raw HTML) are built from it, so renaming the
// repository is one edit here (plus its GitHub URLs).
const repository = 'query_kit'
const baseUrl = `/${repository}/`

// The project's AI disclosure, in the one wording used everywhere a reader
// can land first.
const aiNotice =
  "query_kit is an entirely AI-coded project: all code, tests and documentation were written by AI coding agents (Anthropic's Claude). A human maintainer set the goals and reviews releases, but did not write the code."

// The commit the site is built from. `<DartSource>` links an excerpt to its
// lines on GitHub at this commit, not at `main`, where later edits would move
// them. CI names it; a local build asks git; outside a checkout, `main`.
function sourceRevision(): string {
  if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA
  try {
    return execSync('git rev-parse HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return 'main'
  }
}

const config: Config = {
  title: 'query_kit',
  tagline: 'TanStack Query for Dart and Flutter, ported test for test',
  favicon: 'img/favicon.svg',

  url: 'https://dualmeta-gmbh.github.io',
  baseUrl,
  organizationName: 'dualmeta-gmbh',
  projectName: repository,
  trailingSlash: false,

  // A link to a page that does not exist fails the build, and so does a
  // link to a heading that does not exist. That is the point of building the
  // site in CI.
  onBrokenLinks: 'throw',
  onBrokenAnchors: 'throw',
  markdown: { hooks: { onBrokenMarkdownLinks: 'throw' } },

  future: { v4: true, faster: true },

  customFields: { sourceRevision: sourceRevision() },

  // Geist and Geist Mono. `custom.css` falls back to the system stack,
  // so a blocked or slow font request costs the face and nothing else — and
  // the build never reaches for the network, only the rendered page does.
  headTags: [
    {
      tagName: 'link',
      attributes: { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
    },
    {
      tagName: 'link',
      attributes: {
        rel: 'preconnect',
        href: 'https://fonts.gstatic.com',
        crossorigin: 'anonymous',
      },
    },
  ],
  stylesheets: [
    'https://fonts.googleapis.com/css2?family=Geist:wght@400..700&family=Geist+Mono:wght@400..600&display=swap',
  ],

  i18n: { defaultLocale: 'en', locales: ['en'] },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/docs',
          editUrl: 'https://github.com/dualmeta-gmbh/query_kit/tree/main/website/',
          showLastUpdateTime: false,
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      } satisfies Preset.Options,
    ],
  ],

  // No page lives at `/docs` itself; a reader who trims a docs URL back to
  // it lands on the overview rather than a 404.
  plugins: [
    // `.dart` files importable as strings: the examples pages show the
    // compiled source itself (`src/components/DartSource`).
    dartSource,
    [
      '@docusaurus/plugin-client-redirects',
      { redirects: [{ from: '/docs', to: '/docs/overview' }] },
    ],
  ],

  themeConfig: {
    colorMode: { respectPrefersColorScheme: true },
    // Always on, not dismissible: two things about this project should reach
    // a reader before anything else does. Its colours are in `custom.css`,
    // because `backgroundColor` here lands as an inline style that no
    // stylesheet — and so no dark-mode rule — can override.
    announcementBar: {
      id: 'unaffiliated-and-ai-coded',
      content: `${aiNotice} It is a community port of TanStack Query, <b>not affiliated with or endorsed by TanStack</b>. <a href="${baseUrl}docs/project/credits">What that means</a>.`,
      isCloseable: false,
    },
    navbar: {
      title: 'query_kit',
      logo: { alt: '', src: 'img/logo.svg', width: 26, height: 26 },
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { to: '/docs/coming-from-react-query', position: 'left', label: 'From React Query' },
        { to: '/docs/examples', position: 'left', label: 'Examples' },
        { to: '/docs/project/fidelity', position: 'left', label: 'Fidelity' },
        { to: '/docs/project/credits', position: 'left', label: 'Credits' },
        {
          href: 'https://github.com/dualmeta-gmbh/query_kit',
          position: 'right',
          className: 'header-github-link',
          'aria-label': 'GitHub repository',
        },
      ],
    },
    footer: {
      style: 'light',
      links: [
        {
          title: 'Docs',
          items: [
            { label: 'Installation', to: '/docs/installation' },
            { label: 'Quick start', to: '/docs/quick-start' },
            { label: 'Four ways to read a query', to: '/docs/guides/reading-queries-in-widgets' },
            { label: 'Feature matrix', to: '/docs/reference/feature-matrix' },
          ],
        },
        {
          title: 'Project',
          items: [
            { label: 'Credits, and what this is not', to: '/docs/project/credits' },
            { label: 'How fidelity is proven', to: '/docs/project/fidelity' },
            { label: 'How the examples are built', to: '/docs/project/examples' },
            { label: 'Contributing', href: 'https://github.com/dualmeta-gmbh/query_kit/blob/main/CONTRIBUTING.md' },
            { label: 'Porting notes', href: 'https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md' },
          ],
        },
        {
          title: 'Elsewhere',
          items: [
            { label: 'GitHub', href: 'https://github.com/dualmeta-gmbh/query_kit' },
            { label: 'TanStack Query', href: 'https://tanstack.com/query' },
          ],
        },
      ],
      copyright: `${aiNotice} A port of TanStack Query, published with thanks under its MIT licence. Not affiliated with, endorsed by, or connected to Tanner Linsley, the TanStack team or the TanStack organisation.`,
    },
    prism: {
      theme: prismThemes.github,
      // oneDark over dracula: dracula's pinks and purples are louder than
      // anything else on the page.
      darkTheme: prismThemes.oneDark,
      additionalLanguages: ['dart', 'bash', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
}

export default config
