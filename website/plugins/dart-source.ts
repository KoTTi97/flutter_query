import type { Plugin } from '@docusaurus/types'

/**
 * Lets a page import a Dart file of the repository as a string:
 *
 * ```mdx
 * import screen from '@site/../examples/showcase/lib/features/simple/simple_screen.dart'
 *
 * <DartSource source={screen} path="examples/showcase/lib/features/simple/simple_screen.dart" />
 * ```
 *
 * The bundler reads the file at build time (`asset/source`, built into both
 * webpack and Rspack; no loader package), so the code on the page is the
 * compiled file itself, never a copy committed to the site: the file is
 * analysed and tested where it lives, and the page cannot drift from it.
 */
export default function dartSourcePlugin(): Plugin {
  return {
    name: 'dart-source',
    configureWebpack() {
      return {
        module: { rules: [{ test: /\.dart$/, type: 'asset/source' }] },
      }
    },
  }
}
