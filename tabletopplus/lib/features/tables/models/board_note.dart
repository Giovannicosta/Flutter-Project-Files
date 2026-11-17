import 'package:cloud_firestore/cloud_firestore.dart';

class BoardNote {
  const BoardNote({
    required this.id,
    required this.title,
    required this.body,
    required this.colorValue,
    required this.x,
    required this.y,
    required this.createdBy,
  });

  final String id;
  final String title;
  final String body;
  final int colorValue;
  final double x;
  final double y;
  final String createdBy;

  factory BoardNote.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Note ${snapshot.id} no longer exists.');
    }
    return BoardNote(
      id: snapshot.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      colorValue: (data['color'] as num?)?.toInt() ?? noteColorValues.first,
      x: (data['x'] as num?)?.toDouble() ?? 0,
      y: (data['y'] as num?)?.toDouble() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}

const List<int> noteColorValues = [
  0xFFFFE082, // yellow
  0xFFF8BBD0, // pink
  0xFFB2DFDB, // teal
  0xFFBBDEFB, // blue
  0xFFD1C4E9, // lavender
  0xFFC8E6C9, // green
];
