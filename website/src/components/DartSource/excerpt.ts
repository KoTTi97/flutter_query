/**
 * The stretch of a Dart file a `<DartSource>` shows: the component renders
 * it, and `plugins/llms-txt.ts` writes the same lines into a page's Markdown,
 * so a page and its Markdown copy cannot show different code.
 */
export type Excerpt = {
  /** The excerpt's lines, dedented, joined. */
  code: string
  /** One-based, inclusive. */
  firstLine: number
  lastLine: number
  /** The whole file, not a stretch of it. */
  whole: boolean
}

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

export function excerpt(
  source: string,
  path: string,
  { from, to, end }: { from?: string; to?: string; end?: string },
): Excerpt {
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
  return {
    code: dedent(lines.slice(first, last + 1)),
    firstLine: first + 1,
    lastLine: last + 1,
    whole: first === 0 && last === lines.length - 1,
  }
}
