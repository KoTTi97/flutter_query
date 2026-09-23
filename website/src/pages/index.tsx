import Link from '@docusaurus/Link'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import LiveDemo from '@site/src/components/LiveDemo'
import CodeBlock from '@theme/CodeBlock'
import Layout from '@theme/Layout'
import type { ReactNode } from 'react'
import styles from './index.module.css'

// The sample is compiled: it is the region between the `landing:` markers in
// examples/doc_snippets/lib/landing.dart, and
// examples/doc_snippets/test/landing_sample_test.dart fails when the two
// differ by a character. Edit both, or neither.
const sample = `QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks']),
      queryFn: (context) => api.listTasks(signal: context.signal),
    );

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(tasksQuery());

    return switch (tasks) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('Could not load: $error'),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final task in data) Text(task.name),
          ],
        ),
    };
  }
}`

// The project's AI disclosure, in the one wording used everywhere a reader
// can land first (docs/plans/release-1.0-docs, D2).
const aiNotice =
  "query_kit is an entirely AI-coded project: all code, tests and documentation were written by AI coding agents (Anthropic's Claude). A human maintainer set the goals and reviews releases, but did not write the code."

type Feature = { title: string; body: ReactNode; to: string }

const features: Feature[] = [
  {
    title: 'Caching and deduplication',
    body: 'Five widgets reading one key make one request and share its answer.',
    to: '/docs/guides/caching',
  },
  {
    title: 'Stale-while-revalidate',
    body: (
      <>
        A second visit renders from the cache at once, and refetches behind it when the data is older than its{' '}
        <code>staleTime</code>.
      </>
    ),
    to: '/docs/important-defaults',
  },
  {
    title: 'Refetch on focus and reconnect',
    body: 'The app returning to the foreground, or the network returning, refreshes what is on screen.',
    to: '/docs/guides/window-focus-refetching',
  },
  {
    title: 'Mutations and invalidation',
    body: 'A write names the keys it made stale, and whatever shows them fetches again.',
    to: '/docs/guides/invalidations-from-mutations',
  },
  {
    title: 'Optimistic updates',
    body: 'Show the write before the server answers, and roll it back when the server refuses.',
    to: '/docs/guides/optimistic-updates',
  },
  {
    title: 'Infinite and paginated lists',
    body: 'Pages fetched in either direction, kept under one key, refetched in order.',
    to: '/docs/guides/infinite-queries',
  },
  {
    title: 'Retries and cancellation',
    body: (
      <>
        Failed fetches retry with backoff; a fetch whose function reads <code>context.signal</code> is cancelled when
        its last reader leaves.
      </>
    ),
    to: '/docs/guides/query-cancellation',
  },
  {
    title: 'Offline-aware',
    body: 'Told when the device is offline, queries wait for the network instead of failing, and writes made offline pause until it is back.',
    to: '/docs/guides/network-mode',
  },
  {
    title: 'Four equal ways to read',
    body: (
      <>
        <code>context.query</code>, <code>QueryBuilder</code>, <code>QueryMixin</code> or a{' '}
        <code>ValueListenable</code>. None of them is the default.
      </>
    ),
    to: '/docs/guides/reading-queries-in-widgets',
  },
  {
    title: 'Sealed results',
    body: (
      <>
        A <code>switch</code> over <code>QueryPending</code>, <code>QueryError</code> and <code>QuerySuccess</code>{' '}
        is exhaustive, so there is no <code>data!</code>.
      </>
    ),
    to: '/docs/dart-type-safety',
  },
  {
    title: 'A pure-Dart core',
    body: 'The cache runs without Flutter: in a CLI, on a server, in a shared package.',
    to: '/docs/guides/pure-dart',
  },
  {
    title: 'Nothing but Flutter',
    body: (
      <>
        No hooks, signals or connectivity package required. Connectivity is a <code>Stream&lt;bool&gt;</code> you
        bring yourself.
      </>
    ),
    to: '/docs/guides/connectivity',
  },
]

