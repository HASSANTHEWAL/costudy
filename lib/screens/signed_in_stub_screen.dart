import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import 'register_intent_screen.dart';

/// PLACEHOLDER — not the Home screen.
///
/// This exists only to prove the auth loop closed: the student is signed in,
/// with a verified campus address, and can sign out again. The real Home
/// (greeting, the "Saya ingin belajar" CTA, active intent or next session,
/// bottom nav) is a later change, and the intent form is deliberately absent.
///
/// Do not grow this screen. Replace it.
class SignedInStubScreen extends StatelessWidget {
  const SignedInStubScreen({
    super.key,
    required this.user,
    required this.authService,
  });

  final User user;
  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _VerifiedBadge(),
              const SizedBox(height: 24),
              Text('Kamu sudah masuk', style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(
                user.email ?? '(alamat tidak diketahui)',
                style: textTheme.bodyLarge?.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.gray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Layar sementara',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Beranda dan pendaftaran niat belum dibuat. Bagian ini '
                      'hanya menandakan proses masuk sudah berhasil.',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // The one real entry point so far (FR-02). Still not the Home
              // screen from the design — no greeting, no active-intent card,
              // no bottom nav.
              FilledButton(
                onPressed: () => _openRegisterIntent(context),
                child: const Text('Saya ingin belajar'),
              ),
              const Spacer(),
              TextButton(
                onPressed: authService.signOut,
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openRegisterIntent(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final registered = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RegisterIntentScreen(
        userId: FirebaseAuth.instance.currentUser!.uid,
      ),
    ),
  );

  if (registered != true) return;
  // Placeholder acknowledgement. The design's Waiting screen — pulsing rings,
  // the student's own window shown back to them — is a later change.
  messenger.showSnackBar(
    const SnackBar(content: Text('Niatmu tersimpan. Kami mulai mencari.')),
  );
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 18, color: AppColors.green),
          SizedBox(width: 6),
          Text(
            'Mahasiswa terverifikasi',
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
