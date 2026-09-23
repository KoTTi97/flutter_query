import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import CodeBlock from '@theme/CodeBlock'
import type { ReactNode } from 'react'
import styles from './styles.module.css'

/**
 * A Dart file of the repository, or one stretch of it, as a code block.
 *
 * `source` is the file's text, imported by the page (`plugins/dart-source.ts`
 * makes `.dart` importable as a string). `from` and `to` pick the excerpt:
 * the one line containing `from` through the first line after it containing
 * `to`, both included, or instead of `to` the first line after it that starts
 * with `end`, indentation included (`end="}"` is the next top-level brace).
 * `from` must match exactly one line, so an excerpt whose anchor was renamed
 * or duplicated fails the build instead of quietly showing other code.
 */
export type DartSourceProps = {
  source: string
  /** Repository-relative path: the block's title and the GitHub link. */
  path: string
  from?: string
  to?: string
  /** The excerpt's last line starts with this, indentation included. */
  end?: string
  /** Replaces the path in the block's title. */
  title?: string
}

// Line links point at the commit the site was built from
// (`customFields.sourceRevision`), so the lines they name are the lines shown.
const repository = 'https://github.com/KoTTi97/query_kit/blob'

function find(
  lines: string[],
  needle: string,
  start: number,
  path: string,
  unique: boolean,
  prefix = false,
): number {
  const hits: number[] = []
  for (let i = start; i < lines.length; i++) {
    if (prefix ? lines[i].startsWith(needle) : lines[i].includes(needle)) hits.push(i)
  }
  if (hits.length === 0) {
    throw new Error(`DartSource: "${needle}" is not in ${path} (after line ${start + 1})`)
  }
  if (unique && hits.length > 1) {
    throw new Error(`DartSource: "${needle}" is in ${path} ${hits.length} times; pick an anchor that is unique`)
  }
  return hits[0]
}

function dedent(lines: string[]): string {
  const indents = lines.filter((line) => line.trim() !== '').map((line) => line.match(/^ */)![0].length)
  const cut = indents.length === 0 ? 0 : Math.min(...indents)
  return lines.map((line) => line.slice(cut)).join('\n')
}

export default function DartSource({ source, path, from, to, end, title }: DartSourceProps): ReactNode {
  const revision = String(useDocusaurusContext().siteConfig.customFields?.sourceRevision ?? 'main')
  if (typeof source !== 'string') {
    throw new Error(`DartSource: the source of ${path} is not a string; import the .dart file itself`)
  }
  const lines = source.replace(/\n$/, '').split('\n')
  const first = from === undefined ? 0 : find(lines, from, 0, path, true)
  const last =
    end !== undefined
      ? find(lines, end, first + 1, path, false, true)
      : to !== undefined
        ? find(lines, to, first + 1, path, false)
        : from === undefined
          ? lines.length - 1
          : first
  const whole = first === 0 && last === lines.length - 1
  const anchor = whole ? '' : `#L${first + 1}-L${last + 1}`
  const range = whole ? '' : ` · lines ${first + 1}–${last + 1}`
  return (
    <div className={styles.source}>
      <CodeBlock language="dart" title={`${title ?? path}${range}`} showLineNumbers={first + 1}>
        {dedent(lines.slice(first, last + 1))}
      </CodeBlock>
      <p className={styles.link}>
        <a href={`${repository}/${revision}/${path}${anchor}`} target="_blank" rel="noopener noreferrer">
          View on GitHub ↗
        </a>
      </p>
    </div>
  )
}
