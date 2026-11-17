import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/table_repository.dart';
import '../models/table_model.dart';

/// Left-side, realtime member panel. The table itself comes from selectedTableProvider.
class TableMembersDrawer extends ConsumerWidget {
  const TableMembersDrawer({super.key, required this.table, required this.currentUid});

  final TableModel table;
  final String currentUid;

  Future<void> _moderate(
    BuildContext context,
    WidgetRef ref,
    String memberUid,
    String action,
  ) async {
    if (action == 'kick' || action == 'ban') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(action == 'kick' ? 'Remove member?' : 'Ban member?'),
          content: Text(action == 'kick'
              ? 'This member will be removed but can rejoin with an invite.'
              : 'This member will be removed and blocked from rejoining.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action == 'kick' ? 'Kick' : 'Ban'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      final repository = ref.read(tableRepositoryProvider);
      switch (action) {
        case 'kick':
          await repository.kickMember(table.id, memberUid);
          break;
        case 'ban':
          await repository.banMember(table.id, memberUid);
          break;
        case 'promote':
          await repository.setModerator(table.id, memberUid, true);
          break;
        case 'demote':
          await repository.setModerator(table.id, memberUid, false);
          break;
        case 'unban':
          await repository.unbanMember(table.id, memberUid);
          break;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member permissions updated.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update member: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = table.isOwner(currentUid);
    final members = [...table.memberIds];
    members.sort((a, b) {
      if (a == table.ownerId) return -1;
      if (b == table.ownerId) return 1;
      if (table.isModerator(a) != table.isModerator(b)) {
        return table.isModerator(a) ? -1 : 1;
      }
      return (table.memberNames[a] ?? a)
          .compareTo(table.memberNames[b] ?? b);
    });

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Table members'),
              subtitle: Text('${members.length} member${members.length == 1 ? '' : 's'}'),
              trailing: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final uid in members)
                    ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (table.memberNames[uid]?.isNotEmpty == true
                                  ? table.memberNames[uid]![0]
                                  : 'M')
                              .toUpperCase(),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              table.memberNames[uid] ?? 'Member ${uid.substring(0, uid.length > 6 ? 6 : uid.length)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (uid == table.ownerId) ...[
                            const SizedBox(width: 6),
                            const Text('👑', style: TextStyle(fontSize: 19)),
                          ],
                        ],
                      ),
                      subtitle: Text(uid == table.ownerId
                          ? 'Owner'
                          : table.isModerator(uid) ? 'Moderator' : 'Member'),
                      trailing: isOwner && uid != currentUid
                          ? PopupMenuButton<String>(
                              tooltip: 'Manage member',
                              onSelected: (action) => _moderate(context, ref, uid, action),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: table.isModerator(uid) ? 'demote' : 'promote',
                                  child: Text(table.isModerator(uid)
                                      ? 'Remove moderator privileges'
                                      : 'Give moderator privileges'),
                                ),
                                const PopupMenuItem(value: 'kick', child: Text('Kick from table')),
                                const PopupMenuItem(value: 'ban', child: Text('Ban from table')),
                              ],
                            )
                          : null,
                    ),
                  if (isOwner && table.bannedIds.isNotEmpty) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('Banned accounts'),
                    ),
                    for (final uid in table.bannedIds)
                      ListTile(
                        leading: const Icon(Icons.block_outlined),
                        title: Text(table.memberNames[uid] ??
                            'Member ${uid.substring(0, uid.length > 6 ? 6 : uid.length)}'),
                        trailing: TextButton(
                          onPressed: () => _moderate(context, ref, uid, 'unban'),
                          child: const Text('Unban'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy invite code'),
              subtitle: Text(table.id, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: table.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invite code copied.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