function Arrow(): ReactNode {
  return <span aria-hidden="true">→</span>
}

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext()

  return (
    <Layout title="TanStack Query for Dart and Flutter" description={siteConfig.tagline}>
      <header className={styles.hero}>
        <div className={styles.heroInner}>
          <div className={styles.heroText}>
            <p className={styles.eyebrow}>
              <span>
                <span className={styles.name}>query_kit</span> · for Dart and Flutter
              </span>
            </p>
            <h1 className={styles.title}>Server data in Flutter, cached and kept&nbsp;fresh</h1>
            <p className={styles.subtitle}>
              A port of TanStack Query: queries, mutations and infinite lists for Dart, with a Flutter binding that
              needs nothing but Flutter. You describe where the data comes from; the cache decides when to fetch,
              share, refresh and forget it.
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/docs/quick-start">
                Get started
              </Link>
              <Link className={styles.textAction} to="/docs/examples">
                Examples <Arrow />
              </Link>
              <Link className={styles.textAction} to="/docs/overview">
                Overview <Arrow />
              </Link>
            </div>
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="dart" title="task_list.dart">
              {sample}
            </CodeBlock>
          </div>
        </div>

        <aside className={styles.disclosure} aria-label="About this project">
          <p className={styles.disclosureLabel}>Before you start</p>
          <p className={styles.disclosureText}>{aiNotice}</p>
          <p className={styles.disclosureText}>
            It is a community port of TanStack Query, and not affiliated with or endorsed by TanStack.{' '}
            <Link to="/docs/project/credits">Credits and what that means</Link>.
          </p>
        </aside>
      </header>

      <main>
        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>The problem</h2>
          <div className={styles.problem}>
            <p className={styles.lede}>Server state is not app state.</p>
            <div className={styles.prose}>
              <p>
                A selected tab or a half-typed form is yours: it stays where you left it. The orders on a server are
                not. Someone else can change them, your copy ages while the user reads it, three screens want it at
                once, and the network drops at the worst moment.
              </p>
              <p>
                A <code>FutureBuilder</code> gets the first load on screen. What comes after is the real work —
                caching, sharing one request between readers, refreshing when the app comes back, retrying,
                cancelling, invalidating after a write, paging. query_kit does that work the way TanStack Query does
                it on the web, so a screen only says what it shows.
              </p>
              <p>
                <Link className={styles.textAction} to="/docs/overview">
                  The longer version <Arrow />
                </Link>
              </p>
            </div>
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Try it</h2>
          <div className={styles.demo}>
            <div className={styles.demoIntro}>
              <p className={styles.lede}>A write on screen before the server answers.</p>
              <p className={styles.prose}>
                The showcase's optimistic-updates screen, running in this page against an in-memory backend. Add a
                todo and it is in the list at once. Then switch on <em>Refuse next write</em>, choose{' '}
                <em>Via cache</em> and add another: the row appears, the server refuses it, and the cache rolls back.
              </p>
            </div>
            <LiveDemo feature="optimistic-updates" height={620} />
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>What you get</h2>
          <dl className={styles.features}>
            {features.map((feature) => (
              <div key={feature.title} className={styles.feature}>
                <dt className={styles.featureTitle}>
                  <Link to={feature.to}>{feature.title}</Link>
                </dt>
                <dd className={styles.featureBody}>{feature.body}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Ported, not inspired by</h2>
          <div className={styles.problem}>
            <p className={styles.lede}>Upstream's own tests say it behaves the same.</p>
            <div className={styles.prose}>
              <p>
                TanStack Query's test suite is ported alongside the code, under upstream's own test names, so the two
                files read side by side. Every case that is not ported is listed with its reason, and where the Dart
                port differs on purpose, the differences are written down as behaviour.
              </p>
              <p className={styles.links}>
                <Link className={styles.textAction} to="/docs/project/fidelity">
                  How fidelity is proven <Arrow />
                </Link>
                <Link className={styles.textAction} to="/docs/reference/differences-from-tanstack">
                  Differences from TanStack Query <Arrow />
                </Link>
              </p>
            </div>
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Credits</h2>
          <div className={styles.colophon}>
            <p>
              <strong>Thank you to Tanner Linsley and to everyone who has built and maintained TanStack Query.</strong>{' '}
              Every good idea here is theirs, published under their MIT licence, whose notice each package carries in{' '}
              <code>LICENSE-TANSTACK</code>.
            </p>
            <p>
              <strong>It is not theirs.</strong> Not affiliated with, endorsed by, reviewed by, or connected in any way
              to Tanner Linsley, the TanStack team, or the TanStack organisation. Please do not take problems with this
              package to them —{' '}
              <a href="https://github.com/KoTTi97/flutter_query/issues">they belong here</a>.
            </p>
          </div>
        </section>

        <section className={`${styles.section} ${styles.next}`}>
          <Link className={styles.nextLink} to="/docs/quick-start">
            <span className={styles.nextKicker}>Start</span>
            <span className={styles.nextTitle}>
              Quick start <Arrow />
            </span>
          </Link>
          <Link className={styles.nextLink} to="/docs/examples">
            <span className={styles.nextKicker}>Browse</span>
            <span className={styles.nextTitle}>
              Examples <Arrow />
            </span>
          </Link>
          <Link className={styles.nextLink} to="/docs/overview">
            <span className={styles.nextKicker}>Read</span>
            <span className={styles.nextTitle}>
              Overview <Arrow />
            </span>
          </Link>
        </section>
      </main>
    </Layout>
  )
}
