import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Display names of other users, by user id (see supabase/display_names.sql).
///
/// Never throws: if the SQL has not been run yet, or the network fails, the
/// result is simply empty and the caller keeps its own fallback.
Future<Map<String, String>> fetchDisplayNames(
  SupabaseClient client,
  Iterable<String> ids,
) async {
  final unique = ids.toSet().toList();
  if (unique.isEmpty) return const {};
  try {
    final rows = await client.rpc('display_names', params: {'p_ids': unique});
    return {
      for (final r in (rows as List))
        (r as Map)['id'].toString(): (r['name'] as String?)?.trim() ?? '',
    }..removeWhere((_, v) => v.isEmpty);
  } catch (e) {
    debugPrint('display_names failed: $e');
    return const {};
  }
}
