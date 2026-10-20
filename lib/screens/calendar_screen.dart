import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../models/task.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/task_card.dart';
import '../widgets/app_shared.dart';
import 'add_edit_task.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDay = DateTime.now();

  // strips the time so tasks on the same day group together regardless of hour
  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Task> _withDoneAtBottom(List<Task> input) {
    final notDone = input.where((t) => !t.isDone).toList();
    final done = input.where((t) => t.isDone).toList();
    return [...notDone, ...done];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8EF),
      body: SafeArea(
        // [ act3: u b a c   s e s s i o n - s c o p e d   c a l e n d a r ]
        // rebuilds the task StreamBuilder when the active user changes
        // so calendar dots and daily tasks are strictly scoped to currentUser
        child: StreamBuilder<User?>(
          stream: AuthService().authStateChanges,
          initialData: AuthService().currentUser,
          builder: (context, authSnap) {
            final uid = authSnap.data?.uid;
            return StreamBuilder<List<Task>>(
              key: ValueKey(uid),
              // reuses the same live, non-deleted task stream as home_screen
              stream: FirestoreService().streamTasks(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading tasks: ${snapshot.error}'),
                  );
                }

                final tasks = snapshot.data ?? [];

                // grouped by day, used to filter the list under the calendar
                final Map<DateTime, List<Task>> tasksByDay = {};
                for (final t in tasks) {
                  final key = _dayOnly(t.dueDateTime);
                  tasksByDay.putIfAbsent(key, () => []).add(t);
                }

                final selectedTasks = _withDoneAtBottom(
                  tasksByDay[_dayOnly(_selectedDay)] ?? [],
                );

                return Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildCalendar(tasks),
                    const SizedBox(height: 8),
                    Expanded(child: _buildTaskList(selectedTasks)),
                  ],
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

  // "calendar" title bar with a notification icon placeholder
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

  // syncfusion month view — dots are drawn automatically per day based on
  // how many appointments (tasks) fall on that date in the data source
  Widget _buildCalendar(List<Task> tasks) {
    return Container(
      height: 380,
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
