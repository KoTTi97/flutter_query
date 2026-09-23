// What the specs share: the site's base URL, the list of showcase features the
// site knows, and the showcase's semantics-tree locators
// (examples/showcase/e2e/tests/fixtures.ts), taking a page or an iframe.
import type { FrameLocator, Page } from '@playwright/test'
import features from '../../src/components/LiveDemo/showcase-features.json' with { type: 'json' }

export { expect, test } from '@playwright/test'

export const BASE = '/query_kit/'

export type Feature = { id: string; title: string; summary: string }

/// Every showcase feature, in the catalogue's order. The showcase's
/// test/demo_mode_test.dart keeps this file equal to its lib/routes.dart, so a
/// spec driven from it covers every route there is.
export const showcaseFeatures: Feature[] = features

/// Where a demo lives in the built site; the same URL `<LiveDemo>` frames.
export const embedUrl = (app: 'showcase' | 'task_manager', route = '') =>
  `${BASE}demo/${app}/?embed=1&semantics=1${route}`

type Scope = Page | FrameLocator

/// The semantics group named `name`: a screen publishes it through
/// `SemanticsGroup`, as the showcase's own suite reads it.
export const group = (scope: Scope, name: string) => scope.getByRole('group', { name, exact: true })

/// One fact inside that group, by its exact leaf text: `status=success`.
export const factIn = (scope: Scope, name: string, text: string) =>
  group(scope, name).getByText(text, { exact: true })
