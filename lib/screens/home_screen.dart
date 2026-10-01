import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_service.dart';
import '../models/task.dart';
import '../services/firestore_service.dart';
import '../widgets/task_card.dart';
import '../widgets/app_shared.dart';
import 'add_edit_task.dart';

// the app's default screen. This IS the task list for now —

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _HomeHeader(),

            // Show the list if we have tasks, otherwise show the empty state
            Expanded(
              child: StreamBuilder<List<Task>>(
                stream: FirestoreService().streamTasks(),
                builder: (context, snapshot) {
                  //Firestore initial response
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  //if something is wrong from Firestore
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error loading tasks: ${snapshot.error}'),
                    );
                  }

                  final tasks = snapshot.data ?? [];
                  return tasks.isEmpty
                      ? const _EmptyState()
                      : _TaskList(tasks: tasks);
                },
              ),
            ),
          ],
        ),
      ),

      // The + button opens the add-task form as a popup (a "bottom sheet")
      floatingActionButton: const AppAddTaskFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: const AppBottomNav(currentTab: AppTab.tasks),
    );
  }
}

/// Greeting bar at the top: today's date, greeting, and a profile icon.

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 0 && hour < 12) {
      return 'Good morning, ';
    } else if (hour >= 12 && hour < 18) {
      return 'Good afternoon, ';
    } else {
      return 'Good evening, ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // [ h e a d e r   s t r e a m ]
    // listen to live profile updates (e.g. display name edits)
    return StreamBuilder<User?>(
      stream: AuthService().userChanges,
      initialData: AuthService().currentUser,
      builder: (context, snapshot) {
        // extract user's first name with fallback
        final name = _firstName(snapshot.data);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),

          color: const Color(0xFFFCE8CB),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        _formattedDate(now).toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.star, size: 16),
                    ],
                  ),

                  //* TODO: TEMPORARY BUTTON if ever app user menu
                  IconButton(
                    tooltip: 'Log out',
                    icon: const Icon(Icons.logout),
                    onPressed: () => logoutAndReturnToRoot(context),
                  ),
                ],
              ),
              const SizedBox(height: 5),

              RichText(
                text: TextSpan(
                  style: GoogleFonts.dmSerifDisplay(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  children: [
                    TextSpan(text: _getGreeting()),
                    TextSpan(
                      text: '$name.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Color(0xFFC65A42),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // "Juan Dela Cruz" -> "Juan"; falls back if no name is set yet
  String _firstName(User? user) {
    final full = user?.displayName?.trim() ?? '';
    if (full.isEmpty) return 'there';
    return full.split(' ').first;
  }

  // Formats a date like "Monday, September 7, 2026"
  String _formattedDate(DateTime d) => DateFormat('EEEE, MMMM d, y').format(d);
}

class _TaskList extends StatelessWidget {
  final List<Task> tasks;

  const _TaskList({required this.tasks});

  // true if due today
  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // pushes done tasks to the bottom
  List<Task> _withDoneAtBottom(List<Task> input) {
    final notDone = input.where((t) => !t.isDone).toList();
    final done = input.where((t) => t.isDone).toList()
      ..sort((a, b) {
        final aTime = a.completedAt ?? DateTime(0);
        final bTime = b.completedAt ?? DateTime(0);
        return aTime.compareTo(bTime);
      });
    return [...notDone, ...done];
  }

  @override
  Widget build(BuildContext context) {
    final todayTasks = _withDoneAtBottom(
      tasks.where((t) => _isToday(t.dueDateTime)).toList(),
    );
    final otherTasks = _withDoneAtBottom(
      tasks.where((t) => !_isToday(t.dueDateTime)).toList(),
    );

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
        // section is skipped entirely (no empty header) when it has no tasks
        if (todayTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Today'),
          ...todayTasks.map((task) => _buildTaskCard(context, task)),
        ],
        if (otherTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Upcoming Tasks'),
          ...otherTasks.map((task) => _buildTaskCard(context, task)),
        ],
      ],
    );
  }

  Widget _buildTaskCard(BuildContext context, Task task) {
    return TaskCard(
      key: ValueKey(task.id),
      task: task,
      onTap: () => showAddEditTaskSheet(context, existingTask: task),
      onToggleDone: () async {
        try {
          await FirestoreService().toggleTaskDone(task);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not update task: $e')),
            );
          }
        }
      },
      onDelete: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this task?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true) return;
        if (!context.mounted) return; // guard the gap from the dialog's await

        final messenger = ScaffoldMessenger.of(
          context,
        ); // capture BEFORE the await
        await FirestoreService().softDelete(task);
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Task deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => FirestoreService().undoDelete(task),
            ),
          ),
        );
      },
    );
  }
}

/// label group task ("Today" / "Other Tasks").
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4A3427),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// What the user sees when there are no tasks.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rtl, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No tasks so far',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to add your first task',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
