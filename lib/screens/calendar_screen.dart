import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../models/task.dart';
import '../models/todo_list.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/todo_list_service.dart';
import '../widgets/task_card.dart';
import '../widgets/app_shared.dart';
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
  DateTime _selectedDay = DateTime.now();
  // Default to showing all merged tasks (Personal + Collaborative)
  String _selectedFilter = _kFilterAll;

  // strips the time so tasks on the same day group together regardless of hour
  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Task> _withDoneAtBottom(List<Task> input) {
    final notDone = input.where((t) => !t.isDone).toList();
    final done = input.where((t) => t.isDone).toList();
    return [...notDone, ...done];
  }

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
      backgroundColor: const Color(0xFFFFF8EF),
      body: SafeArea(
        // [ u b a c   m e r g e d   c a l e n d a r   s t r e a m ]
        // Streams the user's accessible collaborative lists, then merges all
        // personal + collaborative tasks with a simple list filter selector.
        child: StreamBuilder<User?>(
          stream: AuthService().authStateChanges,
          initialData: AuthService().currentUser,
          builder: (context, authSnap) {
            final uid = authSnap.data?.uid;
            return StreamBuilder<List<TodoList>>(
              key: ValueKey('lists_$uid'),
              stream: TodoListService().streamCollaborativeLists(),
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
                  stream: FirestoreService().streamAllUserAndCollabTasks(
                    collabIds,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error loading tasks: ${snapshot.error}'),
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
                      final key = _dayOnly(t.dueDateTime);
                      tasksByDay.putIfAbsent(key, () => []).add(t);
                    }

                    final selectedTasks = _withDoneAtBottom(
                      tasksByDay[_dayOnly(_selectedDay)] ?? [],
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
      color: const Color(0xFFFCE8CB),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Calendar 𖤓',
            style: GoogleFonts.dmSerifDisplay(
              textStyle: Theme.of(context).textTheme.headlineSmall,
              color: const Color.fromARGB(255, 73, 50, 41),
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
            position: PopupMenuPosition.under,
            offset: const Offset(0, 4),
            color: const Color(0xFFFFF8EF),
            constraints: BoxConstraints.tightFor(width: constraints.maxWidth),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF4A3427), width: 1),
            ),
            onSelected: (val) => setState(() => _selectedFilter = val),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: _kFilterAll,
                child: Text(
                  'All Tasks',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3427),
                  ),
                ),
              ),
              const PopupMenuItem<String>(
                value: _kFilterPersonal,
                child: Text(
                  'Personal To-Do List',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3427),
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
                      color: Color(0xFF4A3427),
                    ),
                  ),
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8EF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4A3427), width: 1),
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
                        color: Color(0xFF4A3427),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF4A3427),
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
            color: Color(0xFF4A3427),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        viewHeaderStyle: const ViewHeaderStyle(
          dayTextStyle: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        todayHighlightColor: const Color(0xFFE8873A),
        selectionDecoration: BoxDecoration(
          color: const Color(0xFF4A3427).withValues(alpha: 0.08),
          border: Border.all(color: const Color(0xFF4A3427), width: 1.5),
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
          'No tasks on this day★',
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
          task: task,
          onTap: () => showAddEditTaskSheet(context, existingTask: task),
          onToggleDone: () async {
            try {
              await FirestoreService().toggleTaskDone(task);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('could not update task: $e')),
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
            if (!context.mounted) return;

            // capture before the await — task leaves this day's list the
            // instant deletedAt is set, which can dispose this context
            final messenger = ScaffoldMessenger.of(context);
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
            color: _priorityColor(t.priority),
          ),
        )
        .toList();
  }

  // same priority palette used on TaskCard, kept local here since this
  // class only needs it to color each appointment's dot
  Color _priorityColor(Priority p) {
    switch (p) {
      case Priority.high:
        return Colors.pinkAccent;
      case Priority.medium:
        return const Color(0xFFE8873A);
      case Priority.low:
        return Colors.blueAccent;
    }
  }
}
