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
import '../utils/responsive.dart';
import '../utils/task_helpers.dart';
import '../widgets/app_shared.dart';
import '../widgets/task_card.dart';
import 'add_edit_task.dart';

const String _kFilterAll = '__all__';
const String _kFilterPersonal = '__personal__';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final TodoListService _todoListService = TodoListService();

  DateTime _selectedDay = DateTime.now();
  String _selectedFilter = _kFilterAll;

  // keeps the active filter valid even if a shared list was deleted
  String _resolveActiveFilter(List<String> collabIds) {
    final isKnown =
        _selectedFilter == _kFilterAll ||
        _selectedFilter == _kFilterPersonal ||
        collabIds.contains(_selectedFilter);
    return isKnown ? _selectedFilter : _kFilterAll;
  }

  List<Task> _filterTasksByList(List<Task> allTasks, String filter) {
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

  List<Task> _tasksForSelectedDay(List<Task> tasks) {
    final targetDay = TaskHelpers.dayOnly(_selectedDay);
    final matching = tasks
        .where((t) => TaskHelpers.dayOnly(t.dueDateTime) == targetDay)
        .toList();
    return TaskHelpers.sortWithDoneAtBottom(matching);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamSurface,
      body: SafeArea(
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
                return _buildMergedTasksStream(uid, collabLists);
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

  // streams personal + collaborative tasks and renders the responsive layout
  Widget _buildMergedTasksStream(String? uid, List<TodoList> collabLists) {
    final collabIds = collabLists.map((l) => l.id).toList();
    final activeFilter = _resolveActiveFilter(collabIds);

    return StreamBuilder<List<Task>>(
      key: ValueKey('${uid}_${collabIds.join(",")}'),
      stream: _firestoreService.streamAllUserAndCollabTasks(collabIds),
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

        final filteredTasks = _filterTasksByList(
          snapshot.data ?? [],
          activeFilter,
        );
        final selectedTasks = _tasksForSelectedDay(filteredTasks);

        return _buildResponsiveBody(
          context,
          collabLists: collabLists,
          activeFilter: activeFilter,
          filteredTasks: filteredTasks,
          selectedTasks: selectedTasks,
        );
      },
    );
  }

  // switches to a single scrollable page on very short/landscape screens
  Widget _buildResponsiveBody(
    BuildContext context, {
    required List<TodoList> collabLists,
    required String activeFilter,
    required List<Task> filteredTasks,
    required List<Task> selectedTasks,
  }) {
    if (Responsive.isShortViewport(context)) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          _buildHeader(context),
          Responsive.constrainWidth(
            context,
            child: Column(
              children: [
                _buildFilterBar(context, collabLists, activeFilter),
                _buildCalendar(context, filteredTasks),
                const SizedBox(height: 8),
                _buildTaskList(selectedTasks, shrinkWrap: true),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildHeader(context),
        Expanded(
          child: Responsive.constrainWidth(
            context,
            child: Column(
              children: [
                _buildFilterBar(context, collabLists, activeFilter),
                _buildCalendar(context, filteredTasks),
                const SizedBox(height: 8),
                Expanded(child: _buildTaskList(selectedTasks)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: Responsive.headerPadding(context),
      color: AppColors.creamHeader,
      child: Text(
        'Calendar 𖤓',
        style: GoogleFonts.dmSerifDisplay(
          textStyle: Theme.of(context).textTheme.headlineSmall,
          color: AppColors.espresso,
          fontSize: Responsive.headerTitleSize(context),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    List<TodoList> collabLists,
    String activeFilter,
  ) {
    final hPad = Responsive.horizontalPadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
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
              _buildFilterItem(_kFilterAll, 'All Tasks'),
              _buildFilterItem(_kFilterPersonal, 'Personal To-Do List'),
              ...collabLists.map((l) => _buildFilterItem(l.id, l.name)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

  PopupMenuItem<String> _buildFilterItem(String value, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.espresso,
        ),
      ),
    );
  }

  Widget _buildCalendar(BuildContext context, List<Task> tasks) {
    final hPad = Responsive.horizontalPadding(context);
    final compact = Responsive.isCompactHeight(context);

    return Container(
      height: Responsive.calendarHeight(context),
      margin: EdgeInsets.symmetric(horizontal: hPad),
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
        headerHeight: compact ? 36 : 42,
        headerStyle: CalendarHeaderStyle(
          textAlign: TextAlign.center,
          backgroundColor: const Color.fromARGB(255, 255, 227, 205),
          textStyle: TextStyle(
            color: AppColors.espresso,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 16 : 18,
          ),
        ),
        viewHeaderHeight: compact ? 22 : 28,
        viewHeaderStyle: const ViewHeaderStyle(
          dayTextStyle: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        todayHighlightColor: const Color(0xFFE8873A),
        selectionDecoration: BoxDecoration(
          color: AppColors.espresso.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.espresso, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        monthViewSettings: MonthViewSettings(
          showAgenda: false,
          appointmentDisplayMode: MonthAppointmentDisplayMode.indicator,
          showTrailingAndLeadingDates: true,
          monthCellStyle: MonthCellStyle(
            textStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: compact ? 13.0 : 15.0,
            ),
          ),
        ),
        onTap: (CalendarTapDetails details) {
          if (details.date == null) return;
          setState(() => _selectedDay = details.date!);
        },
      ),
    );
  }

  Widget _buildTaskList(List<Task> tasks, {bool shrinkWrap = false}) {
    if (tasks.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: shrinkWrap ? 24 : 0),
        child: Center(
          child: Text(
            'No tasks on this day ★',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.only(top: 4, bottom: shrinkWrap ? 16 : 90),
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

class _TaskDataSource extends CalendarDataSource {
  _TaskDataSource(List<Task> tasks) {
    appointments = tasks
        .map(
          (t) => Appointment(
            startTime: t.dueDateTime,
            endTime: t.dueDateTime.add(const Duration(hours: 1)),
            subject: t.title,
            color: AppColors.priorityColor(t.priority),
          ),
        )
        .toList();
  }
}
