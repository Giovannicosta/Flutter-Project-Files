import 'package:flutter/material.dart';

/// One entry in the corkboard's add-item menu.
///
/// Add new content types by registering another option; the menu renders
/// whatever options it receives, without needing layout changes.
class CorkboardAddOption {
  const CorkboardAddOption({
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

/// A compact add button with a pop-out menu extending to the right.
/// Meant to be placed inside the corkboard body, underneath its AppBar.
class WidgetCorkboardAddMenu extends StatefulWidget {
  const WidgetCorkboardAddMenu({
    super.key,
    required this.options,
  });

  final List<CorkboardAddOption> options;

  @override
  State<WidgetCorkboardAddMenu> createState() =>
      _WidgetCorkboardAddMenuState();
}

class _WidgetCorkboardAddMenuState extends State<WidgetCorkboardAddMenu> {
  bool _open = false;

  void _select(CorkboardAddOption option) {
    setState(() => _open = false);
    option.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton.filledTonal(
            tooltip: _open ? 'Close add menu' : 'Add to corkboard',
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.close : Icons.add, size: 20),
            padding: EdgeInsets.zero,
          ),
        ),
        if (_open) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 208),
                child: Material(
                  elevation: 5,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in widget.options)
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(option.icon, size: 20),
                          title: Text(option.label),
                          onTap: () => _select(option),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
