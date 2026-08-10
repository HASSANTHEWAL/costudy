import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mascot.dart';
import 'register_intent_screen.dart';
import 'waiting_screen.dart';

/// Beranda — screen 5 of the design.
///
/// A greeting, one dominant CTA, and the student's own active intent if there
/// is one. Nothing else: no feed, no discovery, no other users. The emptiness
/// is deliberate — every comparable product fills this space with people to
/// browse, which is the thing that reintroduces first-initiative risk.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user, required this.onSeeSessions});

  final User user;
  final VoidCallback onSeeSessions;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Held locally, not read back from Firestore.
  ///
  /// Watching the student's own intents is a real feature, but it belongs with
  /// the matcher in Phase 4 — wiring a live query here now would mean building
  /// half of it and leaving the other half to contradict it.
  RegisteredIntentSummary? _activeIntent;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat pagi ☀️';
    if (hour < 15) return 'Selamat siang';
    if (hour < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  String get _displayName {
    final email = widget.user.email ?? '';
    final local = email.split('@').first;
    if (local.isEmpty) return 'Mahasiswa';
    return local
        .split(RegExp(r'[.\-_]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  Future<void> _registerIntent() async {
    final summary = await Navigator.of(context).push<RegisteredIntentSummary>(
      MaterialPageRoute(
        builder: (_) => RegisterIntentScreen(userId: widget.user.uid),
      ),
    );
    if (summary == null || !mounted) return;

    setState(() => _activeIntent = summary);

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WaitingScreen(summary: summary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: display(
                            size: 13,
                            weight: FontWeight.w500,
                            color: AppColors.grayMid,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: display(
                            size: 22,
                            weight: FontWeight.w800,
                            letterSpacing: -0.4,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InitialsAvatar(source: widget.user.email ?? '?'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _StudyCta(onTap: _registerIntent),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _activeIntent == null
                  ? const _NoActiveIntent()
                  : _ActiveIntentCard(
                      summary: _activeIntent!,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              WaitingScreen(summary: _activeIntent!),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The hero CTA — blue, oversized, with the mascot bleeding off the right edge.
class _StudyCta extends StatelessWidget {
  const _StudyCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blue,
      borderRadius: BorderRadius.circular(AppRadius.hero),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Positioned(
              right: -10,
              bottom: 0,
              child: CoStudyMascot(width: 142),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 188),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saya ingin\nbelajar',
                      style: display(
                        size: 32,
                        weight: FontWeight.w800,
                        color: AppColors.white,
                        height: 1.05,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Daftarkan niat',
                            style: display(
                              size: 14,
                              weight: FontWeight.w700,
                              color: AppColors.blue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right,
                              size: 16, color: AppColors.blue),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoActiveIntent extends StatelessWidget {
  const _NoActiveIntent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 30, 10, 12),
      child: Text(
        'Belum ada sesi aktif.\nDaftarkan niatmu untuk mulai mencari.',
        textAlign: TextAlign.center,
        style: display(
          size: 14,
          weight: FontWeight.w500,
          color: AppColors.grayMid,
          height: 1.6,
        ),
      ),
    );
  }
}

class _ActiveIntentCard extends StatelessWidget {
  const _ActiveIntentCard({required this.summary, required this.onTap});

  final RegisteredIntentSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.lavenderLight,
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          border: Border.all(color: AppColors.lavender, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sedang mencari sesi',
                    style: display(size: 14, weight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.blue),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in summary.tags)
                  InfoChip(
                    label: tag,
                    background: AppColors.lavender.withValues(alpha: 0.2),
                    border: AppColors.lavender,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
