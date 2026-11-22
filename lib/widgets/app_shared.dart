import 'package:flutter/material.dart';

import '../screens/add_edit_task.dart';
import '../screens/calendar_screen.dart';
import '../screens/profile_screen.dart';
import '../services/auth_service.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';
import '../utils/responsive.dart';
import 'confirm_dialog.dart';

enum AppTab { tasks, calendar, profile }

// prompts confirmation, resets active list state, and signs out to root
Future<void> logoutAndReturnToRoot(BuildContext context) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Log out?',
    message: 'Are you sure you want to sign out of your IsKO-LATER account?',
    confirmLabel: 'Log out',
    icon: Icons.logout_rounded,
    accentColor: AppColors.logoutAmber,
  );

  if (!confirmed || !context.mounted) return;

  final navigator = Navigator.of(context);
  activeListId.value = null;

  await AuthService().logout();
  navigator.popUntil((route) => route.isFirst);
}

class AppAddTaskFAB extends StatelessWidget {
  const AppAddTaskFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showAddEditTaskSheet(context),
      backgroundColor: AppColors.terracotta,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text(
        'Add Task',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    );
  }
}

class AppBottomNav extends StatelessWidget {
  final AppTab currentTab;

  const AppBottomNav({super.key, required this.currentTab});

  // keeps stack depth at most 2 (HomeScreen -> active tab) so Back always returns to Tasks
  void _navigateToTab(BuildContext context, AppTab target) {
    if (target == currentTab) return;

    final navigator = Navigator.of(context);
    if (target == AppTab.tasks) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    final Widget screen = target == AppTab.calendar
        ? const CalendarScreen()
        : const ProfileScreen();
    final route = MaterialPageRoute(builder: (_) => screen);

    if (currentTab == AppTab.tasks) {
      navigator.push(route);
    } else {
      navigator.pushReplacement(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = Responsive.isCompactHeight(context);

    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.creamHeader,
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.list_alt,
              label: 'Tasks',
              selected: currentTab == AppTab.tasks,
              onTap: () => _navigateToTab(context, AppTab.tasks),
            ),
            _NavItem(
              icon: Icons.calendar_month_outlined,
              label: 'Calendar',
              selected: currentTab == AppTab.calendar,
              onTap: () => _navigateToTab(context, AppTab.calendar),
            ),
            _NavItem(
              icon: Icons.person_outline,
              label: 'Profile',
              selected: currentTab == AppTab.profile,
              onTap: () => _navigateToTab(context, AppTab.profile),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = Responsive.isNarrow(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 12 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.navSelectedFill : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.espresso),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.espresso,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
