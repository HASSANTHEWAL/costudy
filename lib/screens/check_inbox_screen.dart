import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';

/// Screen 3 of the design — "check your inbox".
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
    final textTheme = Theme.of(context).textTheme;
    final canResend = _secondsLeft == 0 && !_resending;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InboxGlyph(),
              const SizedBox(height: 28),
              Text('Cek emailmu', style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text('Kami mengirim tautan masuk ke', style: textTheme.bodyLarge),
              const SizedBox(height: 6),
              Text(
                widget.email,
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.blueLight,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  'Buka tautan itu di perangkat ini supaya kamu langsung masuk '
                  'ke CoStudy.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.charcoalMid,
                  ),
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 16),
                Text(
                  _notice!,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.green),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.red),
                ),
              ],
              const SizedBox(height: 28),
              TextButton(
                onPressed: canResend ? _resend : null,
                child: Text(
                  canResend
                      ? 'Kirim ulang'
                      // Monospace so the digits do not jitter as they count
                      // down — the design reserves DM Mono for times and
                      // counts exactly like this one.
                      : 'Kirim ulang dalam $_countdown',
                  style: canResend
                      ? null
                      : const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: AppColors.grayMid,
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

/// A quiet placeholder where the mascot belongs.
///
/// The design puts the two-blob mascot on this screen. Drawing it properly is
/// its own change; an obviously simple shape is better than a rough imitation
/// that later has to be un-learned.
class _InboxGlyph extends StatelessWidget {
  const _InboxGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      width: 96,
      decoration: const BoxDecoration(
        color: AppColors.blueLight,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.mark_email_unread_outlined,
          size: 44, color: AppColors.blue),
    );
  }
}
