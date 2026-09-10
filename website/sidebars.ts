import type { SidebarsConfig } from '@docusaurus/plugin-content-docs'

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Getting started',
      collapsed: false,
      items: ['getting-started/installation', 'getting-started/first-query'],
    },
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'guides/reading-a-query',
        'guides/options',
        'guides/rebuilds',
        'guides/mutations',
        'guides/infinite-queries',
        'guides/the-query-client',
        'guides/collections-and-side-effects',
        'guides/lifecycle-and-connectivity',
        'guides/testing',
        'guides/pure-dart',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      items: [
        'reference/coming-from-react-query',
        'reference/feature-matrix',
        'reference/api',
      ],
    },
    {
      type: 'category',
      label: 'Project',
      items: ['project/fidelity', 'project/examples', 'project/releasing'],
    },
  ],
}

export default sidebars
