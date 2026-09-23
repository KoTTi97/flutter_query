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
    // The same groups, in the same order, as the gallery on the index page
    // (`docs/examples/index.md`).
    {
      type: 'category',
      label: 'Examples',
      className: 'qk-sidebar-heading',
      link: { type: 'doc', id: 'examples/index' },
      items: [
        'examples/task-manager',
        'examples/one-file-tour',
        {
          type: 'category',
          label: 'Basics',
          items: [
            'examples/simple',
            'examples/basic',
            'examples/four-call-styles',
          ],
        },
        {
          type: 'category',
          label: 'Queries',
          items: [
            'examples/default-query-function',
            'examples/dependent-queries',
            'examples/parallel-queries',
            'examples/query-collections',
            'examples/combine',
            'examples/initial-and-placeholder',
            'examples/select-and-sharing',
          ],
        },
        {
          type: 'category',
          label: 'Paging',
          items: [
            'examples/pagination',
            'examples/load-more',
            'examples/max-pages',
          ],
        },
        {
          type: 'category',
          label: 'Mutations',
          items: [
            'examples/mutations',
            'examples/optimistic-updates',
            'examples/mutation-cancel',
            'examples/mutation-state',
          ],
        },
        {
          type: 'category',
          label: 'Cache',
          items: [
            'examples/prefetching',
            'examples/stale-and-gc',
            'examples/invalidation-and-filters',
            'examples/playground',
            'examples/cache-inspector',
          ],
        },
        {
          type: 'category',
          label: 'Network',
          items: [
            'examples/auto-refetching',
            'examples/retry',
            'examples/cancellation',
            'examples/offline',
            'examples/focus-refetch',
          ],
        },
        {
          type: 'category',
          label: 'Advanced',
          items: [
            'examples/build-when',
            'examples/global-callbacks',
            'examples/diagnostics',
          ],
        },
      ],
    },
    // One page for now; the chunks that add its pages list them here, and
    // the page itself stays the category's landing page.
    {
      type: 'category',
      label: 'Cookbook',
      className: 'qk-sidebar-heading',
      link: { type: 'doc', id: 'cookbook/index' },
      items: [],
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
