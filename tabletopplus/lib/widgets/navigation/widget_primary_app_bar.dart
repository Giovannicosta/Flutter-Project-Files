import 'package:flutter/material.dart';

/// Reusable application bar without placeholder actions.
class WidgetPrimaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WidgetPrimaryAppBar({super.key, required this.title, this.actionButtons});

  final Widget title;
  final List<Widget>? actionButtons;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        title: title,
        actions: actionButtons,
      );
}
