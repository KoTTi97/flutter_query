/// The whole cache policy of this demo lives in this file — the Dart twin of
/// `react-demo/react/src/queries.ts`. Note how small it is compared to the
/// manual reload wiring it replaces.
///
/// Shape: the list query owns *which* sensors exist, and a per-sensor query
/// owns *what each one is*. Both the overview rows and the detail screen read
/// the same per-sensor query, so invalidating one sensor key updates both
/// screens — there is no cross-cache patching to keep in sync.
library;

import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api.dart';
import 'models.dart';

/// The client-wide defaults — the twin of `main.tsx`'s `defaultOptions`.
///
/// The gateway cannot take a request storm, so the aggressive defaults are
/// turned off deliberately: no refetch when the app comes back to the
/// foreground or the network returns, and one retry instead of three. Both
/// the app and the acceptance suite build their client from this, so the
/// tests run the policy the app ships with.
const DefaultOptions demoDefaultOptions = DefaultOptions(
  queries: QueryDefaults(
    refetchOnWindowFocus: RefetchOn.never,
    refetchOnReconnect: RefetchOn.never,
    retry: RetryPolicy.times(1),
  ),
);

/// Options for a sensor-list query, shared by every caller.
///
/// They have to be shared rather than re-declared per screen: two observers on
/// one key with two different query functions is a coin flip over which one
/// actually runs, and the seeding below would silently stop happening depending
/// on which widget built first.
QueryObserverOptions<SensorListResponse, SensorListResponse> sensorListQuery(
  QueryClient client,
  SensorApi api,
  SensorFilters filters,
) =>
    QueryObserverOptions<SensorListResponse, SensorListResponse>(
      queryKey: SensorKeys.list(filters),
      queryFn: (context) async {
        final result = await api.listSensors(filters, signal: context.signal);
        // Push the list response into each per-sensor cache.
        //
        // `initialData` cannot do this job: it is only consulted when a cache
        // entry is empty, so once a row has been built, later list responses
        // have no path into that entry and the row renders its own stale copy
        // forever.
        //
        // Seeding also stamps those entries fresh, so building the rows never
        // triggers a burst of per-sensor fetches.
        for (final sensor in result.sensors) {
          client.setQueryData<Sensor>(SensorKeys.detail(sensor.id), sensor);
        }
        return result;
      },
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    );

/// Used by the header. Same key and same options as the overview's unfiltered
/// list, so this costs no extra request — `select` derives from the cache entry
/// that is already there. Two widgets, two shapes of the same data, one fetch.
QueryObserverOptions<SensorListResponse, ({int connected, int total})>
    connectedSensorsQuery(QueryClient client, SensorApi api) {
  final list = sensorListQuery(client, api, SensorFilters.all);
  return QueryObserverOptions<SensorListResponse, ({int connected, int total})>(
    queryKey: list.queryKey,
    queryFn: list.queryFn,
    staleTime: list.staleTime,
    select: (data) => (
      connected: data.sensors.where((sensor) => sensor.connected).length,
      total: data.sensors.length,
    ),
  );
}

/// Used by both the overview rows and the detail screen.
QueryObserverOptions<Sensor, Sensor> sensorQuery(
  QueryClient client,
  SensorApi api,
  String id,
) {
  ({QueryKey key, Sensor match})? findInLists() {
    for (final (key, data) in client.getQueriesData<SensorListResponse>(
      filters: QueryFilters(queryKey: SensorKeys.lists),
    )) {
      for (final sensor in data?.sensors ?? const <Sensor>[]) {
        if (sensor.id == id) {
          return (key: key, match: sensor);
        }
      }
    }
    return null;
  }

  final seed = findInLists();

  return QueryObserverOptions<Sensor, Sensor>(
    queryKey: SensorKeys.detail(id),
    queryFn: (context) => api.getSensor(id, signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
    // Fallback seed for the case where a sensor is opened before any list
    // response has seeded it. Inheriting the list's timestamp matters: dated
    // data must not look freshly fetched, or it would never revalidate.
    initialData:
        seed == null ? null : InitialData<Sensor>.compute(() => seed.match),
    initialDataUpdatedAt: seed == null
        ? null
        : client.getQueryState<SensorListResponse>(seed.key)?.dataUpdatedAt,
    // While the device has an unconfirmed write outstanding, poll until it
    // settles. The poll must survive the app losing focus, otherwise a
    // confirmation that lands while the user glances away is never picked up.
    refetchInterval: RefetchInterval.dynamic((query) {
      final sensor = query.state.data;
      return sensor is Sensor && sensor.matterForwardingPending
          ? const Duration(milliseconds: 500)
          : null;
    }),
    refetchIntervalInBackground: true,
  );
}

/// What an optimistic write stashes so it can be rolled back.
typedef SensorSnapshot = Sensor?;

typedef RenameInput = ({String id, String name});

MutationOptions<Sensor, RenameInput, SensorSnapshot> renameSensorMutation(
  QueryClient client,
  SensorApi api,
) =>
    MutationOptions<Sensor, RenameInput, SensorSnapshot>(
      mutationKey: QueryKey(const <Object?>['renameSensor']),
      mutationFn: (input) => api.renameSensor(input.id, input.name),
      onMutate: (input) async {
        final key = SensorKeys.detail(input.id);
        // Stop in-flight fetches so a stale response cannot overwrite the
        // patch.
        await client.cancelQueries(filters: QueryFilters(queryKey: key));
        final previous = client.getQueryData<Sensor>(key);
        client.updateQueryData<Sensor>(
          key,
          (old) => old?.copyWith(name: input.name),
        );
        return previous;
      },
      onError: (_, __, input, previous) {
        if (previous != null) {
          client.setQueryData<Sensor>(SensorKeys.detail(input.id), previous);
        }
      },
      // One invalidation, one key. The detail screen and the overview row both
      // read this query, so both reconcile from the single refetch.
      onSettled: (_, __, ___, input, ____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: SensorKeys.detail(input.id)),
      ),
    );

