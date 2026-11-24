import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/input_sanitizer.dart';
import '../utils/task_helpers.dart';

Future<void> showAddEditTaskSheet(BuildContext context, {Task? existingTask}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 300),
      reverseDuration: Duration(milliseconds: 220),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => AddEditTaskSheet(existingTask: existingTask),
  );
}

// bottom-sheet form for creating or editing a task
class AddEditTaskSheet extends StatefulWidget {
  final Task? existingTask;

  const AddEditTaskSheet({super.key, this.existingTask});

  @override
  State<AddEditTaskSheet> createState() => _AddEditTaskSheetState();
}

class _AddEditTaskSheetState extends State<AddEditTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  late TextEditingController _titleController;
  late DateTime _dueDateTime;
  late Priority _priority;
  late TaskTags _tag;

  bool get _isEditing => widget.existingTask != null;
  bool _isSaving = false;

  void _dismissSheet() {
    if (!_isSaving && mounted) Navigator.of(context).pop();
  }

  void _dismissFromHandle(DragEndDetails details) {
    if (details.velocity.pixelsPerSecond.dy > 250) {
      _dismissSheet();
    }
  }

  @override
  void initState() {
    super.initState();
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.title ?? '');
    _dueDateTime =
        task?.dueDateTime ?? DateTime.now().add(const Duration(hours: 1));
    _priority = task?.priority ?? Priority.medium;
    _tag = task?.tag ?? TaskTags.personal;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;
    setState(() {
      _dueDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _dueDateTime.hour,
        _dueDateTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDateTime),
    );
    if (picked == null) return;
    setState(() {
      _dueDateTime = DateTime(
        _dueDateTime.year,
        _dueDateTime.month,
        _dueDateTime.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        final updatedTask = widget.existingTask!.copyWith(
          title: _titleController.text.trim(),
          dueDateTime: _dueDateTime,
          priority: _priority,
          tag: _tag,
        );
        await _firestoreService.updateTask(updatedTask);
      } else {
        final uid = AuthService().currentUser?.uid;
        if (uid == null || uid.isEmpty) {
          throw StateError('No active user session. Please log in again.');
        }

        final task = Task(
          id: '',
          ownerId: uid,
          listId: activeListId.value,
          title: _titleController.text.trim(),
          dueDateTime: _dueDateTime,
          priority: _priority,
          tag: _tag,
          createdAt: DateTime.now(),
        );

        await _firestoreService.addTask(task);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TaskHelpers.friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Close task form',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _dismissSheet,
                      onVerticalDragEnd: _dismissFromHandle,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  _isEditing ? 'Edit Task' : 'Add Task',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    counterText: '',
                  ),
                  validator: (value) => InputSanitizer.validateSafeText(
                    value,
                    fieldName: 'Title',
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                    DateFormat('EEEE, MMM d, yyyy').format(_dueDateTime),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _isSaving ? null : _pickDate,
                ),
                const Divider(
                  color: AppColors.espresso,
                  thickness: 0.75,
                  indent: 1,
                  endIndent: 1,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due time'),
                  subtitle: Text(
                    TimeOfDay.fromDateTime(_dueDateTime).format(context),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: _isSaving ? null : _pickTime,
                ),
                const Divider(
                  color: AppColors.espresso,
                  thickness: 0.75,
                  indent: 1,
                  endIndent: 1,
                ),
                const SizedBox(height: 16),
                Text('Priority', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<Priority>(
                  showSelectedIcon: false,
                  segments: Priority.values.map((p) {
                    return ButtonSegment<Priority>(
                      value: p,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: AppColors.priorityColor(p),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  selected: {_priority},
                  onSelectionChanged: _isSaving
                      ? null
                      : (selected) =>
                            setState(() => _priority = selected.first),
                ),
                const SizedBox(height: 16),
                Text('Tag', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<TaskTags>(
                  showSelectedIcon: false,
                  segments: TaskTags.values.map((t) {
                    return ButtonSegment<TaskTags>(
                      value: t,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppColors.tagIcon(t), size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  selected: {_tag},
                  onSelectionChanged: _isSaving
                      ? null
                      : (selected) => setState(() => _tag = selected.first),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.terracotta,
                    foregroundColor: Colors.white,
                    side: const BorderSide(width: 1.0),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEditing ? 'Save Changes' : 'Add Task',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
