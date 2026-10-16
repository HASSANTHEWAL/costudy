import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'profile/student_profile.dart';
import 'screens/app_shell.dart';
import 'screens/email_entry_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No `options:` argument on purpose.
  //
  // CoStudy ships Android only (proposal D.3), and on Android the
  // google-services Gradle plugin compiles android/app/google-services.json
  // into resources that the SDK reads here. That makes a generated
  // firebase_options.dart redundant, and one fewer generated file to drift
  // from the console.
  //
  // If the app ever targets iOS or web, run `flutterfire configure` and pass
  // `options: DefaultFirebaseOptions.currentPlatform` instead.
  await Firebase.initializeApp();

  runApp(const CoStudyApp());
}

class CoStudyApp extends StatefulWidget {
  const CoStudyApp({super.key});

  @override
  State<CoStudyApp> createState() => _CoStudyAppState();
}

class _CoStudyAppState extends State<CoStudyApp> {
  final _authService = AuthService();
  final _appLinks = AppLinks();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _listenForSignInLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  /// Watch for the email sign-in link coming back into the app.
  ///
  /// `uriLinkStream` covers both cases that matter: the app was already
  /// running when the student tapped the link, and the app was launched by
  /// the tap (app_links replays the initial link on subscribe). Handling only
  /// the former would strand anyone who had swiped CoStudy away while waiting
  /// for the mail — which is most people.
  void _listenForSignInLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (Object error) => _showMessage('Tautan tidak bisa dibuka.'),
    );
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    try {
      // Non-sign-in links return null rather than throwing, so every deep
      // link can be passed straight through without pre-filtering here.
      final user = await _authService.completeSignInFromLink(uri.toString());
      if (user == null) return;
      // No success message: the UI switching to the signed-in screen is the
      // feedback, and a toast on top of it would just be noise.
    } on AuthFailure catch (failure) {
      _showMessage(failure.message);
    }
  }

  void _showMessage(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoStudy',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: buildCoStudyTheme(),
      home: AuthGate(authService: _authService),
    );
  }
}

/// Routes on authentication state.
///
/// The signed-in screen is chosen by the auth stream rather than by pushing a
/// route after sign-in, because sign-in can complete from the deep-link
/// handler while an entirely different screen is on top. Letting the stream
/// decide means there is one source of truth and no route stack to unwind.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return EmailEntryScreen(authService: authService);
        }
        return _ProfileGate(user: user, authService: authService);
      },
    );
  }
}

/// Runs Profile Setup once, before the shell.
///
/// A gate rather than a pushed route: the setup screen is not something the
/// student can back out of, and making it a *state* of the tree rather than a
/// route on top of the shell means there is no shell underneath to return to.
///
/// Keyed on `jurusan` because that is what another member's session card
/// renders. A student with no faculty would show up as a blank in someone
/// else's session.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate({required this.user, required this.authService});

  final User user;
  final AuthService authService;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  final _repository = ProfileRepository();
  late Future<StudentProfile> _profile = _repository.load(widget.user.uid);

  void _reload() {
    setState(() => _profile = _repository.load(widget.user.uid));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudentProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.blue),
            ),
          );
        }

        // On a read failure, fall through to setup rather than the shell. The
        // cost of asking twice is a mild annoyance; the cost of skipping it is
        // a member who appears as a blank to everyone else in their session.
        final profile = snapshot.data;
        if (profile == null || profile.needsSetup) {
          return ProfileSetupScreen(
            uid: widget.user.uid,
            emailKampus: widget.user.email,
            onCompleted: _reload,
          );
        }

        return AppShell(
          user: widget.user,
          authService: widget.authService,
          profile: profile,
        );
      },
    );
  }
}