typedef MatterInput = ({String id, bool value});

MutationOptions<Sensor, MatterInput, SensorSnapshot>
    setMatterForwardingMutation(
  QueryClient client,
  SensorApi api,
) =>
        MutationOptions<Sensor, MatterInput, SensorSnapshot>(
          mutationKey: QueryKey(const <Object?>['setMatterForwarding']),
          mutationFn: (input) =>
              api.setMatterForwarding(input.id, value: input.value),
          onMutate: (input) async {
            final key = SensorKeys.detail(input.id);
            await client.cancelQueries(filters: QueryFilters(queryKey: key));
            final previous = client.getQueryData<Sensor>(key);
            // Write the requested value to `matterForwardingTarget`, not to the
            // confirmed field, and deliberately leave `pending` alone: setting it
            // here would start the confirmation poll before the write had even
            // reached the gateway, and the first poll would read pre-write state.
            // The UI renders `target ?? matterForwarding`, so the switch still
            // flips instantly, and every later response agrees with it.
            client.updateQueryData<Sensor>(
              key,
              (old) => old?.copyWith(matterForwardingTarget: input.value),
            );
            return previous;
          },
          onError: (_, __, input, previous) {
            if (previous != null) {
              client.setQueryData<Sensor>(
                  SensorKeys.detail(input.id), previous);
            }
          },
          // The accepted response carries `pending: true`, which starts the poll
          // above. No invalidation here — the poll is already the reconciliation
          // loop.
          onSuccess: (accepted, input, ___) => client.setQueryData<Sensor>(
              SensorKeys.detail(input.id), accepted),
        );

typedef CreateInput = ({String name, String? room, SensorType? type});

/// No optimistic step, so no `onMutate` and nothing to roll back:
/// `MutationOptions.simple` is the form for that.
MutationOptions<Sensor, CreateInput, void> createSensorMutation(
  QueryClient client,
  SensorApi api,
) =>
    MutationOptions.simple(
      mutationKey: QueryKey(const <Object?>['createSensor']),
      mutationFn: (input) => api.createSensor(
          name: input.name, room: input.room, type: input.type),
      // Membership is a list concern, so this one invalidates every list.
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: SensorKeys.lists),
      ),
    );

/// Every list entry as it was before an optimistic delete.
typedef ListSnapshot = List<(QueryKey, SensorListResponse?)>;

MutationOptions<String, String, ListSnapshot> deleteSensorMutation(
  QueryClient client,
  SensorApi api,
) =>
    MutationOptions<String, String, ListSnapshot>(
      mutationKey: QueryKey(const <Object?>['deleteSensor']),
      mutationFn: api.deleteSensor,
      onMutate: (id) async {
        final lists = QueryFilters(queryKey: SensorKeys.lists);
        await client.cancelQueries(filters: lists);
        final snapshot =
            client.getQueriesData<SensorListResponse>(filters: lists);
        client.updateQueriesData<SensorListResponse>(
          (old) => old?.withSensors(
            old.sensors.where((sensor) => sensor.id != id).toList(),
          ),
          filters: lists,
        );
        return snapshot;
      },
      onError: (_, __, ___, snapshot) {
        for (final (key, data)
            in snapshot ?? const <(QueryKey, SensorListResponse?)>[]) {
          if (data != null) {
            client.setQueryData<SensorListResponse>(key, data);
          }
        }
      },
      onSettled: (_, __, ___, id, ____) async {
        client.removeQueries(
            filters: QueryFilters(queryKey: SensorKeys.detail(id)));
        await client.invalidateQueries(
          filters: QueryFilters(queryKey: SensorKeys.lists),
        );
      },
    );
