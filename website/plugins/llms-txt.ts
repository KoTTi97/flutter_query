import type { LoadedContent as DocsContent } from '@docusaurus/plugin-content-docs'
import type { LoadContext, Plugin } from '@docusaurus/types'
import { readFileSync } from 'node:fs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join, relative, resolve } from 'node:path'
import showcaseFeatures from '../src/components/LiveDemo/showcase-features.json'
import { excerpt } from '../src/components/DartSource/excerpt'

/**
 * The site as Markdown, for AI agents and anyone who reads it outside a
 * browser, written into the build by `postBuild`:
 *
 * - every doc page at its own URL plus `.md` (`/docs/quick-start` →
 *   `/docs/quick-start.md`), which the page's "Copy page" button fetches and
 *   its `<link rel="alternate" type="text/markdown">` names;
 * - `llms.txt` (<https://llmstxt.org>), the index: every page in sidebar
 *   order, linked to its Markdown, with its description;
 * - `llms-full.txt`, every page in that order in one file.
 *
 * The source is the page's own `.md`/`.mdx`, not its rendered HTML, with the
 * MDX a reader outside the site cannot run turned into Markdown: a
 * `<DartSource>` becomes the excerpt it shows (through the same `excerpt()`,
 * so the two cannot differ), a `<LiveDemo>` a link to the running app, an
 * `<ExampleGrid>` a list, tabs labelled sections, an admonition a quote, and
 * a link to another page a link to that page's Markdown.
 */

type Doc = DocsContent['loadedVersions'][number]['docs'][number]
type SidebarItem = DocsContent['loadedVersions'][number]['sidebars'][string][number]
type Feature = { id: string; title: string; summary: string }

const features = showcaseFeatures as Feature[]
const repository = 'https://github.com/dualmeta-gmbh/query_kit'

export type LlmsTxtOptions = {
  /** The one-line summary under the title: the site's tagline and disclosure. */
  summary: string
  /** Paragraphs after the summary. */
  details: string
  /** Top-level sidebar categories listed under llms.txt's `## Optional`. */
  optional: string[]
}

