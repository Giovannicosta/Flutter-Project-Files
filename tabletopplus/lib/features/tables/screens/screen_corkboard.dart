import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/user_profile.dart';
import '../../../providers/provider_auth.dart';
import '../../../providers/provider_user_profile.dart';
import '../../../screens/auth/screen_login_validation.dart';
import '../data/table_repository.dart';
import '../models/board_note.dart';
import '../models/table_model.dart';
import '../widgets/widget_sticky_note.dart';
import '../widgets/table_members_drawer.dart';

class ScreenCorkboard extends ConsumerStatefulWidget {
  const ScreenCorkboard({super.key, required this.tableId});

  static const routePath = '/tables/:tableId';
  static String pathFor(String id) => '/tables/${Uri.encodeComponent(id)}';

  final String tableId;

  @override
  ConsumerState<ScreenCorkboard> createState() => _ScreenCorkboardState();
}

class _ScreenCorkboardState extends ConsumerState<ScreenCorkboard> {
  static const double boardWidth = 2000;
  static const double boardHeight = 1450;
  final TransformationController _transform = TransformationController();
  final Map<String, Offset> _localPositions = {};
  Size _viewportSize = const Size(400, 600);
  int _noteCount = 0;
  // Avoid retrying a rejected name update on every rebuild. The attempt
  // can run again after the screen is reopened or the profile name changes.
  String? _lastMemberNameSyncAttemptKey;
  _CorkboardTab _selectedTab = _CorkboardTab.board;
  bool _adding = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save change: $error')),
    );
  }

  void _updateNotePosition(BoardNote note, DragUpdateDetails details) {
    final old = _localPositions[note.id] ?? Offset(note.x, note.y);
    final scale = _transform.value.getMaxScaleOnAxis();
    setState(() {
      _localPositions[note.id] = Offset(
        (old.dx + details.delta.dx / scale).clamp(0.0, boardWidth - 240.0).toDouble(),
        (old.dy + details.delta.dy / scale).clamp(0.0, boardHeight - 190.0).toDouble(),
      );
    });
  }

  Future<void> _finishMovingNote(BoardNote note) async {
    final position = _localPositions[note.id];
    if (position == null) return;
    try {
      await ref.read(tableRepositoryProvider).moveNote(
        widget.tableId,
        note.id,
        position.dx,
        position.dy,
      );
      // Keep the local position until the realtime snapshot catches up.
    } catch (error) {
      if (mounted) setState(() => _localPositions.remove(note.id));
      _showError(error);
    }
  }

  Future<void> _onAdd(ScaffoldState scaffold) async {
    if (_adding) return;
    if (_selectedTab == _CorkboardTab.table) {
      scaffold.openDrawer();
      return;
    }

    setState(() => _adding = true);
    try {
      switch (_selectedTab) {
        case _CorkboardTab.board:
        case _CorkboardTab.myNotes:
          await _createNote();
        case _CorkboardTab.achievements:
          final draft = await _showNoteEditor(context, achievement: true);
          if (draft == null || !mounted) return;
          await ref.read(tableRepositoryProvider).createAchievement(
            tableId: widget.tableId,
            title: draft.title,
            body: draft.body,
          );
        case _CorkboardTab.table:
          break;
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _createNote() async {
    final draft = await _showNoteEditor(context);
    if (draft == null || !mounted) return;
    final center = _transform.toScene(
      Offset(_viewportSize.width / 2, _viewportSize.height / 2),
    );
    final spread = (_noteCount % 5) * 18.0;
    await ref.read(tableRepositoryProvider).createNote(
      tableId: widget.tableId,
      title: draft.title,
      body: draft.body,
      colorValue: draft.colorValue,
      x: center.dx - 110 + spread,
      y: center.dy - 92 + spread,
    );
  }

  Future<void> _editNote(BoardNote note) async {
    final draft = await _showNoteEditor(context, initial: note);
    if (draft == null || !mounted) return;
    try {
      await ref.read(tableRepositoryProvider).editNote(
        tableId: widget.tableId,
        noteId: note.id,
        title: draft.title,
        body: draft.body,
        colorValue: draft.colorValue,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteNote(BoardNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this note?'),
        content: Text('"${note.title}" will be removed for everyone in the table.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(tableRepositoryProvider).deleteNote(widget.tableId, note.id);
      _localPositions.remove(note.id);
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The authenticated root screen owns email verification / onboarding.
    // Prevent deep links from bypassing that gate.
    final auth = ref.watch(authUserProvider);
    final authUi = ref.watch(providerAuth);
    final userProfile = ref.watch(providerUserProfile);
    final User? user = auth.asData?.value;
    if (user == null ||
        (ENFORCE_EMAIL_VERIFICATION && !user.emailVerified && !authUi.emailVerified) ||
        !userProfile.dataLoaded ||
        userProfile.profile.uid != user.uid ||
        userProfile.profile.accountCreationStep ==
            AccountCreationStep.ACC_STEP_ONBOARDING_PROFILE_CONTACT_INFO) {
      return const ScreenLoginValidation();
    }

    final tableAsync = ref.watch(selectedTableProvider(widget.tableId));
    return tableAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => _BoardMessage(
        title: 'Unable to load this table',
        detail: error.toString(),
        onBack: () => context.go('/'),
      ),
      data: (table) {
        if (table == null || !table.hasMember(user.uid)) {
          return _BoardMessage(
            title: 'Table not available',
            detail: 'You are not a member of this table, or it no longer exists.',
            onBack: () => context.go('/'),
          );
        }
        final profile = userProfile.profile;
        final fullName = [profile.firstName.trim(), profile.lastName.trim()]
            .where((part) => part.isNotEmpty)
            .join(' ');
        final displayedName = fullName.length > 60
            ? fullName.substring(0, 60)
            : fullName;
        final syncKey = '${widget.tableId}:${user.uid}:$displayedName';
        if (displayedName.isNotEmpty &&
            table.memberNames[user.uid] != displayedName &&
            _lastMemberNameSyncAttemptKey != syncKey) {
          // Mark the attempt before scheduling; never clear it in catch.
          // Permission-denied is not transient and must not cause a hot loop.
          _lastMemberNameSyncAttemptKey = syncKey;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            try {
              await ref.read(tableRepositoryProvider)
                  .syncMemberName(widget.tableId, displayedName);
            } catch (error) {
              // Displaying the corkboard must not fail if name sync fails.
              debugPrint('Unable to synchronize table member name (will not retry until reopening this screen): $error');
            }
          });
        }
        return _buildBoard(context, table, user.uid);
      },
    );
  }

  Widget _buildBoard(BuildContext context, TableModel table, String uid) {
    final notesAsync = ref.watch(boardNotesProvider(widget.tableId));
    final onBoard = _selectedTab == _CorkboardTab.board;
    return Scaffold(
      drawer: TableMembersDrawer(table: table, currentUid: uid),
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(table.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              onBoard ? 'Corkboard · ${table.memberIds.length} members' : _selectedTab.label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (onBoard)
            IconButton(
              tooltip: 'Reset zoom',
              onPressed: () => _transform.value = Matrix4.identity(),
              icon: const Icon(Icons.center_focus_strong),
            ),
          Builder(
            builder: (scaffoldContext) => IconButton(
              tooltip: 'Table members',
              onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              icon: const Icon(Icons.person_outline),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: onBoard ? 0 : 1,
        sizing: StackFit.expand,
        children: [
          _buildCanvas(notesAsync, table, uid),
          switch (_selectedTab) {
            _CorkboardTab.board => const SizedBox.shrink(),
            _CorkboardTab.myNotes => _buildMyNotes(notesAsync, uid),
            _CorkboardTab.achievements => _buildAchievements(),
            _CorkboardTab.table => const SizedBox.shrink(),
          },
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (barContext) => _CorkboardNavigationBar(
          selectedTab: _selectedTab,
          onSelected: (tab) => setState(() => _selectedTab = tab),
          onAdd: _adding ? null : () => _onAdd(Scaffold.of(barContext)),
        ),
      ),
    );
  }

  Widget _buildMyNotes(AsyncValue<List<BoardNote>> notes, String uid) {
    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load your notes.')),
      data: (items) {
        final mine = items.where((note) => note.createdBy == uid).toList();
        if (mine.isEmpty) {
          return const Center(child: Text('No notes yet. Tap + to add a note.'));
        }
        return ListView.builder(
          key: const PageStorageKey('my-notes'),
          itemCount: mine.length,
          itemBuilder: (context, index) {
            final note = mine[index];
            return ListTile(
              title: Text(note.title),
              subtitle: note.body.isEmpty ? null : Text(note.body, maxLines: 2),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editNote(note),
            );
          },
        );
      },
    );
  }

  Widget _buildAchievements() {
    final achievements = ref.watch(tableAchievementsProvider(widget.tableId));
    return achievements.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load achievements.')),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('No achievements yet. Tap + to add one.'));
        }
        return ListView.builder(
          key: const PageStorageKey('achievements'),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(item.title),
              subtitle: item.body.isEmpty ? null : Text(item.body),
            );
          },
        );
      },
    );
  }

  Widget _buildCanvas(
    AsyncValue<List<BoardNote>> notesAsync,
    TableModel table,
    String uid,
  ) {
    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load notes: $error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(boardNotesProvider(widget.tableId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (notes) {
        _noteCount = notes.length;
        // Clear pending offsets when Firestore confirms the saved position.
        for (final note in notes) {
          final pending = _localPositions[note.id];
          if (pending != null &&
              (pending.dx - note.x).abs() < 0.01 &&
              (pending.dy - note.y).abs() < 0.01) {
            _localPositions.remove(note.id);
          }
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.45,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(350),
                  child: SizedBox(
                    width: boardWidth,
                    height: boardHeight,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: CustomPaint(painter: _BoardBackground())),
                        for (final note in notes)
                          Positioned(
                            key: ValueKey(note.id),
                            left: (_localPositions[note.id]?.dx ?? note.x),
                            top: (_localPositions[note.id]?.dy ?? note.y),
                            child: WidgetStickyNote(
                              note: note,
                              canEdit: note.createdBy == uid ||
                                  table.isOwner(uid) || table.isModerator(uid),
                              canDelete: note.createdBy == uid ||
                                  table.isOwner(uid) || table.isModerator(uid),
                              onDragUpdate: (details) => _updateNotePosition(note, details),
                              onDragEnd: () => _finishMovingNote(note),
                              onEdit: () => _editNote(note),
                              onDelete: () => _deleteNote(note),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (notes.isEmpty)
                  const Positioned(
                    left: 20,
                    top: 20,
                    right: 20,
                    child: IgnorePointer(
                      child: Text('Your corkboard is empty. Tap + to add the first note.'),
                    ),
                  ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xDDFCF8EF), borderRadius: BorderRadius.all(Radius.circular(6))),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text('Drag background to pan · Pinch/scroll to zoom · Drag note header to move',
                            style: TextStyle(color: Colors.black87, fontSize: 11)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum _CorkboardTab {
  board('Board', Icons.note_alt_outlined, 'Add note'),
  myNotes('My notes', Icons.description_outlined, 'Add note'),
  achievements('Achievements', Icons.workspace_premium_outlined, 'Add achievement'),
  table('Table', Icons.casino_outlined, 'Invite members');

  const _CorkboardTab(this.label, this.icon, this.addLabel);

  final String label;
  final IconData icon;
  final String addLabel;
}

class _CorkboardNavigationBar extends StatelessWidget {
  const _CorkboardNavigationBar({
    required this.selectedTab,
    required this.onSelected,
    required this.onAdd,
  });

  final _CorkboardTab selectedTab;
  final ValueChanged<_CorkboardTab> onSelected;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF2B2522) : const Color(0xFFF8F5F0);
    final accent = isDark ? const Color(0xFFF1A78F) : const Color(0xFFA7513C);
    final inactive = isDark ? const Color(0xFFBFB7B0) : const Color(0xFF626861);

    return Material(
      color: background,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 88,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in _CorkboardTab.values) ...[
                if (tab == _CorkboardTab.achievements)
                  Expanded(child: _buildAddButton()),
                Expanded(
                  child: _buildTab(
                    tab,
                    selectedTab == tab ? accent : inactive,
                    theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    final label = selectedTab.addLabel;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Semantics(
            label: label,
            button: true,
            enabled: onAdd != null,
            child: Material(
              color: onAdd == null ? const Color(0xFF956D61) : const Color(0xFFC97358),
              borderRadius: BorderRadius.circular(22),
              elevation: 5,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onAdd,
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.add, color: Colors.white, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(_CorkboardTab tab, Color color, TextStyle? labelStyle) {
    return Semantics(
      button: true,
      selected: selectedTab == tab,
      child: InkWell(
        onTap: () => onSelected(tab),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, color: color, size: 24),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tab.label,
                  maxLines: 1,
                  style: labelStyle?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardBackground extends CustomPainter {
  const _BoardBackground();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFDFCBAB));
    final dotPaint = Paint()..color = const Color(0x665A4632);
    for (double x = 18; x < size.width; x += 28) {
      for (double y = 18; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BoardMessage extends StatelessWidget {
  const _BoardMessage({required this.title, required this.detail, required this.onBack});
  final String title;
  final String detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('TableTopPlus')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline, size: 48),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: onBack, child: const Text('Back to my tables')),
              ],
            ),
          ),
        ),
      );
}

class _NoteDraft {
  const _NoteDraft(this.title, this.body, this.colorValue);
  final String title;
  final String body;
  final int colorValue;
}

Future<_NoteDraft?> _showNoteEditor(
  BuildContext context, {
  BoardNote? initial,
  bool achievement = false,
}) {
  return showDialog<_NoteDraft>(
    context: context,
    builder: (_) => _NoteEditorDialog(initial: initial, achievement: achievement),
  );
}

// Controllers live for the lifetime of the dialog widget, including its
// closing animation, rather than being disposed as soon as showDialog returns.
class _NoteEditorDialog extends StatefulWidget {
  const _NoteEditorDialog({this.initial, required this.achievement});

  final BoardNote? initial;
  final bool achievement;

  @override
  State<_NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<_NoteEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late int _colorValue;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _bodyController = TextEditingController(text: widget.initial?.body ?? '');
    _colorValue = widget.initial?.colorValue ?? noteColorValues.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Enter a title.');
      return;
    }
    Navigator.of(context).pop(_NoteDraft(
      title,
      _bodyController.text.trim(),
      _colorValue,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(
          widget.achievement
              ? 'New achievement'
              : widget.initial == null
                  ? 'New sticky note'
                  : 'Edit sticky note',
        ),
        content: SizedBox(
          width: 410,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                maxLength: 80,
                decoration: InputDecoration(labelText: 'Title', errorText: _errorMessage),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bodyController,
                minLines: 3,
                maxLines: 7,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: widget.achievement ? 'Description' : 'Note text',
                ),
              ),
              if (!widget.achievement) ...[
                const SizedBox(height: 12),
                const Text('Sticky note color'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final value in noteColorValues)
                      Tooltip(
                        message: 'Color ${noteColorValues.indexOf(value) + 1}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(50),
                          onTap: () => setState(() => _colorValue = value),
                          child: CircleAvatar(
                            radius: 19,
                            backgroundColor: Color(value),
                            child: _colorValue == value
                                ? const Icon(Icons.check, size: 20, color: Colors.black87)
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: _save,
            child: Text(
              widget.achievement
                  ? 'Add achievement'
                  : widget.initial == null
                      ? 'Add note'
                      : 'Save changes',
            ),
          ),
        ],
      );
}
