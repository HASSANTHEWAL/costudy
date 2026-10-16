import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'screens/email_entry_screen.dart';
import 'screens/signed_in_stub_screen.dart';
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
        return SignedInStubScreen(user: user, authService: authService);
      },
    );
  }
}
