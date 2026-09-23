// Components every doc page can use without an import. Swizzled by wrapping:
// the theme's own map, plus ours.
import LiveDemo from '@site/src/components/LiveDemo'
import MDXComponents from '@theme-original/MDXComponents'

export default {
  ...MDXComponents,
  LiveDemo,
}
