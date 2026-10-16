import 'package:flutter/material.dart';

import '../coalition/coalition.dart';
import '../coalition/place_name.dart';
import '../theme/app_theme.dart';

/// The active session card (FR-06, FR-07).
///
/// ── THE ONLY YELLOW IN THE APP ──────────────────────────────────────────────
/// #FFD23F appears here and nowhere else in the interface. The design brief
/// reserves it for the coalition-found moment so that when a student sees it,
/// it means one thing: it worked. Spending it on a tab bar or an empty state
/// would make the payoff indistinguishable from ordinary chrome.
///
/// Within this file it is confined to three things, all of them the same
/// moment: the card's accent border, the confirm button, and the confirmed
/// checkmark. The completion state below is deliberately NOT yellow — a
/// finished session is a memory, not a discovery.
///
/// ── WHAT THIS CARD MUST NEVER SHOW ──────────────────────────────────────────
/// Names, and coordinates. Members are rendered as a count and a list of
/// faculties, which is the entire basis on which CoStudy claims a session is
/// not a social exposure. The meeting point is reverse-geocoded to a place
/// description; if that fails it degrades to a vaguer phrase, never to
/// numbers.
class SessionDetailCard extends StatelessWidget {
  const SessionDetailCard({
    super.key,
    required this.entry,
    required this.placeName,
    required this.confirming,
    required this.onConfirm,
  });

  final CoalitionWithMembership entry;

  /// Already resolved — the widget never sees lat/lng.
  final String placeName;

  final bool confirming;
  final VoidCallback onConfirm;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  String get _timeRange =>
      '${_hhmm(entry.coalition.startTime)} – ${_hhmm(entry.coalition.endTime)} WIB';

  String get _memberSummary {
    final count = entry.coalition.memberCount;
    final faculties = entry.coalition.faculties;
    if (faculties.isEmpty) return '$count mahasiswa';
    return '$count mahasiswa · ${faculties.join(", ")}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: AppColors.gray, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The accent. A 6px bar rather than a full yellow surface: the
            // colour is meant to register, not to shout.
            Container(width: 6, color: AppColors.yellow),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sesi terbentuk',
                            style: display(
                              size: 18,
                              weight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        _AtmosphereChip(entry: entry),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Framed as a shared fact, not an invitation — nobody
                    // invited anybody, which is the whole mechanism.
                    Text(
                      'Jadwal kalian beririsan.',
                      style: display(
                        size: 13,
                        weight: FontWeight.w500,
                        color: AppColors.grayMid,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DetailRow(
                      icon: Icons.schedule,
                      child: Text(
                        _timeRange,
                        style: mono(
                          size: 15,
                          weight: FontWeight.w500,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.place_outlined,
                      child: Text(
                        placeName,
                        style: display(
                          size: 14,
                          weight: FontWeight.w600,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DetailRow(
                      icon: Icons.groups_2_outlined,
                      child: Text(
                        _memberSummary,
                        style: display(
                          size: 14,
                          weight: FontWeight.w600,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (entry.membership.hasConfirmed)
                      const _ConfirmedBadge()
                    else
                      _ConfirmButton(busy: confirming, onTap: onConfirm),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.grayMid),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

class _AtmosphereChip extends StatelessWidget {
  const _AtmosphereChip({required this.entry});

  final CoalitionWithMembership entry;

  @override
  Widget build(BuildContext context) {
    // Atmosphere is a property of the coalition's members, and every member
    // agreed to it by construction — the engine treats quiet and discussion as
    // mutually exclusive. Shown as a reminder of the contract, not a setting.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.blueLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        entry.coalition.status == CoalitionStatus.completed
            ? 'Selesai'
            : 'Aktif',
        style: display(
          size: 11,
          weight: FontWeight.w700,
          color: AppColors.blue,
        ),
      ),
    );
  }
}

/// The confirm action. Yellow — this is the coalition-found moment.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.yellow,
          // Charcoal on yellow, not white: white on #FFD23F fails WCAG AA
          // badly, and this is the one button in the app that must not be
          // hard to read.
          foregroundColor: AppColors.charcoal,
          disabledBackgroundColor: AppColors.yellow,
          minimumSize: const Size.fromHeight(52),
        ),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.charcoal,
                ),
              )
            : const Text('Konfirmasi Kehadiran'),
      ),
    );
  }
}

/// The confirmed state. Still yellow, still the same moment — but inert.
class _ConfirmedBadge extends StatelessWidget {
  const _ConfirmedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellow, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_rounded, size: 20, color: AppColors.charcoal),
          const SizedBox(width: 8),
          Text(
            'Sudah dikonfirmasi',
            style: display(size: 15, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Shown once the coalition reaches 'tuntas'.
///
/// Deliberately NOT yellow. A finished session is a memory; the bright colour
/// belongs to the moment of discovery, and reusing it here would blunt it.
class SessionCompletedCard extends StatelessWidget {
  const SessionCompletedCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.greenLight,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 22, color: AppColors.greenDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sesi selesai',
                  style: display(size: 17, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sesi selesai — lihat riwayat kamu.',
            style: display(
              size: 14,
              weight: FontWeight.w500,
              color: AppColors.charcoalMid,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(foregroundColor: AppColors.greenDeep),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

/// Resolve a meeting point to a place description.
Future<String> resolvePlaceName(
  PlaceNameResolver resolver,
  Coalition coalition,
) {
  return resolver.describe(coalition.lat, coalition.lng);
}
