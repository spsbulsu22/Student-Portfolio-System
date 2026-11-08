import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Project URLs and public (anon / publishable) keys of the TWO Supabase
/// projects. Nothing is hard-coded: pass them at build time, e.g.
///
///   flutter run -d chrome \
///     --dart-define=STUDENT_SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=STUDENT_SUPABASE_ANON_KEY=... \
///     --dart-define=INSTRUCTOR_SUPABASE_URL=https://yyyy.supabase.co \
///     --dart-define=INSTRUCTOR_SUPABASE_ANON_KEY=...
///
/// (or `--dart-define-from-file=env.json`, keeping that file out of git).
/// Only the public key belongs in the app. NEVER put a service_role key here.
class SupabaseConfig {
  SupabaseConfig._();

  static const studentUrl = String.fromEnvironment('STUDENT_SUPABASE_URL');
  static const studentAnonKey =
      String.fromEnvironment('STUDENT_SUPABASE_ANON_KEY');
  static const instructorUrl =
      String.fromEnvironment('INSTRUCTOR_SUPABASE_URL');
  static const instructorAnonKey =
      String.fromEnvironment('INSTRUCTOR_SUPABASE_ANON_KEY');

  /// All four values given, and the two projects really are different ones
  /// (the whole point is keeping the two user bases isolated).
  static bool get isConfigured =>
      studentUrl.isNotEmpty &&
      studentAnonKey.isNotEmpty &&
      instructorUrl.isNotEmpty &&
      instructorAnonKey.isNotEmpty &&
      studentUrl != instructorUrl;
}

/// The two independent Supabase clients.
///
///  - Student: the default `Supabase.instance` client, so existing code that
///    uses it (e.g. storage_service.dart) keeps working. supabase_flutter
///    persists and restores its session by itself.
///  - Instructor: a second [SupabaseClient] for the other project. Its
///    session is persisted and restored here with the same local storage that
///    supabase_flutter uses (shared_preferences / localStorage on web).
///
/// A session of one project is never valid in the other: different URLs,
/// different keys, different users.
class AppSupabase {
  AppSupabase._();

  static const _instructorSessionKey = 'sb-sps-instructor-auth-token';
  static const _rememberKey = 'sps-remember-me';

  static SupabaseClient? _instructor;
  static final _rememberStore =
      SharedPreferencesLocalStorage(persistSessionKey: _rememberKey);

  static bool get isConfigured => SupabaseConfig.isConfigured;

  static SupabaseClient get student => Supabase.instance.client;

  static SupabaseClient get instructor =>
      _instructor ?? (throw StateError('AppSupabase.init() was not called.'));

  /// Call once before runApp. Restores saved sessions (or clears them when
  /// the user logged in without "Remember me").
  static Future<void> init() async {
    if (!isConfigured) {
      debugPrint(
        'Supabase is NOT configured: pass STUDENT_/INSTRUCTOR_ '
        'SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define (the two '
        'projects must be different).',
      );
      return;
    }

    await Supabase.initialize(
      url: SupabaseConfig.studentUrl,
      anonKey: SupabaseConfig.studentAnonKey,
    );

    final storage =
        SharedPreferencesLocalStorage(persistSessionKey: _instructorSessionKey);
    await storage.initialize();
    final client = SupabaseClient(
      SupabaseConfig.instructorUrl,
      SupabaseConfig.instructorAnonKey,
    );
    _instructor = client;

    // Keep the instructor session saved while it changes (login, token
    // refresh) and forget it on sign out.
    client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        storage.removePersistedSession();
      } else if (data.session != null) {
        storage.persistSession(jsonEncode(data.session!.toJson()));
      }
    });

    // "Remember me" off at the last login: start logged out.
    await _rememberStore.initialize();
    if (await _rememberStore.accessToken() == '0') {
      await storage.removePersistedSession();
      await signOut(student);
      return;
    }

    try {
      final saved = await storage.accessToken();
      if (saved != null) await client.auth.recoverSession(saved);
    } catch (_) {
      await storage.removePersistedSession(); // expired / revoked
    }
  }

  /// Stores the "Remember me" choice of the last login.
  static Future<void> setRememberMe(bool value) async {
    await _rememberStore.initialize();
    await _rememberStore.persistSession(value ? '1' : '0');
  }

  /// Ends the session of [client] on this device. Never throws (e.g. when
  /// there is no network or no session).
  static Future<void> signOut(SupabaseClient client) async {
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
  }
}
