import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Screen 3 — Cek emailmu.
///
/// The student leaves the app here and comes back through the email link, so
/// this screen's only jobs are to confirm where the link went and to offer a
/// resend without letting impatience turn into a mail flood.
class CheckInboxScreen extends StatefulWidget {
  const CheckInboxScreen({
    super.key,
    required this.email,
    required this.authService,
  });

  final String email;
  final AuthService authService;

  @override
  State<CheckInboxScreen> createState() => _CheckInboxScreenState();
}

class _CheckInboxScreenState extends State<CheckInboxScreen> {
  /// Long enough that the first mail has realistically arrived, short enough
  /// not to feel punitive. Also keeps us clear of Firebase's own rate limit,
  /// which surfaces as `too-many-requests` and is far more confusing.
  static const Duration _cooldown = Duration(seconds: 60);

  Timer? _ticker;
  int _secondsLeft = _cooldown.inSeconds;
  String? _error;
  String? _notice;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = _cooldown.inSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _resend() async {
    if (_resending || _secondsLeft > 0) return;

    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.authService.sendSignInLink(widget.email);
      if (!mounted) return;
      setState(() => _notice = 'Tautan baru sudah dikirim.');
      _startCooldown();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String get _countdown {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0 && !_resending;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScreenHeader(
                title: 'Cek emailmu',
                subtitle: 'Tautan masuk sudah dikirim',
                onBack: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: AppColors.blueLight,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 46,
                    color: AppColors.blue,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Kami mengirim tautan masuk ke',
                style: display(
                  size: 14,
                  weight: FontWeight.w500,
                  color: AppColors.grayMid,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.email,
                // Mono for the address: it is the one string on this screen
                // the student needs to read character by character to confirm
                // they did not mistype it.
                style: mono(
                  size: 15,
                  weight: FontWeight.w500,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.blueLight,
                  borderRadius: BorderRadius.circular(AppRadius.cardLarge),
                ),
                child: Text(
                  'Buka tautan itu di perangkat ini supaya kamu langsung '
                  'masuk ke CoStudy.',
                  style: display(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.charcoalMid,
                    height: 1.5,
                  ),
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 16),
                _Note(text: _notice!, color: AppColors.greenDeep),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _Note(text: _error!, color: AppColors.red),
              ],
              const SizedBox(height: 26),
              Center(
                child: TextButton(
                  onPressed: canResend ? _resend : null,
                  child: canResend
                      ? const Text('Kirim ulang')
                      : Text(
                          'Kirim ulang dalam $_countdown',
                          // Mono so the digits do not jitter as they count
                          // down.
                          style: mono(size: 14, weight: FontWeight.w500),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: display(
        size: 13,
        weight: FontWeight.w600,
        color: color,
        height: 1.4,
      ),
    );
  }
}
