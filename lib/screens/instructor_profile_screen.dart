import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/profile_layout.dart';

/// Figma frame: "Instructor Profile".
/// Name and email are the real account's; the other rows are still sample
/// data until the registration page exists.
class InstructorProfileScreen extends ConsumerWidget {
  const InstructorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return ProfileLayout(
      name: auth.displayName,
      roleLabel: 'Instructor',
      backIcon: Icons.chevron_left, // Figma: chevron-left
      backButtonFontSize: 16,
      backButtonBottom: 50,
      sections: [
        ProfileSection('Personal Information', [
          ProfileRow('Name', auth.displayName),
          ProfileRow('Email', auth.email ?? ''),
        ]),
        const ProfileSection('Academic Information', [
          ProfileRow('Faculty ID', 'F-88291'),
          ProfileRow('Affiliation/College', 'College of Engineering'),
          ProfileRow('Department', 'Computer Engineering'),
          ProfileRow('Academic Position', 'Professor'),
        ]),
      ],
    );
  }
}
