import { defineConfig, devices } from '@playwright/test'

// The app under test is `flutter build web --dart-define=E2E=true` (npm run
// build), served as static files; the backend is the real express server in
// ../server. Both are started here.
//
// Every test lives in a scenario of its own on the backend (see
// tests/fixtures.ts), so the suite runs in parallel: nothing a test does is
// visible to another.
// APP_PORT lets several checkouts run their own build side by side against
// one backend, which keeps them apart by scenario anyway.
const appPort = process.env.APP_PORT ?? '8124'

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // A CanvasKit tab costs a core at boot; the CI runner has four.
  workers: process.env.CI ? 2 : 4,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${appPort}`,
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: [
    {
      command: 'node server.ts',
      cwd: '../server',
      url: 'http://localhost:5175/api/__scenario/probe/requests',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'node serve.mjs ../build/web',
      env: { PORT: appPort },
      url: `http://localhost:${appPort}`,
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
})
