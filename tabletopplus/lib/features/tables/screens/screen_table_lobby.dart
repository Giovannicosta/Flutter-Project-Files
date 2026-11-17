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
  final input = TextEditingController();
  bool submitting = false;
  String? errorMessage;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(joining ? 'Join a table' : 'Create a table'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(joining
                  ? 'Enter the 20-character code shared by the table creator.'
                  : 'Give your campaign a name. You can invite friends afterward.'),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                autofocus: true,
                enabled: !submitting,
                maxLength: joining ? 20 : 60,
                decoration: InputDecoration(
                  labelText: joining ? 'Invite code' : 'Table name',
                  hintText: joining ? 'Paste invite code' : 'The Lost Mines',
                  errorText: errorMessage,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setDialogState(() {
                      submitting = true;
                      errorMessage = null;
                    });
                    try {
                      final repository = ref.read(tableRepositoryProvider);
                      final id = joining
                          ? await repository.joinTable(input.text)
                          : await repository.createTable(input.text);
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      if (context.mounted) context.push(ScreenCorkboard.pathFor(id));
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      setDialogState(() {
                        submitting = false;
                        errorMessage = error is ArgumentError
                            ? error.message.toString()
                            : error is StateError
                                ? error.message
                                : 'Unable to save table. Check your connection and access rules.';
                      });
                    }
                  },
            child: submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(joining ? 'Join' : 'Create'),
          ),
        ],
      ),
    ),
  );
  input.dispose();
}
