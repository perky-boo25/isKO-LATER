import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/todo_list.dart';
import '../models/user.dart';
import '../services/todo_list_service.dart';

// [ 1 .   c r e a t e   c o l l a b o r a t i v e   l i s t   s h e e t ]
// Opens a bottom sheet for creating a new shared list owned by currentUser.
Future<void> showCreateCollabListSheet(BuildContext context) async {
  final controller = TextEditingController();
  final createdName = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFFFFF8EF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Create Collab Space',
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF4A3427),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a shared space and invite friends or classmates.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'List name',
                hintText: "Enter Group name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (val) => Navigator.pop(sheetContext, val.trim()),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4A3427),
                      side: const BorderSide(color: Color(0xFF4A3427)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC65A42),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () =>
                        Navigator.pop(sheetContext, controller.text.trim()),
                    child: const Text(
                      'Create Space',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  if (createdName == null || createdName.isEmpty) return;
  if (!context.mounted) return;

  try {
    final newList = await TodoListService().createCollaborativeList(
      createdName,
    );
    // automatically switch to the newly created collaborative list
    activeListId.value = newList.id;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created "${newList.name}"')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not create list: $e')));
    }
  }
}

// [ 2 .   m e m b e r s   &   i n v i t e   s h e e t ]
// Opens a bottom sheet showing list members and (for the owner) live user suggestions,
// member removal, and list deletion.
Future<void> showCollabMembersSheet(
  BuildContext context, {
  required TodoList list,
  required String currentUid,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFFFFF8EF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CollabMembersSheet(list: list, currentUid: currentUid),
  );
}

class CollabMembersSheet extends StatefulWidget {
  final TodoList list;
  final String currentUid;

  const CollabMembersSheet({
    super.key,
    required this.list,
    required this.currentUid,
  });

  @override
  State<CollabMembersSheet> createState() => _CollabMembersSheetState();
}

class _CollabMembersSheetState extends State<CollabMembersSheet> {
  final _service = TodoListService();
  final _searchController = TextEditingController();

  List<AppUser> _members = [];
  List<AppUser> _allUsers = [];
  bool _loading = true;
  bool _isAdding = false;
  bool _isDeletingList = false;
  String _searchQuery = '';
  String? _feedbackMessage;
  bool _isError = false;

