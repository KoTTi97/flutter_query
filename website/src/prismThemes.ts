import type { PrismTheme } from 'prism-react-renderer'

/**
 * The code blocks' colours: near-monochrome with a few strong accents, in
 * the manner of Vercel's Geist pages, to sit with the Geist type. The
 * backgrounds are the site's own code surface (`custom.css`), so a block is
 * one colour with its title bar.
 */
type Palette = {
  background: string
  plain: string
  comment: string
  keyword: string
  type: string
  call: string
  string: string
  number: string
  annotation: string
  punctuation: string
}

function geist(p: Palette): PrismTheme {
  return {
    plain: { color: p.plain, backgroundColor: p.background },
    styles: [
      { types: ['comment', 'prolog', 'doctype', 'cdata'], style: { color: p.comment, fontStyle: 'italic' } },
      { types: ['keyword', 'boolean', 'builtin', 'important', 'atrule'], style: { color: p.keyword } },
      { types: ['class-name', 'generics', 'tag', 'selector'], style: { color: p.type } },
      { types: ['function'], style: { color: p.call } },
      { types: ['string', 'string-literal', 'char', 'attr-value', 'url', 'inserted'], style: { color: p.string } },
      { types: ['number', 'constant', 'symbol', 'property'], style: { color: p.number } },
      { types: ['metadata', 'annotation', 'attr-name', 'variable'], style: { color: p.annotation } },
      { types: ['operator', 'punctuation'], style: { color: p.punctuation } },
      { types: ['interpolation-punctuation'], style: { color: p.keyword } },
      { types: ['deleted'], style: { color: p.keyword } },
    ],
  }
}

export const geistLight = geist({
  background: '#f8f9fb',
  plain: '#171717',
  comment: '#8f8f8f',
  keyword: '#c41562',
  type: '#005ff2',
  call: '#7d00cc',
  string: '#107d32',
  number: '#005ff2',
  annotation: '#a35200',
  punctuation: '#6f6f6f',
})

export const geistDark = geist({
  background: '#0d1016',
  plain: '#ededed',
  comment: '#7c7c7c',
  keyword: '#ff4d8d',
  type: '#47a8ff',
  call: '#c472fb',
  string: '#62c073',
  number: '#47a8ff',
  annotation: '#ffb224',
  punctuation: '#a1a1a1',
})
