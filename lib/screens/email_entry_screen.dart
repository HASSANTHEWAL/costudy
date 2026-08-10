import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/campus_email.dart';
import '../theme/app_theme.dart';
import '../widgets/mascot.dart';
import 'check_inbox_screen.dart';

/// Screens 1 + 2 of the design, merged — welcome and email entry.
///
/// The prototype separates them, but a standalone Welcome whose only action is
/// "sign in" is a tap the student has to make before they can do anything.
/// Folding the branded header onto the entry screen keeps the mascot, the
/// wordmark and the tagline while removing that step.
///
/// The inline error names the specific mistake rather than saying "invalid
/// email", because the most common failure is a student typing their
/// @uii.ac.id address, and telling them exactly which address to use instead
/// is the whole job of this screen.
class EmailEntryScreen extends StatefulWidget {
  const EmailEntryScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends State<EmailEntryScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;

    // Check locally first so an obvious mistake costs no round trip. The
    // Cloud Function re-checks regardless; this is UX, not enforcement.
    final check = verifyCampusEmail(_controller.text);
    if (!check.valid) {
      setState(() => _error = check.message);
      return;
    }

    setState(() {
      _error = null;
      _sending = true;
    });

    try {
      final email = await widget.authService.sendSignInLink(_controller.text);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CheckInboxScreen(
            email: email,
            authService: widget.authService,
          ),
        ),
      );
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _BrandHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tidak ada yang belajar sendirian karena gagal terhubung.',
                    style: display(
                      size: 21,
                      weight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Daftarkan waktu luangmu. Sistem kami mencarikan teman '
                    'belajar yang cocok secara diam-diam.',
                    style: display(
                      size: 14,
                      weight: FontWeight.w500,
                      color: AppColors.grayMid,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _DomainBanner(),
                  const SizedBox(height: 22),
                  Text(
                    'EMAIL KAMPUS',
                    style: display(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.grayMid,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    enabled: !_sending,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    style: display(size: 15, weight: FontWeight.w600),
                    // Clear a stale error as soon as the student starts fixing
                    // it; leaving it up while they type reads as nagging.
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: InputDecoration(
                      hintText: 'nama@$kCampusDomain',
                      errorText: _error,
                      // The message runs to two lines; the default one-line
                      // clamp would cut off the part that says what to do.
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text('Kirim tautan verifikasi'),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 13, color: AppColors.grayMid),
                      const SizedBox(width: 5),
                      // Flexible, not fixed: this string is long enough to
                      // overflow a narrow screen once the student turns up
                      // their system text size.
                      Flexible(
                        child: Text(
                          'Hanya untuk mahasiswa terverifikasi',
                          style: display(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.grayMid,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blue gradient header with the wordmark and mascot, curving into the page.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _CurveClipper(),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.blue, AppColors.blueDark],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 46),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Co',
                      style: display(
                        size: 32,
                        weight: FontWeight.w800,
                        color: AppColors.lavender,
                        letterSpacing: -0.8,
                      ),
                    ),
                    Text(
                      'Study',
                      style: display(
                        size: 32,
                        weight: FontWeight.w800,
                        color: AppColors.white,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const CoStudyMascot(width: 186),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The prototype ends the header with a shallow upward curve rather than a
/// straight edge.
class _CurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..lineTo(0, size.height)
      ..quadraticBezierTo(size.width / 2, size.height - 38, size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DomainBanner extends StatelessWidget {
  const _DomainBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blueLight,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 16, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: display(
                  size: 13,
                  weight: FontWeight.w500,
                  color: AppColors.blue,
                ),
                children: [
                  const TextSpan(text: 'Domain aktif: '),
                  TextSpan(
                    text: '@$kCampusDomain',
                    style: display(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
