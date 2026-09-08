// The client's copy of the gateway's domain model. Type-only, so every import
// of this file is erased before it reaches the browser.
//
// With tRPC gone this is a copy by convention, not a checked contract: the
// producing side is ../../server/types.ts, and nothing stops the two drifting
// apart except discipline. That is deliberate — it is the same deal the Flutter
// client gets against this gateway (and both get against the real one).

export type SensorType = 'contact' | 'motion' | 'temperature'

export type Sensor = {
  id: string
  name: string
  type: SensorType
  room: string
  battery: number
  temperature: number
  /** Reachable on the radio right now. */
  connected: boolean
  /** Confirmed device state. */
  matterForwarding: boolean
  /**
   * The value a write is trying to reach, or null when nothing is outstanding.
   *
   * This exists so an in-flight write has somewhere to live that a poll response
   * cannot overwrite. Without it, the confirmed field is the only place to put
   * the optimistic value, and every poll during the confirmation window stomps
   * it back to the old state — the switch visibly flickers off→on→off→on.
   */
  matterForwardingTarget: boolean | null
  /** The gateway accepted a write the device has not confirmed yet. */
  matterForwardingPending: boolean
}

export type SensorListResponse = {
  sensors: Sensor[]
  fetchedAt: string
}

export type SensorFilters = {
  search: string
  room: string
}
