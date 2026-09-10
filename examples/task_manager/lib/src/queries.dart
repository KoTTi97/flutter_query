/// The whole cache policy of this demo lives in this file — every staleness,
/// seeding, polling and rollback rule the app has, in about 230 lines
/// including comments. Note how small it is compared to the manual reload
/// wiring it replaces.
///
/// Shape: the list query owns *which* tasks exist, and a per-task query
/// owns *what each one is*. Both the overview rows and the detail screen read
/// the same per-task query, so invalidating one task key updates both
/// screens — there is no cross-cache patching to keep in sync.
library;

import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api.dart';
import 'models.dart';

/// The client-wide defaults.
///
/// This app deliberately turns the aggressive ones off: no refetch when it
/// comes back to the foreground or the network returns, and one retry instead
/// of three — a demo backend that answers in ~900 ms should not be asked twice
/// for the same thing every time the window regains focus. Both the app and
/// the acceptance suite build their client from this, so the tests run the
/// policy the app ships with.
const DefaultOptions appDefaultOptions = DefaultOptions(
  queries: QueryDefaults(
    refetchOnWindowFocus: RefetchOn.never,
    refetchOnReconnect: RefetchOn.never,
    retry: RetryPolicy.times(1),
  ),
);

/// Options for a task-list query, shared by every caller.
///
/// They have to be shared rather than re-declared per screen: two observers on
/// one key with two different query functions is a coin flip over which one
/// actually runs, and the seeding below would silently stop happening depending
/// on which widget built first.
QueryObserverOptions<TaskListResponse, TaskListResponse> taskListQuery(
  QueryClient client,
  TaskApi api,
  TaskFilters filters,
) =>
    QueryObserverOptions<TaskListResponse, TaskListResponse>(
      queryKey: TaskKeys.list(filters),
      queryFn: (context) async {
        final result = await api.listTasks(filters, signal: context.signal);
        // Push the list response into each per-task cache.
        //
        // `initialData` cannot do this job: it is only consulted when a cache
        // entry is empty, so once a row has been built, later list responses
        // have no path into that entry and the row renders its own stale copy
        // forever.
        //
        // Seeding also stamps those entries fresh, so building the rows never
        // triggers a burst of per-task fetches.
        for (final task in result.tasks) {
          client.setQueryData<Task>(TaskKeys.detail(task.id), task);
        }
        return result;
      },
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    );

/// Used by the header. Same key and same options as the overview's unfiltered
/// list, so this costs no extra request — `select` derives from the cache entry
/// that is already there. Two widgets, two shapes of the same data, one fetch.
QueryObserverOptions<TaskListResponse, ({int synced, int total})>
    syncedTasksQuery(QueryClient client, TaskApi api) {
  final list = taskListQuery(client, api, TaskFilters.all);
  return QueryObserverOptions<TaskListResponse, ({int synced, int total})>(
    queryKey: list.queryKey,
    queryFn: list.queryFn,
    staleTime: list.staleTime,
    select: (data) => (
      synced: data.tasks.where((task) => task.synced).length,
      total: data.tasks.length,
    ),
  );
}

/// Used by both the overview rows and the detail screen.
QueryObserverOptions<Task, Task> taskQuery(
  QueryClient client,
  TaskApi api,
  String id,
) {
  ({QueryKey key, Task match})? findInLists() {
    for (final (key, data) in client.getQueriesData<TaskListResponse>(
      filters: QueryFilters(queryKey: TaskKeys.lists),
    )) {
      for (final task in data?.tasks ?? const <Task>[]) {
        if (task.id == id) {
          return (key: key, match: task);
        }
      }
    }
    return null;
  }

  final seed = findInLists();

  return QueryObserverOptions<Task, Task>(
    queryKey: TaskKeys.detail(id),
    queryFn: (context) => api.getTask(id, signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
    // Fallback seed for the case where a task is opened before any list
    // response has seeded it. Inheriting the list's timestamp matters: dated
    // data must not look freshly fetched, or it would never revalidate.
    initialData:
        seed == null ? null : InitialData<Task>.compute(() => seed.match),
    initialDataUpdatedAt: seed == null
        ? null
        : client.getQueryState<TaskListResponse>(seed.key)?.dataUpdatedAt,
    // While the scheduler has an unconfirmed write outstanding, poll until it
    // settles. The poll must survive the app losing focus, otherwise a
    // confirmation that lands while the user glances away is never picked up.
    refetchInterval: RefetchInterval.dynamic((query) {
      final task = query.state.data;
      return task is Task && task.reminderPending
          ? const Duration(milliseconds: 500)
          : null;
    }),
    refetchIntervalInBackground: true,
  );
}

/// What an optimistic write stashes so it can be rolled back.
typedef TaskSnapshot = Task?;

typedef RenameInput = ({String id, String name});

MutationOptions<Task, RenameInput, TaskSnapshot> renameTaskMutation(
  QueryClient client,
  TaskApi api,
) =>
    MutationOptions<Task, RenameInput, TaskSnapshot>(
      mutationKey: QueryKey(const <Object?>['renameTask']),
      mutationFn: (input) => api.renameTask(input.id, input.name),
      onMutate: (input) async {
        final key = TaskKeys.detail(input.id);
        // Stop in-flight fetches so a stale response cannot overwrite the
        // patch.
        await client.cancelQueries(filters: QueryFilters(queryKey: key));
        final previous = client.getQueryData<Task>(key);
        client.updateQueryData<Task>(
          key,
          (old) => old?.copyWith(name: input.name),
        );
        return previous;
      },
      onError: (_, __, input, previous) {
        if (previous != null) {
          client.setQueryData<Task>(TaskKeys.detail(input.id), previous);
        }
      },
      // One invalidation, one key. The detail screen and the overview row both
      // read this query, so both reconcile from the single refetch.
      onSettled: (_, __, ___, input, ____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: TaskKeys.detail(input.id)),
      ),
    );

