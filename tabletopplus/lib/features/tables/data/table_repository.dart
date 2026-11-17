import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/provider_auth.dart';
import '../models/board_note.dart';
import '../models/table_model.dart';

final tableRepositoryProvider = Provider<TableRepository>((ref) {
  return TableRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

final myTablesProvider = StreamProvider<List<TableModel>>((ref) {
  final user = ref.watch(authUserProvider).asData?.value;
  if (user == null) return Stream.value(const <TableModel>[]);
  return ref.watch(tableRepositoryProvider).watchMyTables(user.uid);
});

final selectedTableProvider = StreamProvider.family<TableModel?, String>((ref, id) {
  return ref.watch(tableRepositoryProvider).watchTable(id);
});

final boardNotesProvider = StreamProvider.family<List<BoardNote>, String>((ref, tableId) {
  return ref.watch(tableRepositoryProvider).watchNotes(tableId);
});

class TableRepository {
  const TableRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Please sign in first.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _tables => _db.collection('tables');

  String get _memberName {
    final user = _auth.currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return (displayName.length > 60 ? displayName.substring(0, 60) : displayName);
    final email = user?.email ?? '';
    if (email.isNotEmpty) {
      final local = email.split('@').first;
      return (local.length > 60 ? local.substring(0, 60) : local);
    }
    return 'Member';
  }

  Future<void> _ownerAction(String tableId, String targetUid, String action) async {
    final uid = _uid;
    if (uid == targetUid) throw StateError('You cannot moderate your own account.');
    final table = _tables.doc(tableId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(table);
      if (!snapshot.exists) throw StateError('Table not found.');
      final data = snapshot.data()!;
      if (data['ownerId'] != uid) throw StateError('Only the owner can manage members.');
      final members = List<String>.from(data['memberIds'] as List? ?? []);
      final moderators = List<String>.from(data['moderatorIds'] as List? ?? []);
      final banned = List<String>.from(data['bannedIds'] as List? ?? []);
      if (action == 'kick' || action == 'ban') {
        members.remove(targetUid);
        moderators.remove(targetUid);
        if (action == 'ban' && !banned.contains(targetUid)) banned.add(targetUid);
      } else if (action == 'promote') {
        if (!members.contains(targetUid)) throw StateError('User is not a member.');
        if (!moderators.contains(targetUid)) moderators.add(targetUid);
      } else if (action == 'demote') {
        moderators.remove(targetUid);
      } else if (action == 'unban') {
        banned.remove(targetUid);
      }
      transaction.update(table, {
        'memberIds': members,
        'moderatorIds': moderators,
        'bannedIds': banned,
      });
    });
  }

  Future<void> kickMember(String tableId, String memberUid) =>
      _ownerAction(tableId, memberUid, 'kick');
  Future<void> banMember(String tableId, String memberUid) =>
      _ownerAction(tableId, memberUid, 'ban');
  Future<void> setModerator(String tableId, String memberUid, bool enabled) =>
      _ownerAction(tableId, memberUid, enabled ? 'promote' : 'demote');
  Future<void> unbanMember(String tableId, String memberUid) =>
      _ownerAction(tableId, memberUid, 'unban');

  CollectionReference<Map<String, dynamic>> _notes(String tableId) =>
      _tables.doc(tableId).collection('notes');

  Stream<List<TableModel>> watchMyTables(String uid) => _tables
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((snapshot) {
        final tables = snapshot.docs.map(TableModel.fromSnapshot).toList();
        tables.sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });
        return tables;
      });

  Stream<TableModel?> watchTable(String id) => _tables.doc(id).snapshots().map(
        (snapshot) => snapshot.exists ? TableModel.fromSnapshot(snapshot) : null,
      );

  Stream<List<BoardNote>> watchNotes(String tableId) => _notes(tableId)
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(BoardNote.fromSnapshot).toList());

  Future<String> createTable(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 60) {
      throw ArgumentError('Table name must be between 1 and 60 characters.');
    }
    final uid = _uid;
    // Firestore's auto-generated ID is high-entropy and acts as an invite code.
    final table = _tables.doc();
    await table.set({
      'name': normalized,
      'ownerId': uid,
      'memberIds': [uid],
      'memberNames': {uid: _memberName},
      'moderatorIds': <String>[],
      'bannedIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return table.id;
  }

  Future<String> joinTable(String inviteCode) async {
    final id = inviteCode.trim();
    if (!RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id)) {
      throw ArgumentError('Enter the 20-character invite code.');
    }
    final uid = _uid;
    final table = _tables.doc(id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(table);
      if (!snapshot.exists) {
        throw StateError('No table exists with that invite code.');
      }
      final members = List<String>.from(
        snapshot.data()?['memberIds'] as List<dynamic>? ?? const [],
      );
      final banned = List<String>.from(snapshot.data()?['bannedIds'] as List<dynamic>? ?? const []);
      if (banned.contains(uid)) throw StateError('You are banned from this table.');
      if (members.contains(uid)) return;
      final names = Map<String, dynamic>.from(snapshot.data()?['memberNames'] as Map? ?? {});
      names[uid] = _memberName;
      transaction.update(table, {
        'memberIds': FieldValue.arrayUnion([uid]),
        'memberNames': names,
      });
    });
    return id;
  }

  Future<void> createNote({
    required String tableId,
    required String title,
    required String body,
    required int colorValue,
    required double x,
    required double y,
  }) async {
    _validateNote(title, body, colorValue);
    await _notes(tableId).add({
      'title': title.trim(),
      'body': body.trim(),
      'color': colorValue,
      'x': x.clamp(0.0, 1760.0).toDouble(),
      'y': y.clamp(0.0, 1260.0).toDouble(),
      'createdBy': _uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> editNote({
    required String tableId,
    required String noteId,
    required String title,
    required String body,
    required int colorValue,
  }) async {
    _validateNote(title, body, colorValue);
    await _notes(tableId).doc(noteId).update({
      'title': title.trim(),
      'body': body.trim(),
      'color': colorValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> moveNote(String tableId, String noteId, double x, double y) async {
    await _notes(tableId).doc(noteId).update({
      'x': x.clamp(0.0, 1760.0).toDouble(),
      'y': y.clamp(0.0, 1260.0).toDouble(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNote(String tableId, String noteId) =>
      _notes(tableId).doc(noteId).delete();

  static void _validateNote(String title, String body, int colorValue) {
    if (title.trim().isEmpty || title.trim().length > 80) {
      throw ArgumentError('Note title must be between 1 and 80 characters.');
    }
    if (body.trim().length > 2000) {
      throw ArgumentError('Note body cannot exceed 2,000 characters.');
    }
    if (!noteColorValues.contains(colorValue)) {
      throw ArgumentError('Choose a supported note color.');
    }
  }
}
