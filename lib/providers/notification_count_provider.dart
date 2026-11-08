import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../services/class_service.dart';
import '../services/supabase_clients.dart';
import 'auth_provider.dart';

/// Number of UNREAD notifications of the logged-in user (0 = no badge).
///
/// The number always comes from the backend:
///  - Instructor: rows of `instructor_notifications` with `is_read = false`
///    (ONE row per task, so a task counts once however many students
///    submitted). Supabase Realtime pushes changes at once; polling is the
///    fallback.
///  - Student: unread items of the `student-notifications` Edge Function
///    (the student's login lives in another project, so no Realtime there:
///    polling + refresh when the app comes back to the foreground).
///
/// Because `is_read` is stored in the backend, every device of the same
/// account ends up showing the same number.
class UnreadNotificationCount extends Notifier<int> {
  static const _pollEvery = Duration(seconds: 30);

  Timer? _timer;
  RealtimeChannel? _channel;
  AppLifecycleListener? _lifecycle;
  UserRole? _role;
  bool _alive = true;
  int _seq = 0; // newer requests/local changes win over older answers

  @override
  int build() {
    _alive = true;
    _seq++; // answers requested for a previous login are dropped
    ref.onDispose(_teardown);

    final role = ref.watch(authProvider.select((s) => s.role));
    _role = role;
    if (role == null || !AppSupabase.isConfigured) return 0;

    _timer = Timer.periodic(_pollEvery, (_) => refresh());
    _lifecycle = AppLifecycleListener(onResume: refresh);
    if (role == UserRole.instructor) _listenRealtime();

    Future.microtask(refresh);
    return 0;
  }

  void _teardown() {
    _alive = false;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        unawaited(AppSupabase.instructor.removeChannel(ch));
      } catch (_) {}
    }
  }

  void _listenRealtime() {
    try {
      _channel = AppSupabase.instructor
          .channel('instructor-unread-notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'instructor_notifications',
            callback: (_) => refresh(),
          )
          .subscribe();
    } catch (_) {
      // Realtime unavailable: polling keeps the number current.
    }
  }

  /// Reads the real count from the backend. Errors keep the last number.
  Future<void> refresh() async {
    final role = _role;
    if (!_alive || role == null) return;
    final mine = ++_seq;
    try {
      final n = role == UserRole.instructor
          ? await InstructorClassApi.unreadNotificationCount()
          : await StudentClassApi.unreadNotificationCount();
      if (_alive && mine == _seq) state = n;
    } catch (_) {}
  }

  /// The notifications page loaded a full student list: use its unread count
  /// (same data the refresh would fetch) without another request.
  void setCount(int n) {
    if (!_alive) return;
    _seq++;
    state = n < 0 ? 0 : n;
  }

  /// One unread notification was just opened: show it at once, then let
  /// [refresh] confirm with the backend (also undoes it if saving failed).
  void markedRead() {
    if (!_alive) return;
    _seq++; // drop answers that were requested before this change
    if (state > 0) state = state - 1;
  }
}

final unreadNotificationCountProvider =
    NotifierProvider<UnreadNotificationCount, int>(UnreadNotificationCount.new);
