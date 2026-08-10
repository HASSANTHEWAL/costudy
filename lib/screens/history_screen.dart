import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Riwayat — the student's own session history (FR-09).
///
/// The stat strip is shown at zero rather than hidden. The design puts
/// Total / Jam / Sesi here permanently, and a row of zeros is honest and
/// stable — it tells a first-time student what this screen will become,
/// which a hidden strip that appears later does not.
///
/// The empty copy is the one the brief specifies: inviting, never a shrug.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Riwayat Sesi',
                  style: display(
                    size: 22,
                    weight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Hanya riwayatmu sendiri',
                  style: display(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.grayMid,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: _StatStrip(),
          ),
          const Expanded(
            child: EmptyState(
              icon: Icons.auto_stories_outlined,
              title: 'Sesi pertamamu akan muncul di sini',
              body: 'Setiap sesi yang kamu hadiri tercatat — tanggal, tempat, '
                  'dan berapa orang yang datang.',
              accent: AppColors.lavender,
              accentBackground: AppColors.lavenderLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip();

  @override
  Widget build(BuildContext context) {
    const stats = [('Total', '0'), ('Jam', '0j'), ('Sesi', '0')];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: cardDecoration(),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: i < stats.length - 1
                      ? const Border(
                          right: BorderSide(color: AppColors.gray),
                        )
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      stats[i].$2,
                      style: display(size: 20, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stats[i].$1,
                      style: display(
                        size: 10,
                        weight: FontWeight.w600,
                        color: AppColors.grayMid,
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
