import Link from '@docusaurus/Link'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import CodeBlock from '@theme/CodeBlock'
import Layout from '@theme/Layout'
import type { ReactNode } from 'react'
import styles from './index.module.css'

const sample = `class TaskScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final task = context.query(taskQuery(id));

    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => TaskCard(data),
      QueryError(:final error, :final staleData) =>
        ErrorBanner(error, staleData),
    };
  }
}`

// Measured, not remembered (see website/README.md): these come from an actual
// run of every suite, 2026-09-12. `dart test` in packages/query_kit, then
// `flutter test` in packages/query_kit_flutter, examples/showcase and
// examples/task_manager, then `npx playwright test` in each example's e2e/.
const figures = [
  { value: '741', label: 'core VM tests; 737 also run compiled to JavaScript' },
  { value: '128', label: 'widget tests in the binding' },
  { value: '270', label: 'tests across the two example apps' },
  { value: '179', label: 'end-to-end tests in a real browser' },
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
            <p className={styles.eyebrow}>
              A port of TanStack Query · unaffiliated · written by AI
            </p>
            <h1 className={styles.title}>
              TanStack Query for Dart and&nbsp;Flutter
            </h1>
            <p className={styles.subtitle}>
              A port of <code>query-core</code> with a Flutter binding on top —
              and upstream's own test suite ported alongside it, so the subtle
              things behave the way people who know the library expect.
            </p>
            <div className={styles.actions}>
              <Link
                className="button button--primary button--lg"
                to="/docs/getting-started/first-query"
              >
                Your first query
              </Link>
              <Link className={styles.textAction} to="/docs/">
                What this is <span aria-hidden="true">→</span>
              </Link>
            </div>
          </div>
          <div className={styles.heroCode}>
            <CodeBlock language="dart" title="task_screen.dart">
              {sample}
            </CodeBlock>
          </div>
        </div>
      </header>

      <main>
        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Checkable, not claimed</h2>
          <dl className={styles.figures}>
            {figures.map((figure) => (
              <div key={figure.label} className={styles.figure}>
                <dt className={styles.figureValue}>{figure.value}</dt>
                <dd className={styles.figureLabel}>{figure.label}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>What it is, in four points</h2>
          <div className={styles.points}>
            {points.map((point, index) => (
              <article key={point.title} className={styles.point}>
                <span className={styles.pointIndex}>
                  {String(index + 1).padStart(2, '0')}
                </span>
                <h3 className={styles.pointTitle}>{point.title}</h3>
                <p className={styles.pointBody}>{point.body}</p>
                <Link className={styles.textAction} to={point.to}>
                  {point.cta} <span aria-hidden="true">→</span>
                </Link>
              </article>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <h2 className={styles.sectionLabel}>Credits, and what this is not</h2>
          <div className={styles.colophon}>
            <p>
              <strong>
                Thank you to Tanner Linsley and to everyone who has built and
                maintained TanStack Query.
              </strong>{' '}
              This exists for one reason: we used it, we loved it, and we wanted
              the same thing in Flutter. Every good idea here is theirs, and it
              is published under their MIT licence, whose notice each package
              carries in <code>LICENSE-TANSTACK</code>.
            </p>
            <p>
              <strong>It is not theirs.</strong> Not affiliated with, endorsed
              by, reviewed by, or connected in any way to Tanner Linsley, the
              TanStack team, or the TanStack organisation. Please do not take
              problems with this package to them —{' '}
              <a href="https://github.com/KoTTi97/flutter_query/issues">
                they belong here
              </a>
              .
            </p>
            <p>
              <strong>And this is an AI-written project.</strong> Effectively
              all of the code, the tests and this page were written by AI
              agents, with a human in the loop only rarely. What stands in for
              human review is adversarial: upstream's own test suite, nine
              external deep-dive reviews, and a rule that no reported finding is
              acted on before it has been reproduced.
            </p>
            <p>
              <Link className={styles.textAction} to="/docs/project/credits">
                The whole of it <span aria-hidden="true">→</span>
              </Link>
            </p>
          </div>
        </section>
      </main>
    </Layout>
  )
}
