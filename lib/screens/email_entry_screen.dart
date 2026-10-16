import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../auth/campus_email.dart';
import '../theme/app_theme.dart';
import 'check_inbox_screen.dart';

/// Screen 2 of the design — email entry (FR-01).
///
/// One input, one action. The inline error names the specific mistake rather
/// than saying "invalid email", because the most common failure here is a
/// student typing their @uii.ac.id address, and telling them exactly which
/// address to use instead is the whole job of this screen.
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
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Masuk dengan email kampus', style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                'Kami akan mengirim tautan masuk. Tidak ada kata sandi yang '
                'perlu diingat.',
                style: textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                enabled: !_sending,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                // Clear a stale error as soon as the student starts fixing it;
                // leaving it up while they type reads as nagging.
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: 'nama@$kCampusDomain',
                  errorText: _error,
                  // The message can run to two lines; the default one-line
                  // clamp would truncate the part that says what to do.
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gunakan alamat @$kCampusDomain',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.grayMid),
              ),
              const SizedBox(height: 28),
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
              const SizedBox(height: 16),
              Text(
                'Hanya untuk mahasiswa terverifikasi.',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.grayMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
