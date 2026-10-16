import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/mascot.dart';
import 'register_intent_screen.dart';

/// Screen 7 — Waiting. The most important screen in the app.
///
/// The design brief is emphatic that this must NOT look like an empty list or
/// a spinner over nothing. The failure mode of every comparable product is a
/// board with zero rows on it; here the screen shows work happening — pulsing
/// rings, the mascot breathing, and the student's own registered window as
/// content so the screen is never bare.
///
/// It also never reports absence. There is no "nobody found" state, no count
/// of candidates, no progress bar implying a deadline. An intent that finds
/// nothing expires silently and the student is never told they were passed
/// over (scenario 6, proposal F.5).
///
/// Dark surface, unlike everything else in the app. That is intentional in the
/// prototype: it reads as the system working in the background rather than as
/// another form to fill in.
class WaitingScreen extends StatelessWidget {
  const WaitingScreen({super.key, required this.summary});

  final RegisteredIntentSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: Stack(
        children: [
          const Positioned.fill(child: _StarField()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _CancelButton(onTap: () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _PrivacyPill(),
                const SizedBox(height: 40),
                const SizedBox(height: 210, child: _PulsingRings()),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    children: [
                      Text(
                        'Mencari irisan jadwal…',
                        textAlign: TextAlign.center,
                        style: display(
                          size: 26,
                          weight: FontWeight.w800,
                          color: AppColors.white,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Pencocokan terjadi secara privat. Kamu tidak akan '
                        'muncul bagi orang lain sampai sesi terbentuk.',
                        textAlign: TextAlign.center,
                        style: display(
                          size: 14,
                          weight: FontWeight.w500,
                          color: AppColors.white.withValues(alpha: 0.45),
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _OwnWindowCard(summary: summary),
                ),
                const Spacer(),
                const _SearchingTicker(),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint dot grid, 5% white — the prototype's background texture.
class _StarField extends StatelessWidget {
  const _StarField();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _StarFieldPainter()),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.white.withValues(alpha: 0.05);
    for (var i = 0; i < 30; i++) {
      final x = ((i % 6) * 18 + 9) / 100 * size.width;
      final y = ((i ~/ 6) * 20 + 8) / 100 * size.height;
      canvas.drawCircle(Offset(x, y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close,
                size: 14, color: AppColors.white.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(
              'Batalkan niat',
              style: display(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The pill hugs its content, but the content is a long sentence — give
      // it a margin to shrink into rather than letting it run off the edge at
      // a large text scale.
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 13, color: AppColors.lavender),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                'Niatmu tersembunyi sampai sesi terbentuk',
                style: display(
                  size: 12,
                  weight: FontWeight.w600,
                  color: AppColors.lavender,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three rings expanding outward on a staggered loop, with the mascot face
/// floating at the centre.
///
/// The prototype's `pulseRing`: scale 1 → 2.8, opacity 0.7 → 0, 2.7s, staggered
/// 0.8s apart so there is always a ring mid-flight. That continuity is the
/// point — a gap would read as a stalled process.
class _PulsingRings extends StatefulWidget {
  const _PulsingRings();

  @override
  State<_PulsingRings> createState() => _PulsingRingsState();
}

class _PulsingRingsState extends State<_PulsingRings>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 2700);
  static const int _ringCount = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return SizedBox(
                width: 300,
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < _ringCount; i++)
                      _Ring(
                        // Stagger by a third of the period so a ring departs
                        // as the previous one fades.
                        progress: (_controller.value + i / _ringCount) % 1.0,
                      ),
                  ],
                ),
              );
            },
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.blue.withValues(alpha: 0.44),
                  AppColors.blue.withValues(alpha: 0),
                ],
                stops: const [0, 0.7],
              ),
            ),
          ),
          const FloatingMascot(child: MascotFace(size: 68)),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + progress * 1.8; // 1 → 2.8
    final opacity = (0.7 * (1 - progress)).clamp(0.0, 0.7);

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.blue.withValues(alpha: opacity),
            width: 1.5 / math.max(scale, 0.001),
          ),
        ),
      ),
    );
  }
}

/// The student's own registered window, shown back to them.
///
/// This is what keeps the screen from being empty, and it is the only content
/// here that could ever be mistaken for a list. It is one card, and it is the
/// student's own — never anyone else's.
class _OwnWindowCard extends StatelessWidget {
  const _OwnWindowCard({required this.summary});

  final RegisteredIntentSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NIATMU',
            style: mono(
              size: 10,
              color: AppColors.white.withValues(alpha: 0.3),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in summary.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: display(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "MENCARI ···" shimmering on a 2s loop — the prototype's `shimmerPulse`.
class _SearchingTicker extends StatefulWidget {
  const _SearchingTicker();

  @override
  State<_SearchingTicker> createState() => _SearchingTickerState();
}

class _SearchingTickerState extends State<_SearchingTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.4, end: 0.9)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Text(
        'MENCARI ···',
        style: mono(
          size: 11,
          color: AppColors.white.withValues(alpha: 0.28),
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}
