/// The overview: search, project filter, refresh, create, delete — and the rows.
///
/// Two of the binding's four styles earn their place here:
///
/// * the screen holds a **`QueryController`** for the list, because the toolbar
///   and the body are siblings that both need it (refresh disabled while
///   fetching, error panel, the rows). One controller and two small
///   `ListenableBuilder`s beat one builder wrapping the whole screen.
/// * each row uses **`context.query`**, because rows read *different* keys and
///   that style rebuilds only the row whose task changed.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../queries.dart';
import '../theme.dart';

/// The projects the backend actually uses.
const List<String> projects = <String>[
  'all',
  'Inbox',
  'Website',
  'Admin',
  'Errands',
];

IconData iconFor(Priority priority) => switch (priority) {
      Priority.low => Icons.keyboard_arrow_down,
      Priority.normal => Icons.drag_handle,
      Priority.high => Icons.keyboard_double_arrow_up,
    };

class TaskOverview extends StatefulWidget {
  const TaskOverview({super.key, required this.api});

  final TaskApi api;

  @override
  State<TaskOverview> createState() => _TaskOverviewState();
}

class _TaskOverviewState extends State<TaskOverview> {
  QueryController<TaskListResponse, TaskListResponse>? _list;
  TaskFilters? _filters;
  final TextEditingController _search = TextEditingController();

  QueryClient get _client => QueryClientProvider.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final filters = AppScope.of(context).filters;
    final options = taskListQuery(_client, widget.api, filters);
    if (_list == null) {
      _list = QueryController<TaskListResponse, TaskListResponse>(
        _client,
        options,
      );
    } else if (filters != _filters) {
      // A changed filter re-keys the list. The observer switches queries in
      // place; the previous entry stays cached and is garbage-collected on its
      // own schedule.
      _list!.setOptions(options);
    }
    _filters = filters;
  }

  @override
  void dispose() {
    _list?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_search.text != app.search) {
      _search.text = app.search;
    }

    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Text(
              'Tasks',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              'Tasks on the demo backend. It is deliberately slow — about '
              '900 ms a list fetch — so you can watch the cache work.',
              style: mutedText,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: app.setSearch,
                    decoration: const InputDecoration(
                      hintText: 'Search tasks…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      prefixIconConstraints:
                          BoxConstraints(minWidth: 40, minHeight: 36),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _RoomFilter(value: app.project, onChanged: app.setProject),
                const SizedBox(width: 6),
                // The refresh button needs `isFetching` from the same query the
                // body renders — the reason the controller sits on the State.
                ListenableBuilder(
                  listenable: _list!,
                  builder: (context, _) {
                    final fetching = _list!.value.isFetching;
                    return IconButton(
                      tooltip: 'Reload',
                      onPressed: fetching ? null : () => _list!.refetch(),
                      icon: fetching
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.muted,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 20),
                    );
                  },
                ),
                _CreateTaskButton(api: widget.api),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _list!,
              builder: (context, _) => switch (_list!.value) {
                // The skeleton is only for the first load: a later refetch keeps
                // the rows on screen and shows the quiet spinner in the toolbar.
                // That is `status` and `fetchStatus` being different questions.
                QueryPending() => const _ListSkeleton(),
                QueryError(:final error, staleData: null) =>
                  _ErrorPanel(error: error, onRetry: () => _list!.refetch()),
                QuerySuccess(:final data) ||
                QueryError(staleData: final data!) =>
                  _TaskList(tasks: data.tasks, api: widget.api),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomFilter extends StatelessWidget {
  const _RoomFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(10),
            icon: const Icon(Icons.expand_more, size: 18),
            style: const TextStyle(fontSize: 14, color: AppColors.text),
            onChanged: (project) => onChanged(project ?? 'all'),
            items: <DropdownMenuItem<String>>[
              for (final project in projects)
                DropdownMenuItem<String>(
                  value: project,
                  child: Text(project == 'all' ? 'All projects' : project),
                ),
            ],
          ),
        ),
      );
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks, required this.api});

  final List<Task> tasks;
  final TaskApi api;

  @override
  Widget build(BuildContext context) =>
      MutationBuilder<String, String, ListSnapshot>(
        options: deleteTaskMutation(QueryClientProvider.of(context), api),
        // The builder sits above the empty state on purpose: deleting the
        // last visible task empties the list optimistically, and if the
        // empty state replaced the builder, the rollback would still run but
        // its failure notice would be lost with the unmounted mutation.
        builder: (context, delete) => Column(
          children: <Widget>[
            if (delete.value case MutationError(:final error))
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Notice(text: '$error'),
              ),
            Expanded(
              child: tasks.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      itemCount: tasks.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) => TaskRow(
                        key: ValueKey<String>(tasks[index].id),
                        id: tasks[index].id,
                        api: api,
                        onDelete: () => delete.mutate(tasks[index].id),
                      ),
                    ),
            ),
          ],
        ),
      );
}

