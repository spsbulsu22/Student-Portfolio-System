import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../services/supabase_clients.dart';
import '../utils/display_name.dart';

enum UserRole { student, instructor }

class AuthState {
  const AuthState({this.role, this.email, this.userId, this.name});
  final UserRole? role;
  final String? email;
  final String? userId;

  /// Name saved on the account (null = not set; see [displayName]).
  final String? name;

  /// Name shown in the app (Home, menus, profile): the saved name, or one
  /// made from the email (oliver@test.com -> Oliver Test).
  String get displayName => (name?.trim().isNotEmpty ?? false)
      ? name!.trim()
      : displayNameFrom(email: email);
  bool get isLoggedIn => role != null;
}

/// An error that is safe to show to the user as it is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The Supabase client (= project) that belongs to [role]. Students and
/// instructors never share a client.
SupabaseClient clientForRole(UserRole role) =>
    role == UserRole.student ? AppSupabase.student : AppSupabase.instructor;

/// Email/password authentication with Supabase Auth, one project per role.
///
/// Login only ever talks to the client of the role chosen on the login
/// screen, and then double-checks the account's `profiles.role` in that
/// project (see the SQL scripts). Sessions are persisted by the clients.
class AuthNotifier extends Notifier<AuthState> {
  static const _timeout = Duration(seconds: 20);

  @override
  AuthState build() {
    if (!AppSupabase.isConfigured) return const AuthState();

    // If a session expires or is revoked, forget the logged-in user.
    final subs = [
      for (final role in UserRole.values)
        clientForRole(role).auth.onAuthStateChange.listen((data) {
          if (data.event == AuthChangeEvent.signedOut && state.role == role) {
            state = const AuthState();
          }
        }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });

    // Session restored at app start (persistence).
    for (final role in UserRole.values) {
      final user = clientForRole(role).auth.currentUser;
      if (user != null) {
        return AuthState(
          role: role,
          email: user.email,
          userId: user.id,
          name: displayNameFrom(metadata: user.userMetadata, email: user.email),
        );
      }
    }
    return const AuthState();
  }

  /// Signs in with email + password. Throws [AuthFailure] (with a message
  /// ready to show) when it does not work.
  Future<void> login({
    required String email,
    required String password,
    required UserRole role,
    bool rememberMe = true,
  }) async {
    if (!AppSupabase.isConfigured) {
      throw const AuthFailure(
        'The app is not connected to Supabase yet. Add the project URLs '
        'and keys (see the setup instructions).',
      );
    }

    final client = clientForRole(role);
    try {
      final res = await client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(_timeout);
      final user = res.user;
      if (user == null) throw const AuthFailure('Login failed. Try again.');

      // The account must be registered with this role in this project.
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_timeout);
      if (profile == null || profile['role'] != role.name) {
        await AppSupabase.signOut(client);
        throw AuthFailure(
          role == UserRole.student
              ? 'This account is not a student account.'
              : 'This account is not an instructor account.',
        );
      }

      await AppSupabase.setRememberMe(rememberMe);
      // Only one role is signed in at a time.
      await AppSupabase.signOut(clientForRole(
        role == UserRole.student ? UserRole.instructor : UserRole.student,
      ));
      state = AuthState(
        role: role,
        email: user.email ?? email,
        userId: user.id,
        name: displayNameFrom(
          metadata: user.userMetadata,
          email: user.email ?? email,
        ),
      );
    } on AuthFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFailure(_authMessage(e));
    } on TimeoutException {
      await AppSupabase.signOut(client);
      throw const AuthFailure('The server took too long. Try again.');
    } on PostgrestException {
      // Signed in, but the profile could not be checked (e.g. SQL setup
      // missing): do not leave a half-verified session behind.
      await AppSupabase.signOut(client);
      throw const AuthFailure(
        'Your account could not be verified. Please contact support.',
      );
    } catch (_) {
      await AppSupabase.signOut(client);
      throw const AuthFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  Future<void> logout() async {
    final role = state.role;
    if (role != null && AppSupabase.isConfigured) {
      await AppSupabase.signOut(clientForRole(role));
    }
    state = const AuthState();
  }

  String _authMessage(AuthException e) {
    if (e is AuthRetryableFetchException) {
      return 'Could not reach the server. Check your connection and try again.';
    }
    switch (e.code) {
      case 'invalid_credentials':
        return 'Incorrect email or password.';
      case 'email_not_confirmed':
        return 'Please confirm your email before logging in.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'user_banned':
        return 'This account has been disabled.';
    }
    if (e.message.toLowerCase().contains('invalid login')) {
      return 'Incorrect email or password.';
    }
    return 'Login failed. Please try again.';
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
