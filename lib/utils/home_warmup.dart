import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Checks, before Home opens, whether the sample document image is bundled
/// (`assets/images/recent_doc.png`) and decodes it if it is.
///
/// Home uses [hasRecentDoc] so it never requests a file that does not exist
/// while the slide animation is running.
///
/// Call [HomeWarmUp.run] early (the Login screen does it when it opens) and
/// `await` it before opening Home.
class HomeWarmUp {
  HomeWarmUp._();

  static const _recentDoc = 'assets/images/recent_doc.png';

  /// True only when `assets/images/recent_doc.png` really exists.
  static bool hasRecentDoc = false;

  static Future<void>? _running;

  /// Runs once. Calling it again returns the same Future.
  static Future<void> run(BuildContext context) => _running ??= _run(context);

  static Future<void> _run(BuildContext context) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      hasRecentDoc = manifest.listAssets().contains(_recentDoc);
    } catch (_) {}

    if (hasRecentDoc && context.mounted) {
      try {
        await precacheImage(
          const AssetImage(_recentDoc),
          context,
          onError: (_, __) {},
        );
      } catch (_) {}
    }
  }
}
