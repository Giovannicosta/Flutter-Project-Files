import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/table_repository.dart';
import '../models/table_model.dart';
import 'screen_corkboard.dart';

/// First screen after authentication: create, join, or open a table.
class ScreenTableLobby extends ConsumerWidget {
  const ScreenTableLobby({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(myTablesProvider);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your tabletop adventures', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Each table is a shared workspace for your campaign.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _showTableDialog(context, ref, joining: false),
                    icon: const Icon(Icons.add),
                    label: const Text('Create table'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showTableDialog(context, ref, joining: true),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Join with code'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: tables.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _ErrorState(
                    message: 'Could not load your tables. Check your connection and Firestore rules.\n$error',
                    onRetry: () => ref.invalidate(myTablesProvider),
                  ),
                  data: (items) => items.isEmpty
                      ? const _EmptyTables()
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _TableCard(table: items[index]),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table});
  final TableModel table;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(ScreenCorkboard.pathFor(table.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          child: Row(
            children: [
              const CircleAvatar(radius: 26, child: Icon(Icons.auto_stories_outlined)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(table.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text('${table.memberIds.length} member${table.memberIds.length == 1 ? '' : 's'}'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTables extends StatelessWidget {
  const _EmptyTables();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_alt_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text('No tables yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Create your first table or join one using an invite code.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

Future<void> _showTableDialog(BuildContext context, WidgetRef ref, {required bool joining}) async {
  // The dialog owns its TextEditingController and disposes it only when the
  // dialog's widget has actually been removed from the tree.
  final repository = ref.read(tableRepositoryProvider);
  final tableId = await showDialog<String>(
    context: context,
    builder: (_) => _TableEditorDialog(
      repository: repository,
      joining: joining,
    ),
  );

  // Navigation belongs to the original page, never to the dialog's context.
  if (tableId != null && context.mounted) {
    context.push(ScreenCorkboard.pathFor(tableId));
  }
}

class _TableEditorDialog extends StatefulWidget {
  const _TableEditorDialog({
    required this.repository,
    required this.joining,
  });

  final TableRepository repository;
  final bool joining;

  @override
  State<_TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<_TableEditorDialog> {
  final TextEditingController _input = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final id = widget.joining
          ? await widget.repository.joinTable(_input.text)
          : await widget.repository.createTable(_input.text);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = error is ArgumentError
            ? error.message.toString()
            : error is StateError
                ? error.message
                : 'Unable to save table. Check your connection and access rules.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.joining ? 'Join a table' : 'Create a table'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.joining
                  ? 'Enter the 20-character code shared by the table creator.'
                  : 'Give your campaign a name. You can invite friends afterward.'),
              const SizedBox(height: 16),
              TextField(
                controller: _input,
                autofocus: true,
                enabled: !_submitting,
                maxLength: widget.joining ? 20 : 60,
                decoration: InputDecoration(
                  labelText: widget.joining ? 'Invite code' : 'Table name',
                  hintText: widget.joining ? 'Paste invite code' : 'The Lost Mines',
                  errorText: _errorMessage,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.joining ? 'Join' : 'Create'),
          ),
        ],
      );
}
