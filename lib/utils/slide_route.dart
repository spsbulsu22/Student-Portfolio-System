import 'package:flutter/material.dart';

/// Shared implementation for the horizontal slide transitions.
///
/// Uses [SlideTransition] driven by `animation.drive(...)` instead of
/// rebuilding a FractionalTranslation by hand every frame. The child is wrapped
/// in a [RepaintBoundary] so the page is painted once and the GPU just moves
/// the cached layer while it slides.
class _SlideRoute<T> extends PageRouteBuilder<T> {
  _SlideRoute({required Widget page, required Offset from})
      : super(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (_, animation, __, child) {
            return SlideTransition(
              position: animation.drive(
                Tween<Offset>(begin: from, end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeOutCubic)),
              ),
              child: RepaintBoundary(child: child),
            );
          },
        );
}

/// Slides the new screen in from the LEFT, so it travels to the right.
/// Used when logging out (the reverse of the forward, right-to-left slide).
class SlideFromLeftRoute<T> extends _SlideRoute<T> {
  SlideFromLeftRoute({required super.page}) : super(from: const Offset(-1, 0));
}

/// Slides the new screen in from the RIGHT, so it travels to the left.
/// Used when logging in (the opposite of [SlideFromLeftRoute] for logout).
class SlideFromRightRoute<T> extends _SlideRoute<T> {
  SlideFromRightRoute({required super.page}) : super(from: const Offset(1, 0));
}
