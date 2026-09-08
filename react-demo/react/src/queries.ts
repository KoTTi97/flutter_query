// The whole cache policy of this demo lives in this file. Note how small it is
// compared to the manual reload wiring it replaces.
//
// Shape: the list query owns *which* sensors exist, and a per-sensor query owns
// *what each one is*. Both the overview rows and the detail screen read the same
// per-sensor query, so invalidating one sensor key updates both screens — there
// is no cross-cache patching to keep in sync.
//
// Keys come from the `sensorKeys` factory and requests from the hand-typed
// `api` client (src/api.ts) — the two things tRPC used to derive for us.

import { type QueryKey, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { Sensor, SensorFilters, SensorListResponse } from '../shared/types.ts'
import { api, type CreateSensorInput, sensorKeys } from './api.ts'

/** The unfiltered list. Anything asking for "all sensors" must use this exact
 *  object so it lands on the same query key and shares the one cache entry. */
export const ALL_SENSORS: SensorFilters = { search: '', room: 'all' }

/**
 * Options for a sensor-list query, shared by every caller.
 *
 * They have to be shared rather than re-declared per component: two observers on
 * one key with two different queryFns is a coin flip over which one actually
 * runs, and the seeding below would silently stop happening depending on which
 * component mounted first.
 */
function useSensorListOptions(filters: SensorFilters) {
  const queryClient = useQueryClient()

  return {
    queryKey: sensorKeys.list(filters),
    queryFn: async ({ signal }: { signal: AbortSignal }) => {
      const result = await api.listSensors(filters, signal)
      // Push the list response into each per-sensor cache.
      //
      // initialData cannot do this job: it is only consulted when a cache entry
      // is empty, so once a row has mounted, later list responses have no path
      // into that entry and the row renders its own stale copy forever
      // (verified — a refetched rename does not show through without this).
      //
      // Seeding also stamps those entries fresh, so mounting the rows never
      // triggers a burst of per-sensor fetches.
      for (const sensor of result.sensors) {
        queryClient.setQueryData(sensorKeys.detail(sensor.id), sensor)
      }
      return result
    },
    staleTime: 45_000,
  }
}

export function useSensors(filters: SensorFilters) {
  return useQuery(useSensorListOptions(filters))
}

/**
 * Used by the header. Same key and same options as the overview's unfiltered
 * list, so this costs no extra request — `select` derives from the cache entry
 * that is already there. Two components, two different shapes of the same data,
 * one fetch.
 */
export function useConnectedSensors() {
  return useQuery({
    ...useSensorListOptions(ALL_SENSORS),
    select: (data: SensorListResponse) => ({
      connected: data.sensors.filter((sensor) => sensor.connected),
      total: data.sensors.length,
    }),
  })
}

// Used by both the overview rows and the detail screen.
export function useSensor(id: string) {
  const queryClient = useQueryClient()

  const findInLists = (): { key: QueryKey; match: Sensor } | null => {
    const entries = queryClient.getQueriesData<SensorListResponse>({
      queryKey: sensorKeys.lists(),
    })
    for (const [key, data] of entries) {
      const match = data?.sensors.find((sensor) => sensor.id === id)
      if (match) return { key, match }
    }
    return null
  }

  return useQuery({
    queryKey: sensorKeys.detail(id),
    queryFn: ({ signal }) => api.getSensor(id, signal),
    enabled: Boolean(id),
    staleTime: 45_000,
    // Fallback seed for the case where a sensor is opened before any list
    // response has seeded it. Inheriting the list's timestamp matters: dated
    // data must not look freshly fetched, or it would never revalidate.
    initialData: () => findInLists()?.match,
    initialDataUpdatedAt: () => {
      const found = findInLists()
      return found ? queryClient.getQueryState(found.key)?.dataUpdatedAt : undefined
    },
    // While the device has an unconfirmed write outstanding, poll until it
    // settles — the equivalent of the accepted-pending confirmation loop. The
    // poll must survive the tab losing focus, otherwise a confirmation that
    // lands while the user glances away is never picked up.
    refetchInterval: (query) => (query.state.data?.matterForwardingPending ? 500 : false),
    refetchIntervalInBackground: true,
  })
}

type SensorSnapshot = { previous: Sensor | undefined }

export function useRenameSensor() {
  const queryClient = useQueryClient()

  return useMutation<Sensor, Error, { id: string; name: string }, SensorSnapshot>({
    mutationFn: ({ id, name }) => api.renameSensor(id, name),
    onMutate: async ({ id, name }) => {
      const detailKey = sensorKeys.detail(id)
      // Stop in-flight fetches so a stale response cannot overwrite the patch.
      await queryClient.cancelQueries({ queryKey: detailKey })
      const previous = queryClient.getQueryData<Sensor>(detailKey)
      queryClient.setQueryData<Sensor>(detailKey, (old) => (old ? { ...old, name } : old))
      return { previous }
    },
    onError: (_error, { id }, context) => {
      if (context?.previous) {
        queryClient.setQueryData(sensorKeys.detail(id), context.previous)
      }
    },
    // One invalidation, one key. The detail screen and the overview row both
    // read this query, so both reconcile from the single refetch.
    onSettled: (_data, _error, { id }) =>
      queryClient.invalidateQueries({ queryKey: sensorKeys.detail(id) }),
  })
}

export function useSetMatterForwarding() {
  const queryClient = useQueryClient()

  return useMutation<Sensor, Error, { id: string; value: boolean }, SensorSnapshot>({
    mutationFn: ({ id, value }) => api.setMatterForwarding(id, value),
    onMutate: async ({ id, value }) => {
      const detailKey = sensorKeys.detail(id)
      await queryClient.cancelQueries({ queryKey: detailKey })
      const previous = queryClient.getQueryData<Sensor>(detailKey)
      // Write the requested value to `target`, not to the confirmed field, and
      // deliberately leave `pending` alone: setting it here would start the
      // confirmation poll before the write had even reached the gateway, and
      // the first poll would read pre-write state. The UI renders
      // `target ?? matterForwarding`, so the switch still flips instantly, and
      // every later response — the accepted one and every poll — agrees with
      // it.
      queryClient.setQueryData<Sensor>(detailKey, (old) =>
        old ? { ...old, matterForwardingTarget: value } : old,
      )
      return { previous }
    },
    onError: (_error, { id }, context) => {
      if (context?.previous) {
        queryClient.setQueryData(sensorKeys.detail(id), context.previous)
      }
    },
    // The accepted response carries pending: true, which starts the poll
    // above. No invalidation here — the poll is already the reconciliation
    // loop.
    onSuccess: (accepted, { id }) => queryClient.setQueryData(sensorKeys.detail(id), accepted),
  })
}

export function useCreateSensor() {
  const queryClient = useQueryClient()

  return useMutation<Sensor, Error, CreateSensorInput>({
    mutationFn: (input) => api.createSensor(input),
    // Membership is a list concern, so this one invalidates every list.
    onSuccess: () => queryClient.invalidateQueries({ queryKey: sensorKeys.lists() }),
  })
}

type ListSnapshot = { snapshot: [QueryKey, SensorListResponse | undefined][] }

export function useDeleteSensor() {
  const queryClient = useQueryClient()

  return useMutation<{ id: string }, Error, { id: string }, ListSnapshot>({
    mutationFn: ({ id }) => api.deleteSensor(id),
    onMutate: async ({ id }) => {
      const listKey = sensorKeys.lists()
      await queryClient.cancelQueries({ queryKey: listKey })
      const snapshot = queryClient.getQueriesData<SensorListResponse>({ queryKey: listKey })
      queryClient.setQueriesData<SensorListResponse>({ queryKey: listKey }, (old) =>
        old ? { ...old, sensors: old.sensors.filter((sensor) => sensor.id !== id) } : old,
      )
      return { snapshot }
    },
    onError: (_error, _variables, context) => {
      for (const [key, data] of context?.snapshot ?? []) {
        queryClient.setQueryData(key, data)
      }
    },
    onSettled: (_data, _error, { id }) => {
      queryClient.removeQueries({ queryKey: sensorKeys.detail(id) })
      queryClient.invalidateQueries({ queryKey: sensorKeys.lists() })
    },
  })
}

/** What the matter switch should render: a requested value outranks the
 *  confirmed one for as long as the write is outstanding. */
export const displayedMatterForwarding = (sensor: Sensor) =>
  sensor.matterForwardingTarget ?? sensor.matterForwarding
