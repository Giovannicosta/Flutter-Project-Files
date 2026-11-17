import 'package:flutter/material.dart';

/// Displays a profile image or initials; re-renders on profile updates.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.radius,
    this.initialsSize = 0,
    required this.userImage,
    required this.userWholeName,
    this.isInAppBar = false,
  });

  final double radius;
  final double initialsSize;
  final ImageProvider? userImage;
  final String userWholeName;
  final bool isInAppBar;

  String get initials {
    final names = userWholeName.trim().split(RegExp(r'\s+'));
    if (names.isEmpty || names.first.isEmpty) return 'ME';
    final first = names.first.substring(0, 1);
    final last = names.length > 1 ? names.last.substring(0, 1) : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final image = userImage;
    if (image == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey,
        child: Text(initials, style: TextStyle(fontSize: initialsSize > 0 ? initialsSize : radius * .7)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      onBackgroundImageError: (error, stackTrace) {
        debugPrint('Profile image could not be loaded: $error');
      },
    );
  }
}
