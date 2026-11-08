import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../providers/auth_provider.dart';
import 'name_service.dart';
import 'storage_service.dart' show UploadFailure, kFilesBucket;

/// Placeholder used when the database sent no author name.
const String kUnknownAuthor = 'Unknown';

/// One public file shown on the Community page.
class CommunityFile {
  const CommunityFile({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.fileType,
    required this.storagePath,
    required this.createdAt,
    required this.authorName,
  });

  final String id;
  final String ownerId;
  final String name; // name shown in the app
  final String fileType; // extension without dot, lowercase
  final String storagePath;
  final DateTime createdAt;
  final String authorName;

  CommunityFile withAuthor(String name) => CommunityFile(
        id: id,
        ownerId: ownerId,
        name: this.name,
        fileType: fileType,
        storagePath: storagePath,
        createdAt: createdAt,
        authorName: name,
      );

  factory CommunityFile.fromMap(Map<String, dynamic> m) => CommunityFile(
        id: m['id'].toString(),
        ownerId: m['owner_id'].toString(),
        name: m['name'] as String,
        fileType: ((m['file_type'] as String?) ?? '').toLowerCase(),
        storagePath: m['storage_path'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        authorName: ((m['author_name'] as String?)?.trim().isNotEmpty ?? false)
            ? (m['author_name'] as String).trim()
            : kUnknownAuthor,
      );
}

const _timeout = Duration(seconds: 20);
const _networkMessage =
    'Could not reach the server. Check your connection and try again.';

/// The Supabase client (= project) of the logged-in user, after checking
/// that their session is still the live one.
SupabaseClient _client(AuthState auth) {
  final role = auth.role;
  final uid = auth.userId;
  if (role == null || uid == null) {
    throw const UploadFailure('Please log in again.');
  }
  final client = clientForRole(role);
  final live = client.auth.currentUser;
  if (live == null || live.id != uid) {
    throw const UploadFailure('Your session has expired. Please log in again.');
  }
  return client;
}

/// Public files (visibility = 'public') of everyone in the user's project,
/// newest first, whose name or author contains [query] (empty = all).
/// Uses the `community_files` function from supabase/community.sql.
/// Throws [UploadFailure] with a message ready to show.
Future<List<CommunityFile>> searchCommunityFiles(
  AuthState auth, {
  String query = '',
}) async {
  final client = _client(auth);
  try {
    final rows = await client
        .rpc('community_files', params: {'p_query': query.trim()})
        .timeout(_timeout);
    final files = [
      for (final r in (rows as List))
        CommunityFile.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
    // Authors without a name: you -> your name, others -> looked up by id.
    final names = await fetchDisplayNames(client, [
      for (final f in files)
        if (f.authorName == kUnknownAuthor && f.ownerId != auth.userId)
          f.ownerId,
    ]);
    return [
      for (final f in files)
        if (f.authorName != kUnknownAuthor)
          f
        else if (f.ownerId == auth.userId)
          f.withAuthor(auth.displayName)
        else
          f.withAuthor(names[f.ownerId] ?? f.authorName),
    ];
  } on PostgrestException catch (e) {
    // Function missing = community.sql was not run in this project yet.
    if (e.code == 'PGRST202' || e.code == '42883') {
      throw const UploadFailure(
        'Community is not set up yet. Please contact support.',
      );
    }
    throw const UploadFailure('Could not load public files. Try again.');
  } on TimeoutException {
    throw const UploadFailure('The server took too long. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// Temporary (1 hour) link to open a public file of another user.
Future<String> communityFileUrl(AuthState auth, CommunityFile file) async {
  final client = _client(auth);
  try {
    return await client.storage
        .from(kFilesBucket)
        .createSignedUrl(file.storagePath, 3600);
  } on StorageException {
    throw const UploadFailure('Could not open the file. Try again.');
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}
