import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which address asked for a sign-in link.
///
/// Firebase requires the same address to be presented when the link is
/// redeemed. That is a security property, not an inconvenience: without it,
/// anyone who intercepted the link could redeem it against an address of their
/// choosing. Since the student may tap the link minutes later, from a mail
/// app, after CoStudy has been killed, the address has to survive on disk.
///
/// Deliberately not secure storage. The address is not a secret — it is the
/// thing the student just typed on screen — and the link itself is the
/// credential.
class PendingEmailStore {
  PendingEmailStore({SharedPreferences? preferences})
      : _injected = preferences;

  static const String _key = 'costudy.pending_sign_in_email';

  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  Future<void> save(String email) async {
    final prefs = await _prefs;
    await prefs.setString(_key, email);
  }

  Future<String?> read() async {
    final prefs = await _prefs;
    return prefs.getString(_key);
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_key);
  }
}
