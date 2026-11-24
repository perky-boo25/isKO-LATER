import 'package:flutter/material.dart';

import '../models/todo_list.dart';
import '../screens/collab_list_sheets.dart';
import '../services/todo_list_service.dart';
import '../utils/app_theme.dart';

const String _kPersonalListValue = '__personal__';

// dropdown bar to switch between Personal and Shared lists, manage members, or create a list
class ListSwitcherBar extends StatefulWidget {
  final String currentUid;

  const ListSwitcherBar({super.key, required this.currentUid});

  @override
  State<ListSwitcherBar> createState() => _ListSwitcherBarState();
}

class _ListSwitcherBarState extends State<ListSwitcherBar> {
  final TodoListService _todoListService = TodoListService();

  String _activeLabel(TodoList? activeCollabList) {
    if (activeCollabList == null) return 'Personal To-Do List';
    final role = activeCollabList.isOwnedBy(widget.currentUid)
        ? 'Owner'
        : 'Shared';
    return '${activeCollabList.name} ($role)';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TodoList>>(
      key: ValueKey(widget.currentUid),
      stream: _todoListService.streamCollaborativeLists(),
      builder: (context, listSnap) {
        final collabLists = listSnap.data ?? [];

        return ValueListenableBuilder<String?>(
          valueListenable: activeListId,
          builder: (context, selectedId, _) {
            // fall back to Personal list if selected shared list is no longer accessible
            final activeCollabList = collabLists
                .where((l) => l.id == selectedId)
                .firstOrNull;
            if (selectedId != null &&
                activeCollabList == null &&
                listSnap.connectionState == ConnectionState.active) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                activeListId.value = null;
              });
            }

            return Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return PopupMenuButton<String>(
                        tooltip: 'Switch active task list',
                        position: PopupMenuPosition.under,
                        offset: const Offset(0, 4),
                        color: AppColors.creamSurface,
                        constraints: BoxConstraints.tightFor(
                          width: constraints.maxWidth,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                            color: AppColors.espresso,
                            width: 1,
                          ),
                        ),
                        onSelected: (val) {
                          activeListId.value = val == _kPersonalListValue
                              ? null
                              : val;
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem<String>(
                            value: _kPersonalListValue,
                            child: Text(
                              'Personal To-Do List',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.espresso,
                              ),
                            ),
                          ),
                          ...collabLists.map((list) {
                            final isOwner = list.isOwnedBy(widget.currentUid);
                            return PopupMenuItem<String>(
                              value: list.id,
                              child: Text(
                                '${list.name} (${isOwner ? 'Owner' : 'Shared'})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.espresso,
                                ),
                              ),
                            );
                          }),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.creamSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.espresso,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _activeLabel(activeCollabList),
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
                ),

                if (activeCollabList != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: activeCollabList.isOwnedBy(widget.currentUid)
                        ? 'Manage / Invite Members'
                        : 'View Members',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.terracotta,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      activeCollabList.isOwnedBy(widget.currentUid)
                          ? Icons.group_add_outlined
                          : Icons.group_outlined,
                      size: 20,
                    ),
                    onPressed: () => showCollabMembersSheet(
                      context,
                      list: activeCollabList,
                      currentUid: widget.currentUid,
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                IconButton.outlined(
                  tooltip: 'New Collaborative List',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.espresso,
                    side: const BorderSide(color: AppColors.espresso),
                  ),
                  icon: const Icon(Icons.domain_add, size: 20),
                  onPressed: () => showCreateCollabListSheet(context),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
