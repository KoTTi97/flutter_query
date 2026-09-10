/// The detail screen: rename with rollback, and the reminder switch whose
/// write the scheduler confirms seconds later.
///
/// Uses the binding's **`QueryMixin`**, because this screen is stateful anyway
/// (the rename field needs a `TextEditingController`) and the mixin puts the
/// query and both mutations flat at the top of `build`, with the `State` owning
/// their lifetime.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../models.dart';
import '../queries.dart';
import '../theme.dart';
import 'overview.dart' show iconFor;

class TaskDetail extends StatefulWidget {
  const TaskDetail({super.key, required this.id, required this.api});

  final String id;
  final TaskApi api;

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> with QueryMixin {
  final TextEditingController _name = TextEditingController();

  /// Which task the field was filled for.
  String? _nameFor;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _syncName(QueryClient client, String id) {
    if (!mounted) return;
    final name = client.getQueryData<Task>(TaskKeys.detail(id))?.name;
    if (name != null) _name.text = name;
  }

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);

    final task = watchQuery(taskQuery(client, widget.api, widget.id));
    final rename = watchMutation(renameTaskMutation(client, widget.api));
    final matter = watchMutation(setReminderMutation(client, widget.api));

    final data = task.dataOrNull;
    if (data != null && _nameFor != data.id) {
      _name.text = data.name;
      _nameFor = data.id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: AppScope.of(context).closeTask),
        title: const Text('All tasks'),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: ContentWidth(
        child: switch (task) {
          // In practice this is almost never seen: opening a task from the
          // overview renders from the entry the list already seeded. It shows
          // up when a detail screen is the first thing loaded.
          QueryPending() => const _DetailSkeleton(),
          QueryError(:final error, staleData: null) => _DetailError('$error'),
          QuerySuccess(:final data) ||
          QueryError(staleData: final data!) =>
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: <Widget>[
                _Hero(task: data),
                const SizedBox(height: 14),
                if (rename.value case MutationError(:final error)) ...<Widget>[
                  Notice(text: '$error'),
                  const SizedBox(height: 14),
                ],
                _RenameCard(
                  controller: _name,
                  pending: rename.value.isPending,
                  // A failed submit's banner goes away as soon as the user
                  // edits again.
                  onChanged: rename.value.isError ? rename.reset : null,
                  onSubmit: () => rename.mutate(
                    (id: data.id, name: _name.text.trim()),
                    // Once the rename has settled, the field shows what the
                    // cache holds: the submitted name after a success, the old
                    // one after a rollback.
                    callbacks: MutateCallbacks<Task, RenameInput, TaskSnapshot>(
                      onSettled: (_, __, ___, ____, _____) =>
                          _syncName(client, data.id),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ReminderCard(
                  task: data,
                  // Locked for the whole confirmation window, not only while
                  // the write is in flight — a second flip before the
                  // scheduler has confirmed the first would race the poll.
                  pending: data.reminderPending || matter.value.isPending,
                  onChanged: (value) =>
                      matter.mutate((id: data.id, value: value)),
                ),
                const SizedBox(height: 14),
                _FactsCard(task: data),
              ],
            ),
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: <Widget>[
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: task.synced ? AppColors.accentSoft : AppColors.ground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                iconFor(task.priority),
                size: 26,
                color: task.synced ? AppColors.accent : AppColors.muted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    task.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${task.priority.label} · ${task.project}',
                      style: mutedText),
                ],
              ),
            ),
            if (task.reminderPending)
              const StatusPill(
                label: 'confirming',
                color: AppColors.warning,
                background: AppColors.warningSoft,
                dot: true,
              )
            else if (!task.synced)
              const StatusPill(label: 'not synced'),
          ],
        ),
      );
}

class _RenameCard extends StatelessWidget {
  const _RenameCard({
    required this.controller,
    required this.pending,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool pending;
  final VoidCallback? onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Name', style: titleText),
            const SizedBox(height: 3),
            const Text(
              'Shown at once and rolled back if the server refuses. The '
              'name "fail" is always refused.',
              style: mutedText,
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged == null ? null : (_) => onChanged!(),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: pending ? null : onSubmit,
                  child: pending
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Rename'),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.task,
    required this.pending,
    required this.onChanged,
  });

  final Task task;
  final bool pending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Reminder', style: titleText),
                  const SizedBox(height: 3),
                  Text(
                    task.reminderPending
                        ? 'Waiting for the scheduler…'
                        : 'Confirmed by the scheduler',
                    style: mutedText.copyWith(
                      color: task.reminderPending
                          ? AppColors.warning
                          : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (task.reminderPending)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  height: 15,
                  width: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.warning,
                  ),
                ),
              ),
            Switch(
              // `target ?? confirmed`: the requested value outranks the
              // confirmed one while a write is outstanding, which is what stops
              // the switch flickering during the poll.
              value: task.displayedReminder,
              activeTrackColor: AppColors.accent,
              onChanged: pending ? null : onChanged,
            ),
          ],
        ),
      );
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          children: <Widget>[
            _Fact(
              label: 'Progress',
              value: '${task.progress} %',
              danger: task.progress < 20,
            ),
            const Divider(),
            _Fact(
              label: 'Estimate',
              value: '${task.estimate.toStringAsFixed(2)} h',
            ),
            const Divider(),
            _Fact(label: 'Project', value: task.project),
            const Divider(),
            _Fact(
              label: 'Board',
              value: task.synced ? 'Synced' : 'Not synced',
            ),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: mutedText.copyWith(fontSize: 14)),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: danger ? AppColors.danger : AppColors.text,
              ),
            ),
          ],
        ),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: <Widget>[
          SurfaceCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppColors.skeleton,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(width: 170, height: 16),
                    SizedBox(height: 9),
                    SkeletonBox(width: 120, height: 12),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SurfaceCard(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBox(width: 90, height: 13),
                SizedBox(height: 12),
                SkeletonBox(width: double.infinity, height: 40),
              ],
            ),
          ),
        ],
      );
}

class _DetailError extends StatelessWidget {
  const _DetailError(this.message);

  final String message;

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
                Text(message, textAlign: TextAlign.center, style: titleText),
              ],
            ),
          ),
        ),
      );
}
