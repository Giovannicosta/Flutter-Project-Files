import 'package:flutter/material.dart';

import '../../features/tables/screens/screen_table_lobby.dart';
import 'widget_app_drawer.dart';
import 'widget_primary_app_bar.dart';

/// Authenticated landing screen. A table opens its own corkboard route.
class WidgetPrimaryScaffold extends StatelessWidget {
  static const routeName = '/app';
  const WidgetPrimaryScaffold({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const WidgetPrimaryAppBar(title: Text('My Tables')),
        drawer: WidgetAppDrawer(),
        body: const ScreenTableLobby(),
      );
}
