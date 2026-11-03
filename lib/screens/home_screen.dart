import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/task_helpers.dart';
import '../widgets/app_shared.dart';
import '../widgets/list_switcher_bar.dart';
import '../widgets/task_card.dart';
import 'add_edit_task.dart';

// the app's default screen. This IS the task list —
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // [ act4: reuse single service instances instead of recreating per build/tap ]
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeHeader(authService: _authService),

            // [ act3: u b a c   s e s s i o n - s c o p e d   s t r e a m ]
            // listen to authStateChanges and key the task StreamBuilder by uid
            // so logging out of Account A and into Account B immediately resets
            // the stream and shows only Account B's tasks
            Expanded(
              child: StreamBuilder<User?>(
                stream: _authService.authStateChanges,
                initialData: _authService.currentUser,
                builder: (context, authSnap) {
                  final uid = authSnap.data?.uid;
                  return Column(
                    children: [
                      // [ c o l l a b o r a t i v e   l i s t   s w i t c h e r ]
                      // Placed in the main body above the task list
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                        child: ListSwitcherBar(currentUid: uid ?? ''),
                      ),

                      Expanded(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: activeListId,
                          builder: (context, selectedListId, _) {
                            return StreamBuilder<List<Task>>(
                              key: ValueKey('${uid}_$selectedListId'),
                              stream: _firestoreService.streamTasks(
                                listId: selectedListId,
                              ),
                              builder: (context, snapshot) {
                                // Firestore initial response
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                // [ act4: friendly error state instead of raw exception ]
                                if (snapshot.hasError) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        TaskHelpers.friendlyError(
                                          snapshot.error!,
                                          fallback:
                                              'Could not load tasks right now.',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.errorRed,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final tasks = snapshot.data ?? [];
                                return tasks.isEmpty
                                    ? const _EmptyState()
                                    : _TaskList(
                                        tasks: tasks,
                                        firestoreService: _firestoreService,
                                      );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
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

/// Greeting bar at the top: today's date and personalized time-of-day greeting.
class _HomeHeader extends StatelessWidget {
  final AuthService authService;

  const _HomeHeader({required this.authService});

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
      stream: authService.userChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        // extract user's first name with fallback
        final name = _firstName(snapshot.data);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          color: AppColors.creamHeader,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _formattedDate(now).toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.star, size: 16),
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
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: AppColors.terracotta,
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
  final FirestoreService firestoreService;

  const _TaskList({required this.tasks, required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // [ act4: 4 mutually exclusive sections so overdue & completed tasks are clearly grouped ]
    // 1. Overdue: incomplete tasks whose dueDateTime has already passed
    final overdueTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks.where((t) => TaskHelpers.isOverdue(t, now: now)).toList(),
    );

    // 2. Today: incomplete tasks due later today
    final todayTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks
          .where(
            (t) =>
                !t.isDone &&
                !TaskHelpers.isOverdue(t, now: now) &&
                TaskHelpers.isToday(t.dueDateTime, now: now),
          )
          .toList(),
    );

    // 3. Upcoming Tasks: incomplete tasks due on a future calendar day (tomorrow onward)
    final upcomingTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks
          .where(
            (t) => !t.isDone && TaskHelpers.isFutureDay(t.dueDateTime, now: now),
          )
          .toList(),
    );

    // 4. Completed Tasks: all finished tasks, ordered most recently completed first
    final completedTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks.where((t) => t.isDone).toList(),
    );

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
        // each section is skipped entirely (no empty header) when it has no tasks
        if (overdueTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Overdue', color: AppColors.errorRed),
          ...overdueTasks.map((task) => _buildTaskCard(context, task)),
        ],
        if (todayTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Today'),
          ...todayTasks.map((task) => _buildTaskCard(context, task)),
        ],
        if (upcomingTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Upcoming Tasks'),
          ...upcomingTasks.map((task) => _buildTaskCard(context, task)),
        ],
        if (completedTasks.isNotEmpty) ...[
          const _SectionHeader(title: 'Completed Tasks'),
          ...completedTasks.map((task) => _buildTaskCard(context, task)),
        ],
      ],
    );
  }

  Widget _buildTaskCard(BuildContext context, Task task) {
    return TaskCard(
      key: ValueKey(task.id),
      task: task,
      onTap: () => showAddEditTaskSheet(context, existingTask: task),
      onToggleDone: () => TaskHelpers.toggleTaskDone(
        context,
        task: task,
        service: firestoreService,
      ),
      onDelete: () => TaskHelpers.confirmAndSoftDelete(
        context,
        task: task,
        service: firestoreService,
      ),
    );
  }
}

/// label group task ("Overdue" / "Today" / "Upcoming Tasks" / "Completed Tasks").
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, this.color = AppColors.espresso});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: color,
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
