// The gateway's domain model. With tRPC gone there is no shared type program
// between server and clients any more — each client (React, Flutter) declares
// its own copy of this contract, the same situation the real gateway is in.
// Field-level docs live here, on the producing side.

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
