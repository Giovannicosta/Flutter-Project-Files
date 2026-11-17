import 'package:cloud_firestore/cloud_firestore.dart';

/// A shared tabletop workspace. The document ID is also its invite code.
class TableModel {
  const TableModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    this.createdAt,
    this.memberNames = const {},
    this.moderatorIds = const [],
    this.bannedIds = const [],
  });

  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final DateTime? createdAt;
  final Map<String, String> memberNames;
  final List<String> moderatorIds;
  final List<String> bannedIds;

  bool hasMember(String uid) => memberIds.contains(uid);
  bool isOwner(String uid) => ownerId == uid;
  bool isModerator(String uid) => moderatorIds.contains(uid);

  factory TableModel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Table ${snapshot.id} no longer exists.');
    }
    return TableModel(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Unnamed table',
      ownerId: data['ownerId'] as String? ?? '',
      memberIds: List<String>.from(data['memberIds'] as List<dynamic>? ?? const []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      memberNames: Map<String, String>.from(data['memberNames'] as Map? ?? const {}),
      moderatorIds: List<String>.from(data['moderatorIds'] as List<dynamic>? ?? const []),
      bannedIds: List<String>.from(data['bannedIds'] as List<dynamic>? ?? const []),
    );
  }
}
