// In-memory "database". Restarting the server resets everything.

import type { Sensor, SensorType } from './types.ts'

let nextId = 1

const makeSensor = (name: string, type: SensorType, extra: Partial<Sensor> = {}): Sensor => ({
  id: String(nextId++),
  name,
  type,
  room: extra.room ?? 'Wohnzimmer',
  battery: extra.battery ?? 90,
  temperature: extra.temperature ?? 21.5,
  connected: extra.connected ?? true,
  matterForwarding: extra.matterForwarding ?? false,
  matterForwardingTarget: null,
  matterForwardingPending: false,
})

let sensors: Sensor[] = [
  makeSensor('Fenster Küche', 'contact', { room: 'Küche', battery: 82 }),
  makeSensor('Bewegung Flur', 'motion', { room: 'Flur', battery: 47 }),
  makeSensor('Temperatur Wohnzimmer', 'temperature', { temperature: 22.4 }),
  makeSensor('Fenster Schlafzimmer', 'contact', { room: 'Schlafzimmer', battery: 12 }),
  // Deliberately offline so the header's connected count is not just "all of them".
  makeSensor('Garagentor', 'contact', { room: 'Garage', battery: 65, connected: false }),
]

export const db = {
  all: () => sensors,
  find: (id: string) => sensors.find((sensor) => sensor.id === id),
  create: (name: string, type: SensorType, room?: string) => {
    const sensor = makeSensor(name, type, { room })
    sensors.push(sensor)
    return sensor
  },
  remove: (id: string) => {
    sensors = sensors.filter((sensor) => sensor.id !== id)
  },
}
