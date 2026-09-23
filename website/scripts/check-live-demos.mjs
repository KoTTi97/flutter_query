// Fails when a doc page names a live demo that does not exist.
//
// Every `<LiveDemo feature="…">` in docs/ must name a showcase route; the
// list is src/components/LiveDemo/showcase-features.json, which the
// showcase's own test/demo_mode_test.dart keeps equal to lib/routes.dart. A
// renamed feature therefore fails `npm run build`, instead of leaving a page
// with a frame that opens "Unknown demo". Run by `npm run build`, before
// Docusaurus; needs no demo build.
import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const site = join(dirname(fileURLToPath(import.meta.url)), '..')
const features = new Set(
  JSON.parse(readFileSync(join(site, 'src/components/LiveDemo/showcase-features.json'), 'utf8')).map(
    (feature) => feature.id,
  ),
)
const apps = new Set(['showcase', 'task_manager'])

function* pages(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) yield* pages(path)
    else if (/\.mdx?$/.test(entry.name)) yield path
  }
}

const attribute = (tag, name) => tag.match(new RegExp(`\\b${name}=["']([^"']*)["']`))?.[1]

const problems = []
let count = 0
for (const page of pages(join(site, 'docs'))) {
  // A fenced block that shows the tag is not a use of it; blanked rather than
  // removed, so the line numbers stay true.
  const text = readFileSync(page, 'utf8').replace(/^(`{3,}|~{3,})[^\n]*\n[\s\S]*?^\1/gm, (block) =>
    block.replace(/[^\n]/g, ' '),
  )
  for (const match of text.matchAll(/<LiveDemo\b[^>]*>/g)) {
    count += 1
    const tag = match[0]
    const line = text.slice(0, match.index).split('\n').length
    const where = `${relative(site, page)}:${line}`
    const app = attribute(tag, 'app') ?? 'showcase'
    const feature = attribute(tag, 'feature')
    if (!apps.has(app)) {
      problems.push(`${where}: app="${app}" is neither showcase nor task_manager`)
    } else if (app === 'showcase' && (feature === undefined || !features.has(feature))) {
      problems.push(`${where}: feature="${feature ?? ''}" is not a showcase route`)
    }
  }
}

if (problems.length > 0) {
  console.error(`check-live-demos: ${problems.length} broken <LiveDemo>:\n  ${problems.join('\n  ')}`)
  console.error(`The ids are in src/components/LiveDemo/showcase-features.json (${features.size} features).`)
  process.exit(1)
}
console.log(`check-live-demos: ${count} <LiveDemo> across docs/, every one a real demo`)
