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
    navbar: {
      title: 'query_kit',
      logo: { alt: '', src: 'img/logo.svg', width: 26, height: 26 },
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { to: '/docs/reference/coming-from-react-query', position: 'left', label: 'From React Query' },
        { to: '/docs/project/fidelity', position: 'left', label: 'Fidelity' },
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
        'MIT. An independent community port — not affiliated with, endorsed by, or a product of TanStack.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['dart', 'bash', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
}

export default config
