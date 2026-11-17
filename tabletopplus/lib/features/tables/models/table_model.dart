import 'package:cloud_firestore/cloud_firestore.dart';

/// A shared tabletop workspace. The document ID is also its invite code.
class TableModel {
  const TableModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    this.createdAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final DateTime? createdAt;

  bool hasMember(String uid) => memberIds.contains(uid);

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
    );
  }
}