/// One row.
///
/// Subscribes to the same per-task query the detail screen uses, so a rename
/// invalidating that one key updates this row too — no list refetch, and
/// nothing to wire between the two screens.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.id,
    required this.api,
    required this.onDelete,
  });

  final String id;
  final TaskApi api;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final task = context.query(taskQuery(client, api, id)).dataOrNull;
    if (task == null) {
      return const SizedBox.shrink();
    }

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: () => AppScope.of(context).openTask(id),
      child: Row(
        children: <Widget>[
          IconTile(icon: iconFor(task.priority), dimmed: !task.synced),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.name,
                  style: titleText.copyWith(
                    color: task.synced ? AppColors.text : AppColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _MetaLine(task: task),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (task.reminderPending)
            const StatusPill(
              label: 'confirming',
              color: AppColors.warning,
              background: AppColors.warningSoft,
              dot: true,
            )
          else if (!task.synced)
            const StatusPill(label: 'not synced')
          else if (task.displayedReminder)
            const StatusPill(
              label: 'reminder',
              color: AppColors.accent,
              background: AppColors.accentSoft,
            ),
          IconButton(
            tooltip: 'Delete ${task.name}',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final low = task.progress < 20;
    return DefaultTextStyle(
      style: mutedText.copyWith(fontSize: 12.5),
      child: Row(
        children: <Widget>[
          Text(task.priority.label),
          const _Dot(),
          Text(task.project),
          const _Dot(),
          Text(
            '${task.progress} %',
            style: mutedText.copyWith(
              fontSize: 12.5,
              color: low ? AppColors.danger : AppColors.muted,
              fontWeight: low ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text('·'),
      );
}

class _CreateTaskButton extends StatelessWidget {
  const _CreateTaskButton({required this.api});

  final TaskApi api;

  @override
  Widget build(BuildContext context) =>
      MutationBuilder<Task, CreateInput, void>(
        options: createTaskMutation(QueryClientProvider.of(context), api),
        builder: (context, create) => IconButton(
          tooltip: 'New task',
          onPressed: create.value.isPending
              ? null
              : () => create.mutate((
                    name: 'New task',
                    project: null,
                    priority: null,
                  )),
          icon: create.value.isPending
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.muted,
                  ),
                )
              : const Icon(Icons.add, size: 20),
        ),
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
        key: const ValueKey<String>('list-skeleton'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        itemCount: 4,
        separatorBuilder: (context, _) => const SizedBox(height: 8),
        itemBuilder: (context, _) => SurfaceCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: <Widget>[
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.skeleton,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBox(width: 150, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 210, height: 11),
                ],
              ),
            ],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.inbox_outlined, size: 30, color: AppColors.muted),
            SizedBox(height: 10),
            Text('No tasks found.', style: mutedText),
          ],
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SurfaceCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off, size: 26, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: titleText,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Is the backend running on port 5174?',
                  style: mutedText,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
}
