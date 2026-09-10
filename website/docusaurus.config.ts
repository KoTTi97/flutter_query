import type * as Preset from '@docusaurus/preset-classic'
import type { Config } from '@docusaurus/types'
import { themes as prismThemes } from 'prism-react-renderer'

// `query_kit` is a codename — the published name is decided right before the
// first `dart pub publish`, because a pub.dev name is permanent, and
// `tool/rename_packages.dart` rewrites it here along with everywhere else.
//
// Nothing is deployed yet. The url/baseUrl below are the GitHub Pages
// coordinates the repository would use, so that `onBrokenLinks: 'throw'` has
// something real to check against rather than a placeholder.
const config: Config = {
  title: 'query_kit',
  tagline: 'TanStack Query for Dart and Flutter, ported test for test',
  favicon: 'img/favicon.svg',

  url: 'https://kotti97.github.io',
  baseUrl: '/flutter_query/',
  organizationName: 'KoTTi97',
  projectName: 'flutter_query',
  trailingSlash: false,

  // A link to a page that does not exist fails the build. That is the point
  // of building the site in CI.
  onBrokenLinks: 'throw',
  markdown: { hooks: { onBrokenMarkdownLinks: 'throw' } },

  future: { v4: true, faster: true },

  i18n: { defaultLocale: 'en', locales: ['en'] },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: '/docs',
          editUrl: 'https://github.com/KoTTi97/flutter_query/tree/main/website/',
          showLastUpdateTime: false,
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    colorMode: { respectPrefersColorScheme: true },
    // Always on, not dismissible: two things about this project should reach
    // a reader before anything else does.
    announcementBar: {
      id: 'unaffiliated-and-ai-written',
      content:
        'A community <b>port of TanStack Query</b>, published with thanks — <b>not affiliated with or endorsed by TanStack</b>, and <b>written by AI</b>. <a href="/flutter_query/docs/project/credits">What that means</a>.',
      backgroundColor: '#0b6bcb',
      textColor: '#ffffff',
      isCloseable: false,
    },
    navbar: {
      title: 'query_kit',
      logo: { alt: '', src: 'img/logo.svg', width: 26, height: 26 },
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { to: '/docs/reference/coming-from-react-query', position: 'left', label: 'From React Query' },
        { to: '/docs/project/fidelity', position: 'left', label: 'Fidelity' },
        { to: '/docs/project/credits', position: 'left', label: 'Credits' },
        {
          href: 'https://github.com/KoTTi97/flutter_query',
          position: 'right',
          className: 'header-github-link',
          'aria-label': 'GitHub repository',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            { label: 'Installation', to: '/docs/getting-started/installation' },
            { label: 'Your first query', to: '/docs/getting-started/first-query' },
            { label: 'Reading a query', to: '/docs/guides/reading-a-query' },
            { label: 'Feature matrix', to: '/docs/reference/feature-matrix' },
          ],
        },
        {
          title: 'Project',
          items: [
            { label: 'Credits, and what this is not', to: '/docs/project/credits' },
            { label: 'How fidelity is proven', to: '/docs/project/fidelity' },
            { label: 'Examples', to: '/docs/project/examples' },
            { label: 'Contributing', href: 'https://github.com/KoTTi97/flutter_query/blob/main/CONTRIBUTING.md' },
            { label: 'Porting notes', href: 'https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md' },
          ],
        },
        {
          title: 'Elsewhere',
          items: [
            { label: 'GitHub', href: 'https://github.com/KoTTi97/flutter_query' },
            { label: 'TanStack Query', href: 'https://tanstack.com/query' },
          ],
        },
      ],
      copyright:
        'A port of TanStack Query, published with thanks under its MIT licence. Not affiliated with, endorsed by, or connected to Tanner Linsley, the TanStack team or the TanStack organisation. Written by AI.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart', 'bash', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
}

export default config