// `options` is `unknown` because that is what a plugin entry in the config
// is typed to pass; the config checks its object with `satisfies`.
export default function llmsTxtPlugin(context: LoadContext, rawOptions: unknown): Plugin {
  const options = rawOptions as LlmsTxtOptions
  const { siteDir, siteConfig } = context
  const origin = siteConfig.url.replace(/\/$/, '')
  const baseUrl = siteConfig.baseUrl
  const revision = String(siteConfig.customFields?.sourceRevision ?? 'main')
  let docs: Doc[] = []
  let sidebar: SidebarItem[] = []

  const markdownUrl = (permalink: string) => `${origin}${permalink.replace(/\/$/, '')}.md`

  return {
    name: 'llms-txt',

    async allContentLoaded({ allContent }) {
      const content = allContent['docusaurus-plugin-content-docs']?.default as DocsContent | undefined
      const version = content?.loadedVersions[0]
      if (version === undefined) throw new Error('llms-txt: no docs were loaded')
      docs = version.docs
      sidebar = version.sidebars.docs ?? Object.values(version.sidebars)[0] ?? []
    },

    async postBuild({ outDir }) {
      const byId = new Map(docs.map((doc) => [doc.id, doc]))
      const byFile = new Map(docs.map((doc) => [sourceFile(doc), doc]))

      const pages = new Map<string, string>()
      for (const doc of docs) {
        const file = sourceFile(doc)
        const body = toMarkdown(await readFile(file, 'utf8'), file)
        const titled = /^# /m.test(firstProse(body)) ? body : `# ${doc.title}\n\n${body}`
        const page = `${titled.replace(/^(# .*\n)/, `$1\n${doc.description ? `> ${doc.description}\n` : ''}`).trim()}\n`
        pages.set(doc.id, page)
        const target = join(outDir, `${relative(baseUrl, `${doc.permalink.replace(/\/$/, '')}.md`)}`)
        await mkdir(dirname(target), { recursive: true })
        await writeFile(target, page)
      }

      // Sidebar order, then anything the sidebar leaves out.
      const ordered: { section: string; group?: string; doc: Doc }[] = []
      const seen = new Set<string>()
      const visit = (items: SidebarItem[], section: string, group?: string) => {
        for (const item of items) {
          if (item.type === 'doc' || item.type === 'ref') {
            const doc = byId.get(item.id)
            if (doc && !seen.has(doc.id)) {
              seen.add(doc.id)
              ordered.push({ section, group, doc })
            }
          } else if (item.type === 'category') {
            const inner = section === '' ? item.label : section
            const innerGroup = section === '' ? undefined : item.label
            if (item.link?.type === 'doc') visit([{ type: 'doc', id: item.link.id }], inner, innerGroup)
            visit(item.items, inner, innerGroup)
          }
        }
      }
      visit(sidebar, '')
      for (const doc of docs) if (!seen.has(doc.id)) ordered.push({ section: 'Other pages', doc })

      const head = `# ${siteConfig.title}\n\n> ${options.summary}\n\n${options.details.trim()}\n`
      const sections = new Map<string, typeof ordered>()
      for (const entry of ordered) {
        const key = options.optional.includes(entry.section) ? 'Optional' : entry.section
        sections.set(key, [...(sections.get(key) ?? []), entry])
      }
      const optional = sections.get('Optional')
      if (optional) {
        sections.delete('Optional')
        sections.set('Optional', optional)
      }

      let index = head
      for (const [section, entries] of sections) {
        index += `\n## ${section}\n\n`
        let group: string | undefined
        for (const { group: entryGroup, doc } of entries) {
          if (section !== 'Optional' && entryGroup !== group) {
            group = entryGroup
            if (group) index += `\n### ${group}\n\n`
          }
          index += `- [${doc.title}](${markdownUrl(doc.permalink)})${doc.description ? `: ${doc.description}` : ''}\n`
        }
      }
      index = index.replace(/\n{3,}/g, '\n\n')
      await writeFile(join(outDir, 'llms.txt'), index)

      const full = ordered
        .map(({ doc }) => `<!-- ${origin}${doc.permalink} -->\n\n${pages.get(doc.id)}`)
        .join('\n---\n\n')
      await writeFile(join(outDir, 'llms-full.txt'), `${head}\n---\n\n${full}`)

      // --- conversion -------------------------------------------------------

      function sourceFile(doc: Doc): string {
        return resolve(siteDir, doc.source.replace(/^@site\//, ''))
      }

      function toMarkdown(text: string, file: string): string {
        const imports = new Map<string, string>()
        const out: string[] = []
        const lines = text.replace(/^---\n[\s\S]*?\n---\n/, '').split('\n')
        let fence: string | undefined
        let depth = 0
        let prose: string[] = []

        const quote = (line: string) => (depth === 0 ? line : `${'> '.repeat(depth)}${line}`.trimEnd())
        const flush = () => {
          if (prose.length === 0) return
          for (const line of convertProse(prose.join('\n'), file, imports).split('\n')) out.push(quote(line))
          prose = []
        }

        for (const line of lines) {
          if (fence) {
            out.push(quote(line))
            const close = line.match(/^(\s*)(`{3,}|~{3,})\s*$/)
            if (close && close[2][0] === fence[0] && close[2].length >= fence.length) fence = undefined
            continue
          }
          const open = line.match(/^(\s*)(`{3,}|~{3,})\s*([\w+-]*)(.*)$/)
          if (open) {
            flush()
            const title = open[4].match(/\btitle="([^"]*)"/)?.[1]
            if (title) out.push(quote(`${open[1]}\`${title}\`:`), quote(''))
            out.push(quote(`${open[1]}${open[2]}${open[3]}`))
            fence = open[2]
            continue
          }
          const admonition = line.match(/^\s*:::(\w+)(?:\[(.*)\])?\s*$/)
          if (admonition) {
            flush()
            depth += 1
            const kind = admonition[1][0].toUpperCase() + admonition[1].slice(1)
            out.push(quote(`**${kind}${admonition[2] ? `: ${admonition[2]}` : ''}**`), quote(''))
            continue
          }
          if (/^\s*:::\s*$/.test(line) && depth > 0) {
            flush()
            // A blank quoted line before the close leaves nothing dangling.
            while (out.length > 0 && out[out.length - 1].replace(/^(> ?)+/, '').trim() === '') out.pop()
            depth -= 1
            continue
          }
          prose.push(line)
        }
        flush()
        return out.join('\n').replace(/\n{3,}/g, '\n\n').trim()
      }

      function convertProse(text: string, file: string, imports: Map<string, string>): string {
        return (
          text
            .replace(/^import\s+(\w+)\s+from\s+'([^']+)';?[ \t]*$/gm, (_, name: string, from: string) => {
              imports.set(name, from)
              return ''
            })
            .replace(/^export\s.*$/gm, '')
            .replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
            .replace(/[ \t]*\\?\{#[\w-]+\\?\}[ \t]*$/gm, '')
            .replace(/<DartSource\b([\s\S]*?)\/>/g, (_, attributes: string) => dartSource(attributes, file, imports))
            .replace(/<LiveDemo\b([\s\S]*?)\/>/g, (_, attributes: string) => liveDemo(attributes))
            .replace(/<ExampleGrid\b([\s\S]*?)\/>/g, (_, attributes: string) => exampleGrid(attributes))
            .replace(/^<Tabs\b[^>]*>[ \t]*$|^<\/Tabs>[ \t]*$|^<\/TabItem>[ \t]*$/gm, '')
            .replace(/^<TabItem\b([^>]*)>[ \t]*$/gm, (_, attributes: string) => `**${attribute(attributes, 'label')}**`)
            .replace(/\]\(([^)\s]+)\)/g, (_, href: string) => `](${link(href, file)})`)
            .replace(/[ \t]+$/gm, '')
        )
      }

      function attribute(attributes: string, name: string): string | undefined {
        const match = attributes.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)'|\\{([\\s\\S]*?)\\})`))
        return match ? (match[1] ?? match[2] ?? match[3]) : undefined
      }

      function dartSource(attributes: string, file: string, imports: Map<string, string>): string {
        const name = attribute(attributes, 'source')?.trim()
        const path = attribute(attributes, 'path')
        const imported = name === undefined ? undefined : imports.get(name)
        if (imported === undefined || path === undefined) {
          throw new Error(`llms-txt: a <DartSource> in ${file} names no imported source or no path`)
        }
        const source = resolve(siteDir, imported.replace(/^@site\//, ''))
        const { code, firstLine, lastLine, whole } = excerpt(readFileSyncCached(source), path, {
          from: attribute(attributes, 'from'),
          to: attribute(attributes, 'to'),
          end: attribute(attributes, 'end'),
        })
        const title = attribute(attributes, 'title') ?? path
        const lines = whole ? '' : `, lines ${firstLine}–${lastLine}`
        const url = `${repository}/blob/${revision}/${path}${whole ? '' : `#L${firstLine}-L${lastLine}`}`
        const fence = code.includes('```') ? '````' : '```'
        return `[\`${title}\`${lines}](${url}):\n\n${fence}dart\n${code}\n${fence}`
      }

      function liveDemo(attributes: string): string {
        const app = attribute(attributes, 'app') ?? 'showcase'
        if (app === 'task_manager') {
          return `Live demo: [Task manager](${origin}${baseUrl}demo/task_manager/), the whole example app, running in the browser against an in-memory backend ([source](${repository}/tree/main/examples/task_manager/lib)).`
        }
        const id = attribute(attributes, 'feature')
        const feature = features.find((candidate) => candidate.id === id)
        if (feature === undefined) throw new Error(`llms-txt: <LiveDemo feature="${id}"> is not a showcase feature`)
        return `Live demo: [${feature.title}](${origin}${baseUrl}demo/showcase/#/${feature.id}), running in the browser against an in-memory backend ([source](${repository}/tree/main/examples/showcase/lib/features/${feature.id.replaceAll('-', '_')})). ${feature.summary}`
      }

      function exampleGrid(attributes: string): string {
        const ids = [...(attribute(attributes, 'ids') ?? '').matchAll(/'([^']+)'|"([^"]+)"/g)].map((m) => m[1] ?? m[2])
        return ids
          .map((id) => {
            const feature = features.find((candidate) => candidate.id === id)
            if (feature === undefined) throw new Error(`llms-txt: <ExampleGrid> names "${id}", not a showcase feature`)
            return `- [${feature.title}](${origin}${baseUrl}docs/examples/${feature.id}.md): ${feature.summary}`
          })
          .join('\n')
      }

      /** A link to another page becomes a link to its Markdown; the rest stay. */
      function link(href: string, file: string): string {
        if (/^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('#')) return href
        const [path, anchor = ''] = href.split(/(?=#)/)
        let target: Doc | undefined
        if (/\.mdx?$/.test(path)) target = byFile.get(resolve(dirname(file), path))
        else if (path.startsWith('/')) target = docs.find((doc) => doc.permalink === `${baseUrl}${path.slice(1)}`.replace(/\/$/, ''))
        return target ? `${markdownUrl(target.permalink)}${anchor}` : href
      }
    },
  }
}

const cache = new Map<string, string>()
function readFileSyncCached(path: string): string {
  let text = cache.get(path)
  if (text === undefined) {
    text = readFileSync(path, 'utf8')
    cache.set(path, text)
  }
  return text
}

/** The first line of prose: a fenced `# comment` is not a title. */
function firstProse(markdown: string): string {
  return markdown.split('\n').find((line) => line.trim() !== '') ?? ''
}
