/// Name shown for an account.
///
/// 1. A real name saved on the account (`full_name` / `name` in the Supabase
///    user metadata) - this is what the future registration page will set.
/// 2. Until then, a name made from the email address:
///      oliver@test.com        -> Oliver Test   (one word: add the domain)
///      john.doe@school.edu    -> John Doe      (several words: use them)
///
/// Keep in sync with `derive_display_name` in supabase/display_names.sql,
/// which builds the same name for OTHER users (comments, authors).
String displayNameFrom({Map<String, dynamic>? metadata, String? email}) {
  final meta = metadata ?? const <String, dynamic>{};
  final saved = (meta['full_name'] ?? meta['name'])?.toString().trim() ?? '';
  if (saved.isNotEmpty) return saved;

  final mail = (email ?? '').trim();
  final at = mail.indexOf('@');
  if (at <= 0) return 'Unknown user';

  final local = mail.substring(0, at);
  final domain = mail.substring(at + 1).split('.').first;

  final parts = local
      .toLowerCase()
      .replaceAll(RegExp(r'[0-9]+'), '')
      .split(RegExp(r'[._+-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    parts.add(local);
  } else if (parts.length == 1) {
    final d = domain.toLowerCase().replaceAll(RegExp(r'[0-9]+'), '');
    if (d.isNotEmpty) parts.add(d);
  }
  return parts
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}
