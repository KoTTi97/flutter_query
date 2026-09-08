import { fileURLToPath } from 'node:url'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    port: 5173,
    // The dummy gateway is a standalone process now (../server, port 5174),
    // shared with the Flutter demo. The proxy keeps the browser same-origin so
    // the client code never mentions the gateway's port.
    proxy: { '/api': 'http://localhost:5174' },
  },
})
