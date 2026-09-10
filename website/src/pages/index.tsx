import Link from '@docusaurus/Link'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import CodeBlock from '@theme/CodeBlock'
import Layout from '@theme/Layout'
import type { ReactNode } from 'react'
import styles from './index.module.css'

const sample = `class SensorScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id));

    return switch (sensor) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => SensorCard(data),
      QueryError(:final error, :final staleData) => ErrorBanner(error, staleData),
    };
  }
}`

const numbers = [
  { value: '549', label: 'core tests, on the VM and compiled to JavaScript' },
  { value: '84', label: 'widget tests in the binding' },
  { value: '369', label: 'tests across the two example apps' },
  { value: '155', label: 'end-to-end tests in a real browser' },
]

const points = [
  {
    title: 'Ported, not inspired by',
    body: (
      <>
        Upstream's own suite runs against this port, case for case, keeping
        upstream's test names so the two files diff against each other. Every
        case that is <em>not</em> ported is listed by name, with its reason.
        Porting found 22 bugs no Dart-side test would have caught.
      </>
    ),
    to: '/docs/project/fidelity',
    cta: 'How that is proven',
  },
  {
    title: 'Four equal ways to read a query',
    body: (
      <>
        <code>context.query</code>, <code>QueryBuilder</code>,{' '}
        <code>QueryMixin</code> and a plain <code>ValueListenable</code>. They
        are layered, not competing, and they interoperate inside one screen.
        The documentation names no default — that was a deliberate ruling.
      </>
    ),
    to: '/docs/guides/reading-a-query',
    cta: 'See all four',
  },
  {
    title: 'Nothing but Flutter',
    body: (
      <>
        No <code>flutter_hooks</code>, no signals package, no{' '}
        <code>connectivity_plus</code>. You should not have to adopt somebody's
        state management to use a cache. Connectivity is a{' '}
        <code>Stream&lt;bool&gt;</code> you bring yourself, and it stays your
        dependency.
      </>
    ),
    to: '/docs/guides/lifecycle-and-connectivity',
    cta: 'Lifecycle and connectivity',
  },
  {
    title: 'Dart shapes, not JavaScript ones',
    body: (
      <>
        A sealed <code>QueryResult</code>, so a <code>switch</code> is
        exhaustive and there is no <code>data!</code>. Sealed option values, so{' '}
        <code>null</code> can mean "unset" everywhere. A <code>QueryKey</code>{' '}
        that is a value type. One key, one exact type.
      </>
    ),
    to: '/docs/reference/coming-from-react-query',
    cta: 'The full name map',
  },
]

export default function Home(): ReactNode {
  const { siteConfig } = useDocusaurusContext()

  return (
    <Layout
      title="TanStack Query for Dart and Flutter"
      description={siteConfig.tagline}
    >
      <header className={styles.hero}>
        <div className={styles.heroInner}>
          <div className={styles.heroText}>
            <p className={styles.eyebrow}>An independent community port</p>
            <h1 className={styles.title}>
              TanStack Query for Dart and&nbsp;Flutter
            </h1>
            <p className={styles.subtitle}>
              A port of <code>query-core</code> with a Flutter binding on top —
              and upstream's own test suite ported alongside it, so the subtle
              things behave the way people who know the library expect.
            </p>
            <div className={styles.buttons}>
              <Link className="button button--primary button--lg" to="/docs/getting-started/first-query">
                Your first query
              </Link>
              <Link className="button button--secondary button--lg" to="/docs/">
                What this is
              </Link>
            </div>
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="dart">{sample}</CodeBlock>
          </div>
        </div>
      </header>

      <main>
        <section className={styles.numbers}>
          {numbers.map((entry) => (
            <div key={entry.label} className={styles.number}>
              <span className={styles.numberValue}>{entry.value}</span>
              <span className={styles.numberLabel}>{entry.label}</span>
            </div>
          ))}
        </section>

        <section className={styles.points}>
          {points.map((point) => (
            <article key={point.title} className={styles.point}>
              <h2>{point.title}</h2>
              <p>{point.body}</p>
              <Link to={point.to}>{point.cta} →</Link>
            </article>
          ))}
        </section>

        <section className={styles.closing}>
          <h2>Not affiliated with TanStack</h2>
          <p>
            This is an independent community port — not affiliated with,
            endorsed by, or a product of TanStack. It is published under
            upstream's MIT licence, whose notice each package carries in{' '}
            <code>LICENSE-TANSTACK</code>. The package name here is a{' '}
            <Link to="/docs/project/releasing">codename</Link>: a name on
            pub.dev is permanent, so it is the last decision, not the first.
          </p>
        </section>
      </main>
    </Layout>
  )
}
