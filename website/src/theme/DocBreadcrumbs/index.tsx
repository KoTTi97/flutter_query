// Wrapped, not ejected: the theme's breadcrumbs, with the page's "Copy page"
// menu at the end of the same row (`src/components/CopyPage`).
import CopyPage from '@site/src/components/CopyPage'
import DocBreadcrumbs from '@theme-original/DocBreadcrumbs'
import type { WrapperProps } from '@docusaurus/types'
import type DocBreadcrumbsType from '@theme/DocBreadcrumbs'
import type { ReactNode } from 'react'
import styles from './styles.module.css'

type Props = WrapperProps<typeof DocBreadcrumbsType>

export default function DocBreadcrumbsWrapper(props: Props): ReactNode {
  return (
    <div className={styles.row}>
      <div className={styles.crumbs}>
        <DocBreadcrumbs {...props} />
      </div>
      <CopyPage />
    </div>
  )
}
