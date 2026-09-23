import type { SidebarsConfig } from '@docusaurus/plugin-content-docs'

const sidebars: SidebarsConfig = {
  docs: [
    {
      type: 'category',
      label: 'Getting started',
      collapsed: false,
      items: [
        'overview',
        'installation',
        'quick-start',
        'important-defaults',
        'coming-from-react-query',
        'dart-type-safety',
      ],
    },
    {
      type: 'category',
      label: 'Guides & concepts',
      collapsed: false,
      items: [
        {
          type: 'category',
          label: 'Queries',
          items: [
            'guides/queries',
            'guides/reading-queries-in-widgets',
            'guides/query-keys',
            'guides/query-functions',
            'guides/query-options',
            'guides/parallel-queries',
            'guides/combining-queries',
            'guides/dependent-queries',
            'guides/disabling-queries',
            'guides/side-effects',
          ],
        },
        {
          type: 'category',
          label: 'Refetching and the network',
          items: [
            'guides/background-fetching-indicators',
            'guides/window-focus-refetching',
            'guides/network-mode',
            'guides/connectivity',
            'guides/polling',
            'guides/query-retries',
            'guides/query-cancellation',
          ],
        },
        {
          type: 'category',
          label: 'Paging and early data',
          items: [
            'guides/paginated-queries',
            'guides/infinite-queries',
            'guides/initial-query-data',
            'guides/placeholder-query-data',
            'guides/scroll-restoration',
          ],
        },
        {
          type: 'category',
          label: 'Mutations',
          items: [
            'guides/mutations',
            'guides/query-invalidation',
            'guides/invalidations-from-mutations',
            'guides/updates-from-mutation-responses',
            'guides/optimistic-updates',
            'guides/mutation-scopes',
            'guides/cancelling-mutations',
            'guides/mutation-state',
          ],
        },
        {
          type: 'category',
          label: 'The cache and performance',
          items: [
            'guides/filters',
            'guides/request-waterfalls',
            'guides/prefetching',
            'guides/caching',
            'guides/render-optimizations',
            'guides/structural-sharing',
            'guides/default-query-function',
            'guides/global-callbacks',
          ],
        },
        {
          type: 'category',
          label: 'Tools and architecture',
          items: [
            'guides/debugging',
            'guides/testing',
            'guides/pure-dart',
            'guides/does-this-replace-state-management',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Examples',
      items: ['examples/index'],
    },
    {
      type: 'category',
      label: 'Cookbook',
      items: ['cookbook/index'],
    },
    {
      type: 'category',
      label: 'API reference',
      items: [
        'reference/api',
        'reference/feature-matrix',
        'reference/troubleshooting',
        'reference/differences-from-tanstack',
      ],
    },
    {
      type: 'category',
      label: 'Project',
      items: ['project/credits', 'project/fidelity', 'project/examples'],
    },
  ],
}

export default sidebars
