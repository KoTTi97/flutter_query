// Client state only.
//
// The split that matters: anything the gateway owns (sensors, their names, their
// matter state) lives in the TanStack Query cache and is never copied in here.
// This store holds the things that have no server representation at all — which
// screen is open, what is typed into the search box, whether a menu is expanded.
//
// Keeping server data out of the store is what makes both halves simple. A
// store that mirrored the sensor list would need its own fetching, staleness and
// invalidation rules, which is exactly the hand-rolled machinery this demo
// exists to argue against.

import { create } from 'zustand'

/** Last request seen by the axios interceptor — purely for the UI readout. */
type RequestLogEntry = { path: string; ms: number; ok: boolean }

type AppState = {
  openSensorId: string | null
  search: string
  room: string
  sensorMenuOpen: boolean
  lastRequest: RequestLogEntry | null

  openSensor: (id: string) => void
  closeSensor: () => void
  setSearch: (search: string) => void
  setRoom: (room: string) => void
  setSensorMenuOpen: (open: boolean) => void
  recordRequest: (entry: RequestLogEntry) => void
}

export const useAppStore = create<AppState>()((set) => ({
  openSensorId: null,
  search: '',
  room: 'all',
  sensorMenuOpen: false,
  lastRequest: null,

  openSensor: (id) => set({ openSensorId: id, sensorMenuOpen: false }),
  closeSensor: () => set({ openSensorId: null }),
  setSearch: (search) => set({ search }),
  setRoom: (room) => set({ room }),
  setSensorMenuOpen: (sensorMenuOpen) => set({ sensorMenuOpen }),
  recordRequest: (lastRequest) => set({ lastRequest }),
}))
