// A static file server for `../build/web`, so the end-to-end tests need no
// extra dependency for it. Node only.
import { createReadStream, existsSync, statSync } from 'node:fs'
import { createServer } from 'node:http'
import { extname, join, normalize } from 'node:path'

const root = process.argv[2] ?? '../build/web'
const port = Number(process.env.PORT ?? 8124)

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.wasm': 'application/wasm',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
}

createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost')
  let file = join(root, normalize(decodeURIComponent(url.pathname)))
  if (!file.startsWith(normalize(root))) {
    res.writeHead(403).end()
    return
  }
  if (!existsSync(file) || statSync(file).isDirectory()) {
    file = join(root, 'index.html')
  }
  res.writeHead(200, {
    'content-type': types[extname(file)] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  })
  createReadStream(file).pipe(res)
}).listen(port, () => console.log(`serving ${root} on http://localhost:${port}`))
