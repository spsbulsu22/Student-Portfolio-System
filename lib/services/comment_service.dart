import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../providers/auth_provider.dart';
import 'name_service.dart';
import 'storage_service.dart' show UploadFailure;

/// Longest comment allowed. Keep in sync with the check in
/// supabase/comments.sql.
const int kMaxCommentLength = 500;

/// Placeholder used when the database sent no author name.
const String kUnknownUser = 'Unknown user';

/// One comment on a public file (Community > File Viewing > Comments).
class FileComment {
  const FileComment({
    required this.id,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
    required this.authorName,
    required this.isMine,
  });

  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;
  final int likeCount;
  final bool likedByMe;
  final String authorName; // the account name (never the email)
  final bool isMine;

  FileComment copyWith({
    int? likeCount,
    bool? likedByMe,
    String? authorName,
  }) =>
      FileComment(
        id: id,
        userId: userId,
        body: body,
        createdAt: createdAt,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        authorName: authorName ?? this.authorName,
        isMine: isMine,
      );

  factory FileComment.fromMap(Map<String, dynamic> m) => FileComment(
        id: m['id'].toString(),
        userId: m['user_id'].toString(),
        body: (m['body'] as String?) ?? '',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        likeCount: (m['like_count'] as num?)?.toInt() ?? 0,
        likedByMe: (m['liked_by_me'] as bool?) ?? false,
        authorName: ((m['author_name'] as String?)?.trim().isNotEmpty ?? false)
            ? (m['author_name'] as String).trim()
            : kUnknownUser,
        isMine: (m['is_mine'] as bool?) ?? false,
      );
}

/// Result of liking / unliking a comment.
class CommentLikeResult {
  const CommentLikeResult({required this.liked, required this.count});
  final bool liked;
  final int count;
}

const _timeout = Duration(seconds: 20);
const _networkMessage =
    'Could not reach the server. Check your connection and try again.';

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

/// Turns a database error into a message that is safe to show.
UploadFailure _failure(PostgrestException e, String fallback) {
  // Function missing = comments.sql was not run in this project yet.
  if (e.code == 'PGRST202' || e.code == '42883') {
    return const UploadFailure(
      'Comments are not set up yet. Please contact support.',
    );
  }
  switch (e.code) {
    case 'P0002':
      return const UploadFailure('This file or comment is no longer available.');
    case '22023':
      return const UploadFailure(
        'Write a comment between 1 and $kMaxCommentLength characters.',
      );
    case '42501':
      return const UploadFailure('You cannot do that.');
    case '28000':
      return const UploadFailure('Your session has expired. Please log in again.');
    case '42P01':
      return const UploadFailure(
        'Comments are not set up yet. Please contact support.',
      );
  }
  // Unknown problem: log it and show its code so it can be diagnosed.
  debugPrint('Comments error: ${e.code} ${e.message} ${e.details}');
  final code = (e.code ?? '').isEmpty ? '' : ' (${e.code})';
  return UploadFailure('$fallback$code');
}

Future<T> _run<T>(
  AuthState auth,
  String fallback,
  Future<T> Function(SupabaseClient client) body,
) async {
  final client = _client(auth);
  try {
    return await body(client).timeout(_timeout);
  } on PostgrestException catch (e) {
    throw _failure(e, fallback);
  } on TimeoutException {
    throw const UploadFailure('The server took too long. Try again.');
  } on UploadFailure {
    rethrow;
  } catch (_) {
    throw const UploadFailure(_networkMessage);
  }
}

/// All comments of the public file [fileId], newest first.
Future<List<FileComment>> loadComments(AuthState auth, String fileId) =>
    _run(auth, 'Could not load comments. Try again.', (c) async {
      final rows =
          await c.rpc('community_file_comments', params: {'p_file_id': fileId});
      return _withNames(c, auth, [
        for (final r in (rows as List))
          FileComment.fromMap(Map<String, dynamic>.from(r as Map)),
      ]);
    });

/// Fills in the name of every comment whose author name is missing: your own
/// comments get your name, other people's are looked up by user id.
Future<List<FileComment>> _withNames(
  SupabaseClient c,
  AuthState auth,
  List<FileComment> list,
) async {
  final missing = [
    for (final m in list)
      if (m.authorName == kUnknownUser && !m.isMine) m.userId,
  ];
  final names = await fetchDisplayNames(c, missing);
  return [
    for (final m in list)
      if (m.authorName != kUnknownUser)
        m
      else if (m.isMine)
        m.copyWith(authorName: auth.displayName)
      else
        m.copyWith(authorName: names[m.userId] ?? m.authorName),
  ];
}

/// Posts a comment. Returns the saved comment.
Future<FileComment> addComment(
  AuthState auth,
  String fileId,
  String body,
) {
  final text = body.trim();
  if (text.isEmpty) {
    throw const UploadFailure('Write something first.');
  }
  if (text.length > kMaxCommentLength) {
    throw const UploadFailure(
      'Comments can have at most $kMaxCommentLength characters.',
    );
  }
  return _run(auth, 'Could not post your comment. Try again.', (c) async {
    final rows = await c.rpc(
      'add_community_comment',
      params: {'p_file_id': fileId, 'p_body': text},
    );
    final list = rows as List;
    if (list.isEmpty) {
      throw const UploadFailure('Could not post your comment. Try again.');
    }
    final saved =
        FileComment.fromMap(Map<String, dynamic>.from(list.first as Map));
    return (await _withNames(c, auth, [saved])).first;
  });
}

/// Likes the comment, or removes the like when it is already liked.
Future<CommentLikeResult> toggleCommentLike(
  AuthState auth,
  String commentId,
) =>
    _run(auth, 'Could not update your like. Try again.', (c) async {
      final rows = await c.rpc(
        'toggle_community_comment_like',
        params: {'p_comment_id': commentId},
      );
      final list = rows as List;
      if (list.isEmpty) {
        throw const UploadFailure('Could not update your like. Try again.');
      }
      final m = Map<String, dynamic>.from(list.first as Map);
      return CommentLikeResult(
        liked: (m['liked'] as bool?) ?? false,
        count: (m['like_count'] as num?)?.toInt() ?? 0,
      );
    });

/// Deletes a comment (its author, or the owner of the file, may do it).
Future<void> deleteComment(AuthState auth, String commentId) =>
    _run(auth, 'Could not delete the comment. Try again.', (c) async {
      await c.rpc(
        'delete_community_comment',
        params: {'p_comment_id': commentId},
      );
    });
