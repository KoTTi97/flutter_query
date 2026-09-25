import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import CodeBlock from '@theme/CodeBlock'
import type { ReactNode } from 'react'
import { excerpt } from './excerpt'
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
const repository = 'https://github.com/dualmeta-gmbh/query_kit/blob'

export default function DartSource({ source, path, from, to, end, title }: DartSourceProps): ReactNode {
  const revision = String(useDocusaurusContext().siteConfig.customFields?.sourceRevision ?? 'main')
  if (typeof source !== 'string') {
    throw new Error(`DartSource: the source of ${path} is not a string; import the .dart file itself`)
  }
  const { code, firstLine, lastLine, whole } = excerpt(source, path, { from, to, end })
  const anchor = whole ? '' : `#L${firstLine}-L${lastLine}`
  const range = whole ? '' : ` · lines ${firstLine}–${lastLine}`
  return (
    <div className={styles.source}>
      <CodeBlock language="dart" title={`${title ?? path}${range}`} showLineNumbers={firstLine}>
        {code}
      </CodeBlock>
      <p className={styles.link}>
        <a href={`${repository}/${revision}/${path}${anchor}`} target="_blank" rel="noopener noreferrer">
          View on GitHub ↗
        </a>
      </p>
    </div>
  )
}
