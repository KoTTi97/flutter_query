import type { PrismTheme } from 'prism-react-renderer'

/**
 * The code blocks' colours: near-monochrome with a few strong accents, in
 * the manner of Vercel's Geist pages, to sit with the Geist type.
 *
 * The theme holds no colours, only the `--qk-code-*` variables, whose values
 * for either mode are in `custom.css`. Docusaurus picks a prism theme by the
 * React colour mode, which is light in the pre-rendered HTML and becomes dark
 * only after hydration, and writes it into each block as inline styles; with
 * two themes of real colours a dark page therefore drew its code light until
 * then. One theme of variables renders the same inline styles in both, and
 * `[data-theme='dark']`, set by an inline script before the first paint,
 * picks the colours.
 */
const v = (name: string) => `var(--qk-code-${name})`

export const geist: PrismTheme = {
  plain: { color: v('plain'), backgroundColor: v('background') },
  styles: [
    { types: ['comment', 'prolog', 'doctype', 'cdata'], style: { color: v('comment'), fontStyle: 'italic' } },
    { types: ['keyword', 'boolean', 'builtin', 'important', 'atrule'], style: { color: v('keyword') } },
    { types: ['class-name', 'generics', 'tag', 'selector'], style: { color: v('type') } },
    { types: ['function'], style: { color: v('call') } },
    { types: ['string', 'string-literal', 'char', 'attr-value', 'url', 'inserted'], style: { color: v('string') } },
    { types: ['number', 'constant', 'symbol', 'property'], style: { color: v('number') } },
    { types: ['metadata', 'annotation', 'attr-name', 'variable'], style: { color: v('annotation') } },
    { types: ['operator', 'punctuation'], style: { color: v('punctuation') } },
    { types: ['interpolation-punctuation'], style: { color: v('keyword') } },
    { types: ['deleted'], style: { color: v('keyword') } },
  ],
}
