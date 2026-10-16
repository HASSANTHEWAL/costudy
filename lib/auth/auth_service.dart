import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'campus_email.dart';
import 'pending_email_store.dart';

/// Raised when a sign-in attempt is refused for a reason worth showing the
/// student. [message] is Indonesian copy ready to render.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AuthFailure($code): $message';
}

/// Email-link (passwordless) authentication against Firebase (FR-01).
///
/// ── HOW THE LINK GETS BACK INTO THE APP ─────────────────────────────────────
/// Firebase Dynamic Links shut down on 25 August 2025. Email sign-in links are
/// now served from the project's Firebase Hosting default domain,
/// `PROJECT_ID.firebaseapp.com/__/auth/links`, and the app claims them with an
/// Android App Links intent filter (see AndroidManifest.xml). Firebase
/// publishes the matching assetlinks.json on that domain automatically.
///
/// The consequence for this class: [sendSignInLink] must point
/// [ActionCodeSettings.url] at that same host, or the link will open in a
/// browser and the student will never get back into the app.
class AuthService {
  AuthService({FirebaseAuth? auth, PendingEmailStore? pendingEmail})
      : _injectedAuth = auth,
        _pendingEmail = pendingEmail ?? PendingEmailStore();

  final FirebaseAuth? _injectedAuth;
  final PendingEmailStore _pendingEmail;

  /// Resolved lazily rather than in the constructor.
  ///
  /// `FirebaseAuth.instance` throws unless `Firebase.initializeApp()` has run,
  /// so resolving it eagerly would make this class unconstructible in a widget
  /// test. Deferring it lets tests exercise the paths that never reach
  /// Firebase — client-side domain rejection being the important one.
  late final FirebaseAuth _auth = _injectedAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// The Firebase Hosting domain that serves this project's auth links.
  ///
  /// Derived from the live FirebaseApp rather than hardcoded, so it cannot
  /// drift from whichever project google-services.json points at. The Gradle
  /// build derives the manifest's intent-filter host from the same file, so
  /// the two stay in step by construction.
  String get _authLinkHost {
    final projectId = Firebase.app().options.projectId;
    return '$projectId.firebaseapp.com';
  }

  /// Send a sign-in link to [rawEmail], after checking it is a student address.
  ///
  /// The address is remembered locally: completing sign-in requires presenting
  /// the same address that requested the link, and the student may open the
  /// link on a different screen or after the app has been killed.
  ///
  /// Throws [AuthFailure] with student-facing copy on refusal.
  Future<String> sendSignInLink(String? rawEmail) async {
    final result = verifyCampusEmail(rawEmail);
    if (!result.valid) {
      throw AuthFailure(result.message!, code: result.reason!.name);
    }
    final email = result.email!;

    final settings = ActionCodeSettings(
      // Must live on the Firebase Hosting domain and be listed under
      // Authentication > Settings > Authorized domains.
      //
      // The address is deliberately NOT carried as a query parameter here.
      // Doing so is a common shortcut for the cross-device case, but it puts
      // the address into a URL that ends up in mail logs and browser history,
      // and it defeats the point of Firebase requiring the address to be
      // presented separately: a link that already contains it is a link that
      // anyone who intercepts it can redeem alone.
      url: 'https://$_authLinkHost/__/auth/links',
      // Mandatory for email link sign-in — without it Firebase completes the
      // flow on the web instead of handing the link to the app.
      handleCodeInApp: true,
      androidPackageName: 'com.example.costudy',
      // Send the student to the Play Store rather than a dead end if they
      // opened the link on a device without CoStudy installed.
      androidInstallApp: true,
      androidMinimumVersion: '26',
    );

    try {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: settings,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_describe(error), code: error.code);
    }

    await _pendingEmail.save(email);
    return email;
  }

  /// True if [link] is a Firebase email sign-in link.
  bool isSignInLink(String link) => _auth.isSignInWithEmailLink(link);

  /// Complete sign-in from a link the app received.
  ///
  /// Returns null if [link] is not a sign-in link, so callers can pass every
  /// incoming deep link here without pre-filtering.
  ///
  /// Throws [AuthFailure] if no pending address is on record — that happens
  /// when the link is opened on a different device from the one that
  /// requested it, and the only honest fix is to ask for the address again.
  Future<User?> completeSignInFromLink(String link) async {
    if (!isSignInLink(link)) return null;

    final email = await _pendingEmail.read();
    if (email == null) {
      throw const AuthFailure(
        'Buka tautan ini di perangkat yang kamu pakai untuk meminta tautan, '
        'atau masukkan lagi alamat emailmu.',
        code: 'missing-pending-email',
      );
    }

    try {
      final credential =
          await _auth.signInWithEmailLink(email: email, emailLink: link);
      await _pendingEmail.clear();
      return credential.user;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_describe(error), code: error.code);
    }
  }

  Future<String?> readPendingEmail() => _pendingEmail.read();

  Future<void> signOut() async {
    await _pendingEmail.clear();
    await _auth.signOut();
  }

  /// Map Firebase error codes onto Indonesian copy.
  ///
  /// `invalid-argument` is what our own beforeUserCreated blocking function
  /// raises, and its message is already written for a student — so it is
  /// passed straight through rather than replaced with something vaguer.
  String _describe(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-argument':
      case 'invalid-email':
        return error.message ?? 'Alamat email tidak bisa digunakan.';
      case 'expired-action-code':
        return 'Tautan ini sudah kedaluwarsa. Minta tautan baru, ya.';
      case 'invalid-action-code':
        return 'Tautan ini sudah pernah dipakai atau tidak berlaku lagi.';
      case 'user-disabled':
        return 'Akun ini sedang dinonaktifkan.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.';
      case 'network-request-failed':
        return 'Tidak ada koneksi. Periksa jaringanmu lalu coba lagi.';
      default:
        return error.message ?? 'Terjadi kesalahan. Coba lagi.';
    }
  }
}
