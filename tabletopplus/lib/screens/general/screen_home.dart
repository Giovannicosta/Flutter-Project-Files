import 'package:flutter/material.dart';

import '../../features/tables/screens/screen_table_lobby.dart';

/// Legacy entrypoint maintained for existing imports; the home is now My Tables.
class ScreenHome extends StatelessWidget {
  static const routeName = '/home';
  const ScreenHome({super.key});

  @override
  Widget build(BuildContext context) => const ScreenTableLobby();
}
