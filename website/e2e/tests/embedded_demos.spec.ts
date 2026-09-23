// Every demo the site can frame, opened at its embed URL: each showcase
// feature — the list comes from the catalogue, so a new screen is covered the
// day it is added — and the task manager. What is checked is that the demo
// build boots on that route, with no server, and shows that screen alone.
import { embedUrl, expect, showcaseFeatures, test } from './fixtures'

for (const feature of showcaseFeatures) {
  test(`showcase: ${feature.id}`, async ({ page }) => {
    await page.goto(embedUrl('showcase', `#/${feature.id}`))
    await expect(page.getByRole('heading', { name: feature.title, exact: true })).toBeVisible()
    // The intro folds the summary and the upstream line into one node.
    await expect(page.getByText(feature.summary).first()).toBeVisible()
    await expect(page.getByText('in-memory backend', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Back', exact: true })).toHaveCount(0)
  })
}

test('showcase: an id that is no feature is not the catalogue', async ({ page }) => {
  await page.goto(embedUrl('showcase', '#/no-such-feature'))
  await expect(page.getByRole('heading', { name: 'Unknown demo', exact: true })).toBeVisible()
  await expect(page.getByText('query_kit showcase', { exact: true })).toHaveCount(0)
})

test('task manager: the list arrives from the in-memory backend', async ({ page }) => {
  await page.goto(embedUrl('task_manager'))
  await expect(page.getByRole('heading', { name: 'Task Manager', exact: true })).toBeVisible()
  // A row is a group named after its task (examples/task_manager/e2e).
  await expect(page.getByRole('group', { name: /^Draft the changelog/ })).toBeVisible()
})
