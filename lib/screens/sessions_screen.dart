import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Sesi — confirmed sessions.
///
/// Empty until the coalition engine runs and notifies, which is Phase 4. The
/// empty state is written to stay true even then: it describes the mechanism
/// ("kami akan memberi tahu semua orang di saat yang sama") rather than
/// apologising for having nothing, because a student with no session has not
/// failed at anything — the system simply has not found an overlap yet.
///
/// Deliberately absent: any count of how many people are searching, any hint
/// that a match nearly happened, any "no results" phrasing.
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sesi',
                  style: display(
                    size: 22,
                    weight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sesi yang sudah terbentuk',
                  style: display(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.grayMid,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            child: EmptyState(
              icon: Icons.groups_2_outlined,
              title: 'Belum ada sesi terbentuk',
              body: 'Begitu jadwalmu beririsan dengan orang lain, kami '
                  'memberi tahu semua orang di saat yang sama.',
            ),
          ),
        ],
      ),
    );
  }
}
