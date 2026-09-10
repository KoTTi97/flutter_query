/// The header badge: "x of y synced".
///
/// Reads the *same* cache entry as the overview's unfiltered list, through
/// `select`. Two widgets, two shapes of one fetch — and this one is a leaf, so
/// a builder is the honest fit (of the four styles the binding offers, it is
/// the one that stays visible in the tree).
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../api.dart';
import '../models.dart';
import '../queries.dart';
import '../theme.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({super.key, required this.api});

  final TaskApi api;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    return AppBar(
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      title: Row(
        children: <Widget>[
          Container(
            height: 26,
            width: 26,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.checklist_rounded,
              size: 15,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 10),
          const Text('Task Manager'),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Center(
            child:
                QuerySelectBuilder<TaskListResponse, ({int synced, int total})>(
              options: syncedTasksQuery(client, api),
              builder: (context, result) => switch (result) {
                QuerySuccess(:final data) => StatusPill(
                    label: '${data.synced} of ${data.total} synced',
                    color: data.synced == data.total
                        ? AppColors.accent
                        : AppColors.muted,
                    background: data.synced == data.total
                        ? AppColors.accentSoft
                        : AppColors.ground,
                    dot: true,
                  ),
                QueryError() => const StatusPill(
                    label: 'Server offline',
                    color: AppColors.danger,
                    background: AppColors.dangerSoft,
                  ),
                QueryPending() => const SkeletonBox(width: 128, height: 22),
              },
            ),
          ),
        ),
      ],
    );
  }
}
