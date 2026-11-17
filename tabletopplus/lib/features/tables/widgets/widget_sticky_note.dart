import 'package:flutter/material.dart';

import '../models/board_note.dart';

/// A note can be moved by dragging its top bar; clicking the pen edits it.
class WidgetStickyNote extends StatelessWidget {
  const WidgetStickyNote({
    super.key,
    required this.note,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onEdit,
    required this.onDelete,
  });

  final BoardNote note;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: Color(note.colorValue),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 220,
        height: 184,
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: onDragUpdate,
              onPanEnd: (_) => onDragEnd(),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    const Icon(Icons.drag_indicator, color: Colors.black54, size: 18),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit note',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 17, color: Colors.black87),
                      visualDensity: VisualDensity.compact,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Note actions',
                      icon: const Icon(Icons.more_vert, color: Colors.black87, size: 18),
                      onSelected: (action) {
                        if (action == 'delete') onDelete();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'delete', child: Text('Delete note')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    note.body,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
