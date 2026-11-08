import 'package:flutter/material.dart';

/// Figma prototype transition: DISSOLVE, ease out, 0.3s.
/// The new screen fades in over the old one (no sliding).
class DissolvePageRoute<T> extends PageRouteBuilder<T> {
  DissolvePageRoute({required Widget page})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        );
}
