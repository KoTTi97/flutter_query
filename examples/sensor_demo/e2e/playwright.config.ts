import { defineConfig, devices } from '@playwright/test'

// The app under test is `flutter build web --dart-define=E2E=true` (npm run
// build), served as static files; the gateway is the real express server the
// React demo uses. Both are started here.
export default defineConfig({
  testDir: './tests',
  // The gateway keeps one in-memory state per run and scripts "every second
  // delete fails", so tests run one at a time, in file order.
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: 'http://localhost:8123',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: [
    {
      command: 'node server.ts',
      cwd: '../server',
      url: 'http://localhost:5174/api/sensors',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
    {
      command: 'node serve.mjs ../build/web',
      url: 'http://localhost:8123',
      reuseExistingServer: !process.env.CI,
      timeout: 30_000,
    },
  ],
})
