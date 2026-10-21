import 'package:flutter/material.dart';

import '../models/todo_list.dart';
import '../screens/collab_list_sheets.dart';
import '../services/todo_list_service.dart';

// [ l i s t   s w i t c h e r   b a r ]
// Streams all collaborative lists where currentUid is in memberIds, and renders:
// 1. Dropdown to switch between Personal To-Do List (null) and Collaborative Lists
// 2. Members / Invite button (when a Collaborative List is active)
// 3. New Collaborative List button
class ListSwitcherBar extends StatelessWidget {
  final String currentUid;

  const ListSwitcherBar({super.key, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TodoList>>(
      key: ValueKey(currentUid),
      stream: TodoListService().streamCollaborativeLists(),
      builder: (context, listSnap) {
        final collabLists = listSnap.data ?? [];

        return ValueListenableBuilder<String?>(
          valueListenable: activeListId,
          builder: (context, selectedId, _) {
            // If the selected collaborative list is not in this user's accessible lists,
            // fall back safely to the Personal list (null)
            final activeCollabList = collabLists
                .where((l) => l.id == selectedId)
                .firstOrNull;
            final effectiveId = activeCollabList?.id;
            if (selectedId != null &&
                effectiveId == null &&
                listSnap.connectionState == ConnectionState.active) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                activeListId.value = null;
              });
            }

            return Row(
              children: [
                // 1. Dropdown to switch between Personal List and Collaborative Lists
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8EF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4A3427),
                        width: 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: effectiveId,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF4A3427),
                        ),
                        dropdownColor: const Color(0xFFFFF8EF),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 16,
                                  color: Color(0xFF4A3427),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Personal To-Do List',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4A3427),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...collabLists.map((list) {
                            final isOwner = list.isOwnedBy(currentUid);
                            return DropdownMenuItem<String?>(
                              value: list.id,
                              child: Row(
                                children: [
                                  Icon(
                                    isOwner
                                        ? Icons.groups
                                        : Icons.folder_shared_outlined,
                                    size: 16,
                                    color: const Color(0xFFC65A42),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${list.name} (${isOwner ? 'Owner' : 'Shared'})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF4A3427),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (newListId) {
                          activeListId.value = newListId;
                        },
                      ),
                    ),
                  ),
                ),

                // 2. If viewing a Collaborative List, show the Members / Invite button
                if (activeCollabList != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: activeCollabList.isOwnedBy(currentUid)
                        ? 'Manage / Invite Members'
                        : 'View Members',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFC65A42),
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      activeCollabList.isOwnedBy(currentUid)
                          ? Icons.group_add_outlined
                          : Icons.group_outlined,
                      size: 20,
                    ),
                    onPressed: () => showCollabMembersSheet(
                      context,
                      list: activeCollabList,
                      currentUid: currentUid,
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                // 3. Button to create a new Collaborative List
                IconButton.outlined(
                  tooltip: 'New Collaborative List',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFF4A3427),
                    side: const BorderSide(color: Color(0xFF4A3427)),
                  ),
                  icon: const Icon(Icons.add_box_outlined, size: 20),
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
