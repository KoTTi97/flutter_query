// The wire contract, typed by hand. With tRPC gone, nothing checks this file
// against the server any more — the route table in ../../server/server.ts is
// the source of truth and this is the client's copy of it. That is the same
// deal the Flutter client gets, which is exactly why the demo now works this
// way.
//
// The key factory is the other half of what tRPC used to provide: every query
// key in the app is minted here, so "which keys exist" has one answer and
// prefix invalidation (`sensorKeys.lists()`, `sensorKeys.details()`) has stable
// anchors.

import type { Sensor, SensorFilters, SensorListResponse, SensorType } from '../shared/types.ts'
import { http } from './http.ts'

export const sensorKeys = {
  all: ['sensors'] as const,
  lists: () => [...sensorKeys.all, 'list'] as const,
  list: (filters: SensorFilters) => [...sensorKeys.lists(), filters] as const,
  details: () => [...sensorKeys.all, 'byId'] as const,
  detail: (id: string) => [...sensorKeys.details(), id] as const,
}

export type CreateSensorInput = { name: string; room?: string; type?: SensorType }

// Every read takes the AbortSignal from the query-function context, so
// TanStack Query cancelling a query (which it does on `cancelQueries`, and for
// superseded fetches) really does abort the HTTP request.
export const api = {
  listSensors: async (filters: SensorFilters, signal?: AbortSignal) =>
    (await http.get<SensorListResponse>('/sensors', { params: filters, signal })).data,

  getSensor: async (id: string, signal?: AbortSignal) =>
    (await http.get<Sensor>(`/sensors/${id}`, { signal })).data,

  createSensor: async (input: CreateSensorInput) =>
    (await http.post<Sensor>('/sensors', input)).data,

  renameSensor: async (id: string, name: string) =>
    (await http.put<Sensor>(`/sensors/${id}/name`, { name })).data,

  setMatterForwarding: async (id: string, value: boolean) =>
    (await http.put<Sensor>(`/sensors/${id}/matter-forwarding`, { value })).data,

  deleteSensor: async (id: string) => (await http.delete<{ id: string }>(`/sensors/${id}`)).data,
}
