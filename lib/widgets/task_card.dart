import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../utils/app_theme.dart';
import '../utils/task_helpers.dart';

// [ t a s k   c a r d ]
// Reusable card item displaying task title, category tag, due date/time,
// overdue status indicator, completion checkbox, priority dot, and delete action.
class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback? onTap;
  final VoidCallback? onToggleDone;
  final VoidCallback? onDelete;

  const TaskCard({
    super.key,
    required this.task,
    this.onTap,
    this.onToggleDone,
    this.onDelete,
  });

  String _formattedDueDateTime(DateTime dt) =>
      DateFormat('MMM d, yyyy h:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    final priorityLabel = '${AppColors.priorityLabel(task.priority)} priority';
    final overdue = TaskHelpers.isOverdue(task);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: Semantics(
          label: task.isDone
              ? 'Mark "${task.title}" as incomplete'
              : 'Mark "${task.title}" as completed',
          child: Checkbox(
            value: task.isDone,
            onChanged: (_) => onToggleDone?.call(),
          ),
        ),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: task.isDone
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          overdue
              ? 'OVERDUE ★ ${task.tag.name} ★ ${_formattedDueDateTime(task.dueDateTime)}'
              : '${task.tag.name} ★ ${_formattedDueDateTime(task.dueDateTime)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: overdue ? AppColors.errorRed : null,
            fontWeight: overdue ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // [ act4: accessible priority dot with tooltip & centralized color ]
            Tooltip(
              message: priorityLabel,
              child: Semantics(
                label: priorityLabel,
                child: CircleAvatar(
                  radius: 6,
                  backgroundColor: AppColors.priorityColor(task.priority),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete task',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}
