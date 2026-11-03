import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/task_helpers.dart';
import '../widgets/app_shared.dart';
import '../widgets/task_card.dart';
import 'add_edit_task.dart';

// Filter constants for Calendar view
const String _kFilterAll = '__all__';
const String _kFilterPersonal = '__personal__';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // [ act4: reuse single service instances across rebuilds ]
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final TodoListService _todoListService = TodoListService();

  DateTime _selectedDay = DateTime.now();
  // Default to showing all merged tasks (Personal + Collaborative)
  String _selectedFilter = _kFilterAll;

  // Filters the merged task list based on the user's selected filter dropdown
  List<Task> _applyListFilter(List<Task> allTasks, String filter) {
    if (filter == _kFilterAll) return allTasks;
    if (filter == _kFilterPersonal) {
      return allTasks.where((t) => t.listId == null).toList();
    }
    return allTasks.where((t) => t.listId == filter).toList();
  }

  String _labelForFilter(String activeFilter, List<TodoList> collabLists) {
    if (activeFilter == _kFilterAll) return 'All Tasks';
    if (activeFilter == _kFilterPersonal) return 'Personal To-Do List';
    final match = collabLists.where((l) => l.id == activeFilter).firstOrNull;
    return match?.name ?? 'All Tasks';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamSurface,
      body: SafeArea(
        // [ u b a c   m e r g e d   c a l e n d a r   s t r e a m ]
        // Streams the user's accessible collaborative lists, then merges all
        // personal + collaborative tasks with a simple list filter selector.
        child: StreamBuilder<User?>(
          stream: _authService.authStateChanges,
          initialData: _authService.currentUser,
          builder: (context, authSnap) {
            final uid = authSnap.data?.uid;
            return StreamBuilder<List<TodoList>>(
              key: ValueKey('lists_$uid'),
              stream: _todoListService.streamCollaborativeLists(),
              builder: (context, listSnap) {
                final collabLists = listSnap.data ?? [];
                final collabIds = collabLists.map((l) => l.id).toList();

                // If the user was filtering by a collab list that no longer exists,
                // fall back to showing All Tasks
                final activeFilter =
                    (_selectedFilter == _kFilterAll ||
                        _selectedFilter == _kFilterPersonal ||
                        collabIds.contains(_selectedFilter))
                    ? _selectedFilter
                    : _kFilterAll;

                return StreamBuilder<List<Task>>(
                  key: ValueKey('${uid}_${collabIds.join(",")}'),
                  stream: _firestoreService.streamAllUserAndCollabTasks(
                    collabIds,
                  ),
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
                              fallback: 'Could not load calendar tasks.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.errorRed),
                          ),
                        ),
                      );
                    }

                    final allTasks = snapshot.data ?? [];
                    final filteredTasks = _applyListFilter(
                      allTasks,
                      activeFilter,
                    );

                    // grouped by day, used to filter the list under the calendar
                    final Map<DateTime, List<Task>> tasksByDay = {};
                    for (final t in filteredTasks) {
                      final key = TaskHelpers.dayOnly(t.dueDateTime);
                      tasksByDay.putIfAbsent(key, () => []).add(t);
                    }

                    final selectedTasks = TaskHelpers.sortWithDoneAtBottom(
                      tasksByDay[TaskHelpers.dayOnly(_selectedDay)] ?? [],
                    );

                    return Column(
                      children: [
                        _buildHeader(),
                        _buildFilterBar(collabLists, activeFilter),
                        _buildCalendar(filteredTasks),
                        const SizedBox(height: 8),
                        Expanded(child: _buildTaskList(selectedTasks)),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: const AppAddTaskFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: const AppBottomNav(currentTab: AppTab.calendar),
    );
  }

  // "calendar" title bar kept clean as in Lab 1
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      color: AppColors.creamHeader,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Calendar 𖤓',
            style: GoogleFonts.dmSerifDisplay(
              textStyle: Theme.of(context).textTheme.headlineSmall,
              color: AppColors.espresso,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Normal dropdown that always opens strictly downward below the field
  // (using PopupMenuPosition.under so selecting a group never covers the header)
  Widget _buildFilterBar(List<TodoList> collabLists, String activeFilter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return PopupMenuButton<String>(
            tooltip: 'Filter tasks by list',
            position: PopupMenuPosition.under,
            offset: const Offset(0, 4),
            color: AppColors.creamSurface,
            constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.espresso, width: 1),
            ),
            onSelected: (val) => setState(() => _selectedFilter = val),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: _kFilterAll,
                child: Text(
                  'All Tasks',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: _kFilterPersonal,
                child: Text(
                  'Personal To-Do List',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              ...collabLists.map(
                (list) => PopupMenuItem<String>(
                  value: list.id,
                  child: Text(
                    list.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.espresso,
                    ),
                  ),
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.creamSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.espresso, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _labelForFilter(activeFilter, collabLists),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.espresso,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.espresso,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // syncfusion month view — dots are drawn automatically per day based on
  // how many appointments (tasks) fall on that date in the data source
  Widget _buildCalendar(List<Task> tasks) {
    return Container(
      height: 360,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SfCalendar(
        view: CalendarView.month,
        dataSource: _TaskDataSource(tasks),
        initialSelectedDate: _selectedDay,
        showNavigationArrow: true,
        showDatePickerButton: false,
        headerStyle: const CalendarHeaderStyle(
          textAlign: TextAlign.center,
          backgroundColor: Color.fromARGB(255, 255, 227, 205),
          textStyle: TextStyle(
            color: AppColors.espresso,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        viewHeaderStyle: const ViewHeaderStyle(
          dayTextStyle: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        todayHighlightColor: const Color(0xFFE8873A),
        selectionDecoration: BoxDecoration(
          color: AppColors.espresso.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.espresso, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        monthViewSettings: const MonthViewSettings(
          showAgenda: false, // we render our own task list below instead
          appointmentDisplayMode:
              MonthAppointmentDisplayMode.indicator, // dots, not bars
          showTrailingAndLeadingDates: true,
          monthCellStyle: MonthCellStyle(
            textStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
          ),
        ),
        onTap: (CalendarTapDetails details) {
          if (details.date == null) return;
          setState(() => _selectedDay = details.date!);
        },
      ),
    );
  }

  // tasks due on whichever day is currently selected
  Widget _buildTaskList(List<Task> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          'No tasks on this day ★',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 90),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final task = tasks[i];
        return TaskCard(
          key: ValueKey(task.id),
          task: task,
          onTap: () => showAddEditTaskSheet(context, existingTask: task),
          onToggleDone: () => TaskHelpers.toggleTaskDone(
            context,
            task: task,
            service: _firestoreService,
          ),
          onDelete: () => TaskHelpers.confirmAndSoftDelete(
            context,
            task: task,
            service: _firestoreService,
          ),
        );
      },
    );
  }
}

// adapts our Task list into Appointment objects, which is what drives
// syncfusion's dot markers under each day in month view
class _TaskDataSource extends CalendarDataSource {
  _TaskDataSource(List<Task> tasks) {
    appointments = tasks
        .map(
          (t) => Appointment(
            startTime: t.dueDateTime,
            endTime: t.dueDateTime.add(const Duration(hours: 1)),
            subject: t.title,
            // [ act4: uses centralized AppColors.priorityColor ]
            color: AppColors.priorityColor(t.priority),
          ),
        )
        .toList();
  }
}
