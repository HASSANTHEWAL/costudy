import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../profile/student_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Profil — screen 12 of the design.
///
/// Verified badge, campus email, jurusan, sign out. Note what is absent, and
/// deliberately so: no public profile, no followers, no visibility toggle.
/// There is nothing to be visible to, which is the whole point — the closing
/// line on this screen says so in as many words.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.authService,
    required this.profile,
  });

  final User user;
  final AuthService authService;

  /// Filled at Profile Setup, which the auth gate runs before this screen can
  /// ever be reached — so these are real values, not guesses from the address.
  final StudentProfile profile;

  String get _displayName {
    final nama = (profile.nama ?? '').trim();
    return nama.isEmpty ? 'Mahasiswa' : nama;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profil',
              style: display(
                size: 22,
                weight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 20),
            _IdentityCard(
              name: _displayName,
              email: profile.emailKampus ?? user.email ?? '—',
              jurusan: profile.jurusan,
              verified: user.emailVerified,
            ),
            const SizedBox(height: 12),
            const _PreferenceRow(),
            const SizedBox(height: 18),
            Text(
              'PENGATURAN',
              style: mono(size: 10, letterSpacing: 1.4),
            ),
            const SizedBox(height: 10),
            const _SettingsCard(),
            const SizedBox(height: 10),
            _SignOutButton(onTap: authService.signOut),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Profilmu tidak bisa dilihat orang lain.\n'
                'Tidak ada pengikut, tidak ada visibilitas publik.',
                textAlign: TextAlign.center,
                style: display(
                  size: 12,
                  weight: FontWeight.w500,
                  color: AppColors.grayMid,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.email,
    required this.jurusan,
    required this.verified,
  });

  final String name;
  final String email;
  final String? jurusan;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: cardDecoration(radius: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(source: email, size: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: display(size: 17, weight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _VerifiedBadge(verified: verified),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  '${jurusan ?? 'Jurusan belum diatur'} · UII',
                  style: display(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.charcoalMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    // Reflects the real emailVerified flag rather than assuming. An account
    // that has not opened its sign-in link is not a verified student, and
    // Firestore rules will refuse its writes — saying so here beats a
    // PERMISSION_DENIED later.
    final color = verified ? AppColors.blue : AppColors.grayMid;
    final background = verified ? AppColors.blueLight : AppColors.gray;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_user_outlined : Icons.schedule,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            verified ? 'Terverifikasi' : 'Belum verifikasi',
            style: display(size: 11, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniCard(
            caption: 'SUASANA FAVORIT',
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 7),
                Text(
                  'Belum diatur',
                  style: display(size: 14, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniCard(
            caption: 'SESI SELESAI',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('0', style: display(size: 24, weight: FontWeight.w800)),
                const SizedBox(width: 4),
                Text(
                  'sesi',
                  style: display(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.grayMid,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: cardDecoration(radius: AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: mono(size: 9, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    const rows = [
      (Icons.notifications_none_rounded, 'Notifikasi', 'Belum aktif'),
      (Icons.place_outlined, 'Izin Lokasi', 'Saat digunakan'),
    ];

    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              decoration: BoxDecoration(
                border: i == 0
                    ? const Border(
                        bottom: BorderSide(color: AppColors.hairline),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.blueLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(rows[i].$1, size: 18, color: AppColors.blue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      style: display(size: 14, weight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    rows[i].$3,
                    style: display(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.grayMid,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: cardDecoration(radius: AppRadius.card),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.redLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded,
                  size: 18, color: AppColors.red),
            ),
            const SizedBox(width: 12),
            Text(
              'Keluar',
              style: display(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