typedef ReminderInput = ({String id, bool value});

MutationOptions<Task, ReminderInput, TaskSnapshot> setReminderMutation(
  QueryClient client,
  TaskApi api,
) =>
    MutationOptions<Task, ReminderInput, TaskSnapshot>(
      mutationKey: QueryKey(const <Object?>['setReminder']),
      mutationFn: (input) => api.setReminder(input.id, value: input.value),
      onMutate: (input) async {
        final key = TaskKeys.detail(input.id);
        await client.cancelQueries(filters: QueryFilters(queryKey: key));
        final previous = client.getQueryData<Task>(key);
        // Write the requested value to `reminderTarget`, not to the
        // confirmed field, and deliberately leave `pending` alone: setting it
        // here would start the confirmation poll before the write had even
        // reached the backend, and the first poll would read pre-write state.
        // The UI renders `target ?? reminder`, so the switch still
        // flips instantly, and every later response agrees with it.
        client.updateQueryData<Task>(
          key,
          (old) => old?.copyWith(reminderTarget: input.value),
        );
        return previous;
      },
      onError: (_, __, input, previous) {
        if (previous != null) {
          client.setQueryData<Task>(TaskKeys.detail(input.id), previous);
        }
      },
      // The accepted response carries `pending: true`, which starts the poll
      // above. No invalidation here — the poll is already the reconciliation
      // loop.
      onSuccess: (accepted, input, ___) =>
          client.setQueryData<Task>(TaskKeys.detail(input.id), accepted),
    );

typedef CreateInput = ({String name, String? project, Priority? priority});

/// No optimistic step, so no `onMutate` and nothing to roll back:
/// `MutationOptions.simple` is the form for that.
MutationOptions<Task, CreateInput, void> createTaskMutation(
  QueryClient client,
  TaskApi api,
) =>
    MutationOptions.simple(
      mutationKey: QueryKey(const <Object?>['createTask']),
      mutationFn: (input) => api.createTask(
          name: input.name, project: input.project, priority: input.priority),
      // Membership is a list concern, so this one invalidates every list.
      onSuccess: (_, __, ___) => client.invalidateQueries(
        filters: QueryFilters(queryKey: TaskKeys.lists),
      ),
    );

/// Every list entry as it was before an optimistic delete.
typedef ListSnapshot = List<(QueryKey, TaskListResponse?)>;

MutationOptions<String, String, ListSnapshot> deleteTaskMutation(
  QueryClient client,
  TaskApi api,
) =>
    MutationOptions<String, String, ListSnapshot>(
      mutationKey: QueryKey(const <Object?>['deleteTask']),
      mutationFn: api.deleteTask,
      onMutate: (id) async {
        final lists = QueryFilters(queryKey: TaskKeys.lists);
        await client.cancelQueries(filters: lists);
        final snapshot =
            client.getQueriesData<TaskListResponse>(filters: lists);
        client.updateQueriesData<TaskListResponse>(
          (old) => old?.withTasks(
            old.tasks.where((task) => task.id != id).toList(),
          ),
          filters: lists,
        );
        return snapshot;
      },
      onError: (_, __, ___, snapshot) {
        for (final (key, data)
            in snapshot ?? const <(QueryKey, TaskListResponse?)>[]) {
          if (data != null) {
            client.setQueryData<TaskListResponse>(key, data);
          }
        }
      },
      onSettled: (_, __, ___, id, ____) async {
        client.removeQueries(
            filters: QueryFilters(queryKey: TaskKeys.detail(id)));
        await client.invalidateQueries(
          filters: QueryFilters(queryKey: TaskKeys.lists),
        );
      },
    );
