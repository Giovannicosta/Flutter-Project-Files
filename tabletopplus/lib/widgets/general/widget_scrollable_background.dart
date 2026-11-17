import 'package:flutter/material.dart';

/// A safe padded container for the authentication and loading screens.
class ScrollableBackground extends StatelessWidget {
  const ScrollableBackground({
    super.key,
    this.height,
    required this.child,
    this.padding = 20,
  });

  final double? height;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: child,
        ),
      ),
    );
  }
}
