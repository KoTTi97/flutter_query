import { defineConfig, devices } from '@playwright/test'

// The site as it ships: `npm run demos && npm run build` in website/, then
// `docusaurus serve` over build/, under the real base URL. There is no backend
// — every demo runs against its in-memory one inside the page — so nothing
// here starts a server but the static one.
const port = process.env.SITE_PORT ?? '3100'

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // A CanvasKit tab costs a core at boot; the CI runner has four.
  workers: process.env.CI ? 2 : 4,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 20_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `npx docusaurus serve --dir build --port ${port} --no-open`,
    cwd: '..',
    url: `http://localhost:${port}/query_kit/`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
})
