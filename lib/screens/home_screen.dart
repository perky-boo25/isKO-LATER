import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import '../widgets/app_shared.dart';
import '../widgets/list_switcher_bar.dart';
import '../widgets/task_card.dart';
import 'add_edit_task.dart';

// default screen displaying the user's personal or shared task list
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeHeader(authService: _authService),

            // key the task stream by uid so switching accounts resets the list
            Expanded(
              child: Responsive.constrainWidth(
                context,
                child: StreamBuilder<User?>(
                  stream: _authService.authStateChanges,
                  initialData: _authService.currentUser,
                  builder: (context, authSnap) {
                    final uid = authSnap.data?.uid;
                    return Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 4),
                          child: ListSwitcherBar(currentUid: uid ?? ''),
                        ),
                        Expanded(child: _buildTaskStream(uid)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: const AppAddTaskFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: const AppBottomNav(currentTab: AppTab.tasks),
    );
  }

  Widget _buildTaskStream(String? uid) {
    return ValueListenableBuilder<String?>(
      valueListenable: activeListId,
      builder: (context, selectedListId, _) {
        return StreamBuilder<List<Task>>(
          key: ValueKey('${uid}_$selectedListId'),
          stream: _firestoreService.streamTasks(listId: selectedListId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    TaskHelpers.friendlyError(
                      snapshot.error!,
                      fallback: 'Could not load tasks right now.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.errorRed),
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
    );
  }
}

// top banner with today's date and personalized greeting
class _HomeHeader extends StatelessWidget {
  final AuthService authService;

  const _HomeHeader({required this.authService});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 12) return 'Good morning, ';
    if (hour >= 12 && hour < 18) return 'Good afternoon, ';
    return 'Good evening, ';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return StreamBuilder<User?>(
      stream: authService.userChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        final name = _firstName(snapshot.data);

        return Container(
          width: double.infinity,
          padding: Responsive.headerPadding(context),
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
                        fontSize: Responsive.isNarrow(context) ? 11.5 : 13,
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
                    fontSize: Responsive.headerTitleSize(context),
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

  String _firstName(User? user) {
    final full = user?.displayName?.trim() ?? '';
    if (full.isEmpty) return 'there';
    return full.split(' ').first;
  }

  String _formattedDate(DateTime d) => DateFormat('EEEE, MMMM d, y').format(d);
}

class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  final FirestoreService firestoreService;

  const _TaskList({required this.tasks, required this.firestoreService});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // group tasks into 4 clear sections: Overdue, Today, Upcoming, and Completed
    final overdueTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks.where((t) => TaskHelpers.isOverdue(t, now: now)).toList(),
    );
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
    final upcomingTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks
          .where(
            (t) => !t.isDone && TaskHelpers.isFutureDay(t.dueDateTime, now: now),
          )
          .toList(),
    );
    final completedTasks = TaskHelpers.sortWithDoneAtBottom(
      tasks.where((t) => t.isDone).toList(),
    );

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      children: [
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader({required this.title, this.color = AppColors.espresso});

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 8),
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
