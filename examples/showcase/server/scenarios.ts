// One in-memory world per scenario id, so any number of tests (or browser
// tabs) can run against one process without seeing each other. The Flutter
// app sends the id in the `x-scenario` header; a request without one lands in
// `default`, which is what a human at the keyboard gets.

import { readFileSync } from 'node:fs'
import { DEFAULT_LATENCY, SCENARIO_TTL } from './config.ts'
import type { Comment, LogEntry, Post, Project, ScenarioConfig, Seed, Tick, Todo } from './types.ts'

// The same file the Flutter widget tests' fake backend loads, so both sides
// start from identical data and the contract test can compare them.
export const seed: Seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'))

// mulberry32: a tiny seeded PRNG, so `errorRate` fails the same requests on
// every run of the same scenario.
const seededRandom = (start: number) => {
  let a = start >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const hash = (text: string) => {
  let h = 2166136261
  for (const char of text) {
    h ^= char.charCodeAt(0)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

export class Scenario {
  readonly id: string

  posts: Post[] = []
  comments: Comment[] = []
  todos: Todo[] = []
  ticks: Tick[] = []
  counter = 0
  // Bumped by `GET /api/time`, so "a refetch happened" is assertable without
  // comparing clocks.
  serial = 0

  config: ScenarioConfig = { latency: DEFAULT_LATENCY, errorRate: 0, failNext: [] }
  log: LogEntry[] = []
  random: () => number = () => 0
  lastTouched = Date.now()

  nextTodoId = 1
  nextTickId = 1

  constructor(id: string) {
    this.id = id
    this.reset()
  }

  reset() {
    this.posts = structuredClone(seed.posts)
    this.comments = structuredClone(seed.comments)
    this.todos = structuredClone(seed.todos)
    this.ticks = []
    this.counter = 0
    this.serial = 0
    this.config = { latency: DEFAULT_LATENCY, errorRate: 0, failNext: [] }
    this.log = []
    this.random = seededRandom(hash(this.id))
    this.nextTodoId = Math.max(0, ...this.todos.map((todo) => todo.id)) + 1
    this.nextTickId = 1
  }

  // Projects are not stored: they are `projectCount` rows minted on demand,
  // each stamped with the time of the response that carried it.
  project(id: number): Project {
    return { id, name: `Projekt ${id}`, fetchedAt: new Date().toISOString() }
  }

  get projectCount() {
    return seed.projectCount
  }
}

const scenarios = new Map<string, Scenario>()

export const scenarioFor = (id: string): Scenario => {
  let scenario = scenarios.get(id)
  if (!scenario) {
    scenario = new Scenario(id)
    scenarios.set(id, scenario)
  }
  scenario.lastTouched = Date.now()
  return scenario
}

export const evictIdleScenarios = (now = Date.now()) => {
  for (const [id, scenario] of scenarios) {
    if (id !== 'default' && now - scenario.lastTouched > SCENARIO_TTL) {
      scenarios.delete(id)
    }
  }
}

setInterval(evictIdleScenarios, 60_000).unref()