  bool get _isOwner => widget.list.isOwnedBy(widget.currentUid);

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // 1. Load current list members from `users/{uid}`
    try {
      final loadedMembers = await _service.getListMembers(
        widget.list.memberIds,
      );
      if (mounted) {
        setState(() {
          _members = loadedMembers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }

    // 2. Load all users for owner autocomplete suggestions
    if (_isOwner) {
      try {
        final users = await _service.getAllUsers();
        if (mounted) setState(() => _allUsers = users);
      } catch (_) {}
    }
  }

  // [ o w n e r   a c t i o n :   a d d   m e m b e r ]
  Future<void> _inviteIdentifier(String identifier) async {
    if (identifier.trim().isEmpty || _isAdding) return;

    setState(() {
      _isAdding = true;
      _feedbackMessage = null;
    });

    try {
      final addedUser = await _service.addMemberByEmailOrUsername(
        listId: widget.list.id,
        identifier: identifier,
      );
      if (!widget.list.memberIds.contains(addedUser.uid)) {
        widget.list.memberIds.add(addedUser.uid);
      }
      if (!_members.any((m) => m.uid == addedUser.uid)) {
        _members.add(addedUser);
      }
      _searchController.clear();
      if (mounted) {
        setState(() {
          _isAdding = false;
          _isError = false;
          _feedbackMessage =
              'Added ${addedUser.userName} (${addedUser.email})!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAdding = false;
          _isError = true;
          _feedbackMessage = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  // [ o w n e r   a c t i o n :   r e m o v e   m e m b e r ]
  Future<void> _confirmAndRemoveMember(AppUser member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.userName} (${member.email}) from "${widget.list.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.removeMemberFromList(
        listId: widget.list.id,
        memberUid: member.uid,
      );
      widget.list.memberIds.remove(member.uid);
      if (mounted) {
        setState(() {
          _members.removeWhere((m) => m.uid == member.uid);
          _isError = false;
          _feedbackMessage = 'Removed ${member.userName} from the list.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _feedbackMessage = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  // [ o w n e r   a c t i o n :   d e l e t e   c o l l a b   l i s t ]
  Future<void> _confirmAndDeleteList() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete collaborative list?'),
        content: Text(
          'Are you sure you want to delete "${widget.list.name}"? All tasks in this shared list will also be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete List'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingList = true);
    final listName = widget.list.name;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await _service.deleteCollaborativeList(widget.list.id);
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Deleted collaborative list "$listName"')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeletingList = false;
          _isError = true;
          _feedbackMessage = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  String _initialFor(AppUser u) {
    final name = u.userName.trim();
    if (name.isNotEmpty) return name[0].toUpperCase();
    final email = u.email.trim();
    if (email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _allUsers.where((u) {
      if (widget.list.memberIds.contains(u.uid)) return false;
      if (_searchQuery.isEmpty) return true;
      return u.userName.toLowerCase().contains(_searchQuery) ||
          u.email.toLowerCase().contains(_searchQuery);
    }).toList();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title + Role badge + Owner Delete List icon
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.list.name,
                      style: GoogleFonts.dmSerifDisplay(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4A3427),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE8CB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4A3427),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      _isOwner ? 'Owner' : 'Shared with you',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A3427),
                      ),
                    ),
                  ),
                  if (_isOwner) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Delete Collaborative List',
                      onPressed: _isDeletingList ? null : _confirmAndDeleteList,
                      icon: _isDeletingList
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade700,
                            ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // [ o w n e r - o n l y   i n v i t e   &   s u g g e s t i o n s ]
              if (_isOwner) ...[
                const Text(
                  'Add Collaborator',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF4A3427),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 20),
                          hintText: 'Search username or email...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onSubmitted: _inviteIdentifier,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC65A42),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isAdding
                          ? null
                          : () => _inviteIdentifier(_searchController.text),
                      child: _isAdding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Add',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),

                if (_feedbackMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _isError
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isError
                            ? Colors.red.shade300
                            : Colors.green.shade300,
                      ),
                    ),
                    child: Text(
                      _feedbackMessage!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _isError
                            ? Colors.red.shade800
                            : Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],

                if (suggestions.isNotEmpty || _searchQuery.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    _searchQuery.isEmpty
                        ? 'Suggested People'
                        : 'Matching People (${suggestions.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (suggestions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'No other registered users match "$_searchQuery".',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    ...suggestions.take(4).map((u) {
                      return Card(
                        elevation: 0,
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFFFCE8CB),
                            foregroundColor: const Color(0xFF4A3427),
                            child: Text(
                              _initialFor(u),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            u.userName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            u.email,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFC65A42),
                            ),
                            onPressed: _isAdding
                                ? null
                                : () => _inviteIdentifier(u.email),
                            icon: const Icon(Icons.person_add_alt_1, size: 16),
                            label: const Text(
                              'Invite',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    }),
                ],

                const Divider(height: 24),
              ],

              // [ c u r r e n t   m e m b e r s   l i s t ]
              Text(
                'Members (${_members.isNotEmpty ? _members.length : widget.list.memberIds.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF4A3427),
                ),
              ),
              const SizedBox(height: 8),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ..._members.map((m) {
                  final memberIsOwner = m.uid == widget.list.ownerId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE8CB).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFC65A42),
                        foregroundColor: Colors.white,
                        child: Text(
                          _initialFor(m),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text(
                        m.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4A3427),
                        ),
                      ),
                      subtitle: Text(
                        m.email,
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: memberIsOwner
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A3427),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Owner',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Member',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF4A3427),
                                  ),
                                ),
                                if (_isOwner) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Remove ${m.userName}',
                                    icon: Icon(
                                      Icons.person_remove_outlined,
                                      size: 18,
                                      color: Colors.red.shade700,
                                    ),
                                    onPressed: () => _confirmAndRemoveMember(m),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
