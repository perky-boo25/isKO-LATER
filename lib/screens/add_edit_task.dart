import 'package:flutter/material.dart';
import 'package:isko_later/services/firestore_service.dart';

import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/todo_list_service.dart';

Future<void> showAddEditTaskSheet(BuildContext context, {Task? existingTask}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // lets the sheet grow and avoid the keyboard
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    // A slightly shorter reverse animation makes drag/backdrop dismissal feel
    // responsive without looking abrupt.
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

/// The add/edit task form itself.
/// It's a StatefulWidget because the form fields change as the user types.
class AddEditTaskSheet extends StatefulWidget {
  final Task? existingTask;

  const AddEditTaskSheet({super.key, this.existingTask});

  @override
  State<AddEditTaskSheet> createState() => _AddEditTaskSheetState();
}

Color _priorityColor(Priority p) {
  switch (p) {
    case Priority.high:
      return Colors.pinkAccent;
    case Priority.medium:
      return Colors.orangeAccent;
    case Priority.low:
      return Colors.blueAccent;
  }
}

IconData tagIcon(TaskTags t) {
  switch (t) {
    case TaskTags.school:
      return Icons.school;
    case TaskTags.personal:
      return Icons.person;
    case TaskTags.others:
      return Icons.label_outline;
  }
}

class _AddEditTaskSheetState extends State<AddEditTaskSheet> {
  final _formKey = GlobalKey<FormState>(); // used to validate the form
  final _firestoreService = FirestoreService();

  late TextEditingController _titleController;
  late DateTime _dueDateTime;
  late Priority _priority;
  late TaskTags _tag;

  // true if we're editing an existing task instead of making a new one
  bool get _isEditing => widget.existingTask != null;

  // true while save() is awaiting in Firestore
  // disabling submit button during network calls
  bool _isSaving = false;

  void _dismissSheet() {
    if (!_isSaving && mounted) Navigator.of(context).pop();
  }

  void _dismissFromHandle(DragEndDetails details) {
    // A downward flick on the handle dismisses the sheet. Using the handle
    // as the gesture target avoids the form's ListView consuming the drag.
    if (details.velocity.pixelsPerSecond.dy > 250) {
      _dismissSheet();
    }
  }

  @override
  void initState() {
    super.initState();
    // fill the form with the existing task's data, or sensible defaults
    final task = widget.existingTask;
    _titleController = TextEditingController(text: task?.title ?? '');
    _dueDateTime =
        task?.dueDateTime ?? DateTime.now().add(const Duration(hours: 1));
    _priority = task?.priority ?? Priority.medium;
    _tag = task?.tag ?? TaskTags.personal;
  }

  // cleans up the controller so it doesn't leak memory
  @override
  void dispose() {
    _titleController.dispose(); // always dispose controllers
    super.dispose();
  }

  // opens date picker and updates due date, keeping the time as is
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return; // user cancelled
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

  // opens time picker and updates due time, keeping the date as is
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDateTime),
    );
    if (picked == null) return; // user cancelled
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

  // validates form and then creates/updates task
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return; // stop if title is empty

    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        // copyWith preserves the original ownerId and listId so ownership stays intact
        final updatedTask = widget.existingTask!.copyWith(
          title: _titleController.text.trim(),
          dueDateTime: _dueDateTime,
          priority: _priority,
          tag: _tag,
        );
        await _firestoreService.updateTask(updatedTask);
      } else {
        // [ act3:  t a s k   c r e a t i o n ]
        // require an active logged-in session and attach its UID as ownerId.
        // Also attach activeListId.value (null for Personal, or listId for Collaborative).
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save task: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prevents an accidental system-back dismissal while a save is in flight.
    return PopScope(
      canPop: !_isSaving,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          // Smoothly follows the keyboard instead of jumping when it appears.
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true, // sheet only takes as much height as it needs
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              children: [
                // The handle is both a close control and a dedicated swipe
                // target, so the form's ListView cannot swallow the gesture.
                Center(
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

                // title changes depending on add or edit mode
                Text(
                  _isEditing ? 'Edit Task' : 'Add Task',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Title is required'
                      : null,
                ),
                const SizedBox(height: 16),

                // tapping opens date picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                    '${_dueDateTime.year}-${_dueDateTime.month}-${_dueDateTime.day}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDate,
                ),
                const Divider(
                  color: Color.fromARGB(255, 68, 39, 10),
                  thickness: 0.75,
                  indent: 1,
                  endIndent: 1,
                ),
                // tapping opens the time picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due time'),
                  subtitle: Text(
                    TimeOfDay.fromDateTime(_dueDateTime).format(context),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: _pickTime,
                ),
                const Divider(
                  color: Color.fromARGB(255, 68, 39, 10),
                  thickness: 0.75,
                  indent: 1,
                  endIndent: 1,
                ),
                const SizedBox(height: 16),

                // priority dropdown - get from enum data model
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
                          Icon(Icons.star, size: 14, color: _priorityColor(p)),
                          const SizedBox(width: 4),
                          Text(p.name),
                        ],
                      ),
                    );
                  }).toList(),
                  selected: {_priority},
                  onSelectionChanged: (selected) =>
                      setState(() => _priority = selected.first),
                ),

                const SizedBox(height: 16),

                // tag dropdown - get from enum data model
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
                          Icon(tagIcon(t), size: 14),
                          const SizedBox(width: 4),
                          Text(t.name),
                        ],
                      ),
                    );
                  }).toList(),
                  selected: {_tag},
                  onSelectionChanged: (selected) =>
                      setState(() => _tag = selected.first),
                ),

                const SizedBox(height: 24),

                // validation + save
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC65A42),
                    foregroundColor: Colors.white,
                    side: const BorderSide(width: 1.0),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
