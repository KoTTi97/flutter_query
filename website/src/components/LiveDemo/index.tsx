import useBaseUrl from '@docusaurus/useBaseUrl'
import useIsBrowser from '@docusaurus/useIsBrowser'
import { useColorMode } from '@docusaurus/theme-common'
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react'
import showcaseFeatures from './showcase-features.json'
import styles from './styles.module.css'

/**
 * A live demo: one of the example apps, built for the web against its
 * in-memory backend (`tool/build_demos.sh`, `npm run demos`), in a frame.
 *
 * Nothing is downloaded until the reader asks: the placeholder is static, and
 * the iframe — some 3 MB of Flutter engine and app — is created on the click.
 *
 * ```mdx
 * <LiveDemo feature="optimistic-updates" />
 * <LiveDemo app="task_manager" height={720} />
 * ```
 *
 * `feature` is a showcase route id (`examples/showcase/lib/routes.dart`);
 * `showcase-features.json` is the site's copy of that list, which the
 * showcase's `test/demo_mode_test.dart` keeps equal to it, and
 * `scripts/check-live-demos.mjs` fails the build on an id that is not in it.
 */

export type LiveDemoApp = 'showcase' | 'task_manager'

export type LiveDemoProps = {
  /** The showcase feature to open, by its route id: `optimistic-updates`. */
  feature?: string
  app?: LiveDemoApp
  /** The frame's height in CSS pixels. Capped at 85% of the viewport. */
  height?: number
}

type ShowcaseFeature = { id: string; title: string; summary: string }

const repository = 'https://github.com/KoTTi97/flutter_query/tree/main/examples'

const taskManager = {
  title: 'Task manager',
  summary: 'One small app on query_kit: optimistic writes, rollback, a poll that stops, one cache entry read by two screens.',
}

/** What the placeholder says, where the frame points and where the code is. */
function describe(app: LiveDemoApp, feature: string | undefined) {
  if (app === 'task_manager') {
    return { ...taskManager, route: '', source: `${repository}/task_manager/lib` }
  }
  const entry = (showcaseFeatures as ShowcaseFeature[]).find((candidate) => candidate.id === feature)
  if (entry === undefined) {
    return undefined
  }
  return {
    title: entry.title,
    summary: entry.summary,
    route: `#/${entry.id}`,
    source: `${repository}/showcase/lib/features/${entry.id.replaceAll('-', '_')}`,
  }
}

type Phase = 'idle' | 'checking' | 'missing' | 'loading' | 'running'

export default function LiveDemo({ feature, app = 'showcase', height = 640 }: LiveDemoProps): ReactNode {
  const [phase, setPhase] = useState<Phase>('idle')
  const frame = useRef<HTMLIFrameElement>(null)
  const fallback = useRef<number | undefined>(undefined)
  useEffect(() => () => window.clearTimeout(fallback.current), [])
  // The demo takes the site's colour scheme from its URL (`?theme=`), once,
  // at boot. A toggle while it runs therefore restarts it in the new scheme:
  // the frame is keyed on the mode, and the overlay covers the restart.
  const { colorMode } = useColorMode()
  const isBrowser = useIsBrowser()
  const shownMode = useRef(colorMode)
  useEffect(() => {
    if (shownMode.current === colorMode) {
      return
    }
    shownMode.current = colorMode
    window.clearTimeout(fallback.current)
    setPhase((current) => (current === 'running' ? 'loading' : current))
  }, [colorMode])
  const root = useBaseUrl(`/demo/${app}/`)
  const demo = describe(app, feature)

  if (demo === undefined) {
    return (
      <div className={styles.frame} role="note">
        <p className={styles.error}>
          <code>{`<LiveDemo feature="${feature ?? ''}" />`}</code> names no showcase feature. The ids are
          the routes in <code>examples/showcase/lib/routes.dart</code>.
        </p>
      </div>
    )
  }

  // The query string sits before the hash, so the app reads it however it
  // navigates. `semantics=1` switches Flutter's semantics tree on: a screen
  // reader can use the demo, and so can the site's end-to-end suite.
  // `theme` is the site's own light or dark mode, which the app follows.
  const embedded = `${root}?embed=1&semantics=1&theme=${colorMode}${demo.route}`
  // The server renders without knowing the reader's mode, so the link gains
  // its `theme` once the page runs in a browser rather than hydrating a guess.
  const fullScreen = isBrowser ? `${root}?theme=${colorMode}${demo.route}` : `${root}${demo.route}`
  const frameTitle = `Live demo: ${demo.title}`

  // `version.json` is written by every Flutter web build and names the app;
  // asking for it first turns "the demos were not built" into a sentence
  // rather than a 404 page inside the frame.
  async function run() {
    setPhase('checking')
    try {
      const response = await fetch(`${root}version.json`, { cache: 'no-store' })
      const version = response.ok ? await response.json() : undefined
      setPhase(version?.app_name === app ? 'loading' : 'missing')
    } catch {
      setPhase('missing')
    }
  }

  // The frame's `load` comes before Flutter has painted anything — the engine
  // and CanvasKit are still on their way — so the overlay stays until the app
  // announces its first frame (`flutter-first-frame`, dispatched on the
  // frame's window; same origin, so it can be heard). A frame that has
  // already painted (its semantics tree is there, `semantics=1`) or cannot be
  // read shows at once, and a timeout keeps a silent one from hiding forever.
  function onFrameLoad() {
    const show = () => {
      window.clearTimeout(fallback.current)
      setPhase('running')
    }
    try {
      const win = frame.current?.contentWindow
      if (win == null || win.document.querySelector('flt-semantics') !== null) {
        show()
        return
      }
      win.addEventListener('flutter-first-frame', show, { once: true })
      fallback.current = window.setTimeout(show, 15_000)
    } catch {
      show()
    }
  }

  const style = { '--live-demo-height': `${height}px` } as CSSProperties
  const started = phase === 'loading' || phase === 'running'

  return (
    <figure className={styles.demo} style={style}>
      <div className={styles.frame}>
        {started ? (
          <>
            <iframe
              key={colorMode}
              ref={frame}
              className={styles.iframe}
              src={embedded}
              title={frameTitle}
              allow="clipboard-write"
              onLoad={onFrameLoad}
            />
            {phase === 'loading' && (
              <div className={styles.overlay} role="status">
                Starting Flutter…
              </div>
            )}
          </>
        ) : (
          <div className={styles.placeholder}>
            <span className={styles.kicker}>Live demo</span>
            <strong className={styles.title}>{demo.title}</strong>
            <span className={styles.summary}>{demo.summary}</span>
            {phase === 'missing' ? (
              <p className={styles.error} role="status">
                The demo is not built into this copy of the site. Run <code>npm run demos</code> in{' '}
                <code>website/</code> (it needs Flutter), then reload.
              </p>
            ) : (
              <button
                type="button"
                className="button button--primary"
                onClick={run}
                disabled={phase === 'checking'}
              >
                Run live demo
              </button>
            )}
            <span className={styles.note}>~3 MB, runs in your browser; no server involved.</span>
          </div>
        )}
      </div>
      <figcaption className={styles.links}>
        <a href={fullScreen} target="_blank" rel="noopener">
          Open full screen ↗
        </a>
        <a href={demo.source} target="_blank" rel="noopener noreferrer">
          View source ↗
        </a>
      </figcaption>
    </figure>
  )
}
