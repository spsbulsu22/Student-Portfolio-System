import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/profile_layout.dart';

/// Figma frame: "Student Profile".
/// Name and email are the real account's; the other rows are still sample
/// data until the registration page exists.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return ProfileLayout(
      name: auth.displayName,
      roleLabel: 'Student',
      backIcon: Icons.arrow_back, // Figma: arrow-left
      backButtonFontSize: 18,
      backButtonBottom: 52,
      sections: [
        ProfileSection('Personal Information', [
          ProfileRow('Email Address', auth.email ?? ''),
          const ProfileRow('Student ID', '2024123123'),
        ]),
        const ProfileSection('Academic Information', [
          ProfileRow('Affiliation/College', 'College of Engineering'),
          ProfileRow('Degree Program', 'BS Computer Engineering'),
          ProfileRow('Year Level / Section', '3rd Year - Section B'),
        ]),
      ],
    );
  }
}
