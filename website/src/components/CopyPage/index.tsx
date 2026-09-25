import Head from '@docusaurus/Head'
import useBaseUrl from '@docusaurus/useBaseUrl'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import { useDoc } from '@docusaurus/plugin-content-docs/client'
import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
import styles from './styles.module.css'

/**
 * A doc page's "Copy page" button, and a menu of the other ways to hand the
 * page to an AI agent: its Markdown, a chat that is asked to read it, and the
 * site's `llms.txt` / `llms-full.txt`.
 *
 * The Markdown is the file `plugins/llms-txt.ts` writes next to the page at
 * build time (`/docs/quick-start` → `/docs/quick-start.md`); the page names
 * it as `<link rel="alternate" type="text/markdown">` too. `npm start` builds
 * none of it, so there the copy says it cannot, rather than copying HTML.
 */

type Status = 'idle' | 'copied' | 'failed'

/** `.menu`'s width in `styles.module.css`, 17rem, in pixels. */
const menuWidth = 272

const icons = {
  copy: (
    <>
      <rect x="9" y="9" width="12" height="12" rx="2" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </>
  ),
  check: <path d="M20 6 9 17l-5-5" />,
  chevron: <path d="m6 9 6 6 6-6" />,
  markdown: (
    <>
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <path d="M14 2v6h6M8 13h8M8 17h5" />
    </>
  ),
  chat: <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />,
  index: <path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01" />,
  external: <path d="M7 17 17 7M8 7h9v9" />,
}

function Icon({ name, className }: { name: keyof typeof icons; className?: string }): ReactNode {
  return (
    <svg
      className={className ?? styles.icon}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true">
      {icons[name]}
    </svg>
  )
}

/** The page's Markdown, or an error when this build has none (`npm start`). */
async function markdown(url: string): Promise<string> {
  const response = await fetch(url)
  const type = response.headers.get('content-type') ?? ''
  if (!response.ok || type.includes('text/html')) {
    throw new Error(`${url} is not built; it is written by \`npm run build\``)
  }
  return response.text()
}

/**
 * Safari allows a clipboard write only inside the click's own task, so the
 * text goes in as a promise the clipboard item waits on; elsewhere, or when
 * that is refused, the fetched text is written plainly.
 */
async function copy(url: string): Promise<void> {
  if (typeof ClipboardItem !== 'undefined' && navigator.clipboard?.write) {
    try {
      const blob = markdown(url).then((text) => new Blob([text], { type: 'text/plain' }))
      await navigator.clipboard.write([new ClipboardItem({ 'text/plain': blob })])
      return
    } catch (error) {
      if (error instanceof Error && error.message.includes('is not built')) throw error
    }
  }
  await navigator.clipboard.writeText(await markdown(url))
}

export default function CopyPage(): ReactNode {
  const { metadata } = useDoc()
  const { siteConfig } = useDocusaurusContext()
  const llmsTxt = useBaseUrl('/llms.txt')
  const llmsFullTxt = useBaseUrl('/llms-full.txt')
  const [status, setStatus] = useState<Status>('idle')
  const [open, setOpen] = useState(false)
  // The menu opens under the button's right edge, or its left edge when the
  // button is too near the left to fit it there (a phone, where it wraps).
  const [alignLeft, setAlignLeft] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const menuId = useId()

  const path = `${metadata.permalink.replace(/\/$/, '')}.md`
  const absolute = `${siteConfig.url}${path}`
  const prompt = `Read ${absolute} — a page of the ${siteConfig.title} documentation (${siteConfig.tagline}) — so I can ask you questions about it.`

  useEffect(() => {
    if (status === 'idle') return
    const timer = setTimeout(() => setStatus('idle'), 2000)
    return () => clearTimeout(timer)
  }, [status])

  useEffect(() => {
    if (!open) return
    const onPointer = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpen(false)
        root.current?.querySelector<HTMLButtonElement>('button[aria-haspopup]')?.focus()
      }
    }
    document.addEventListener('pointerdown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('pointerdown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const onCopy = () => {
    setOpen(false)
    copy(path).then(
      () => setStatus('copied'),
      (error: unknown) => {
        console.warn('Copy page:', error)
        setStatus('failed')
      },
    )
  }

  const items: { icon: keyof typeof icons; title: string; detail: string; href: string }[] = [
    { icon: 'markdown', title: 'View as Markdown', detail: 'This page as plain text', href: path },
    {
      icon: 'chat',
      title: 'Open in Claude',
      detail: 'Ask questions about this page',
      href: `https://claude.ai/new?q=${encodeURIComponent(prompt)}`,
    },
    {
      icon: 'chat',
      title: 'Open in ChatGPT',
      detail: 'Ask questions about this page',
      href: `https://chatgpt.com/?hints=search&q=${encodeURIComponent(prompt)}`,
    },
    { icon: 'index', title: 'llms.txt', detail: 'Every page, indexed for agents', href: llmsTxt },
    { icon: 'index', title: 'llms-full.txt', detail: 'All the docs in one file', href: llmsFullTxt },
  ]

  return (
    <div className={styles.root} ref={root}>
      <Head>
        <link rel="alternate" type="text/markdown" href={path} />
      </Head>
      <div className={styles.split}>
        <button type="button" className={styles.main} onClick={onCopy} aria-live="polite">
          <Icon name={status === 'copied' ? 'check' : 'copy'} />
          {status === 'copied' ? 'Copied' : status === 'failed' ? 'Copy failed' : 'Copy page'}
        </button>
        <button
          type="button"
          className={styles.toggle}
          aria-label="More ways to use this page"
          aria-haspopup="menu"
          aria-expanded={open}
          aria-controls={menuId}
          onClick={() => {
            const right = root.current?.getBoundingClientRect().right ?? Infinity
            setAlignLeft(right < menuWidth + 16)
            setOpen((value) => !value)
          }}>
          <Icon name="chevron" />
        </button>
      </div>
      {open && (
        <div className={`${styles.menu} ${alignLeft ? styles.left : ''}`} id={menuId} role="menu">
          <button type="button" role="menuitem" className={styles.item} onClick={onCopy}>
            <Icon name="copy" className={styles.itemIcon} />
            <span className={styles.itemText}>
              <span className={styles.itemTitle}>Copy page</span>
              <span className={styles.itemDetail}>As Markdown, for an LLM</span>
            </span>
          </button>
          {items.map((item, index) => (
            <a
              key={item.title}
              role="menuitem"
              className={`${styles.item} ${index === 3 ? styles.divided : ''}`}
              href={item.href}
              target="_blank"
              rel="noopener noreferrer"
              onClick={() => setOpen(false)}>
              <Icon name={item.icon} className={styles.itemIcon} />
              <span className={styles.itemText}>
                <span className={styles.itemTitle}>
                  {item.title}
                  <Icon name="external" className={styles.external} />
                </span>
                <span className={styles.itemDetail}>{item.detail}</span>
              </span>
            </a>
          ))}
        </div>
      )}
    </div>
  )
}
