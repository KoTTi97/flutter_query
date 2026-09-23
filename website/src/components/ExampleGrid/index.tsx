import Link from '@docusaurus/Link'
import type { ReactNode } from 'react'
import showcaseFeatures from '../LiveDemo/showcase-features.json'
import styles from './styles.module.css'

/**
 * One group of the examples gallery: each showcase feature named in `ids`,
 * with its title and one-line summary from `showcase-features.json` (the
 * site's copy of the showcase's routes), linking to its page under
 * `/docs/examples/<id>`.
 *
 * ```mdx
 * <ExampleGrid ids={['simple', 'basic']} />
 * ```
 *
 * An id that is not a showcase feature fails the build, as `<LiveDemo>` does.
 */

type ShowcaseFeature = { id: string; title: string; summary: string }

export type ExampleGridProps = {
  ids: string[]
}

export default function ExampleGrid({ ids }: ExampleGridProps): ReactNode {
  const features = showcaseFeatures as ShowcaseFeature[]
  const entries = ids.map((id) => {
    const feature = features.find((candidate) => candidate.id === id)
    if (feature === undefined) {
      throw new Error(`ExampleGrid: "${id}" is not a showcase feature (showcase-features.json)`)
    }
    return feature
  })
  return (
    <ul className={styles.grid}>
      {entries.map((feature) => (
        <li key={feature.id} className={styles.entry}>
          <Link to={`/docs/examples/${feature.id}`} className={styles.title}>
            {feature.title}
          </Link>
          <span className={styles.summary}>{feature.summary}</span>
        </li>
      ))}
    </ul>
  )
}
