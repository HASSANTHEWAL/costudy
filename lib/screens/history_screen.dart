import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../coalition/coalition.dart';
import '../coalition/coalition_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Riwayat — the student's own session history (FR-09).
///
/// "Own" is enforced by firestore.rules, not by the query being polite: a
/// membership list filtered by any other `idPengguna` is refused outright.
///
/// The empty copy is the one the brief specifies: inviting, never a shrug.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.userId,
    this.repository,
    this.historyStream,
  });

  final String? userId;
  final CoalitionRepository? repository;

  /// Lets a test drive the screen without Firestore.
  final Stream<List<CoalitionWithMembership>>? historyStream;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final CoalitionRepository _repository =
      widget.repository ?? CoalitionRepository();

  Stream<List<CoalitionWithMembership>> get _stream {
    if (widget.historyStream != null) return widget.historyStream!;
    final uid = widget.userId;
    if (uid == null) return const Stream.empty();
    return _repository.watchMyCoalitions(uid);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: StreamBuilder<List<CoalitionWithMembership>>(
        stream: _stream,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const <CoalitionWithMembership>[];
          final completed = entries
              .where((e) => e.coalition.status == CoalitionStatus.completed)
              .length;
          final hours = entries.fold<double>(
            0,
            (sum, e) =>
                sum +
                e.coalition.endTime
                        .difference(e.coalition.startTime)
                        .inMinutes /
                    60,
          );

          return Column(
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: _StatStrip(
                  total: entries.length,
                  hours: hours,
                  completed: completed,
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyState(
                        icon: Icons.auto_stories_outlined,
                        title: 'Sesi pertamamu akan muncul di sini',
                        body: 'Setiap sesi yang kamu hadiri tercatat — '
                            'tanggal, tempat, dan berapa orang yang datang.',
                        accent: AppColors.lavender,
                        accentBackground: AppColors.lavenderLight,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) =>
                            HistoryTile(entry: entries[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One past session.
///
/// Layout follows the prototype's history card: a 44px rounded tile, the
/// title, a status badge, and mono for the date and counts.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry});

  final CoalitionWithMembership entry;

  /// "Sabtu, 15 Agustus 2026" — Indonesian, spelled out.
  ///
  /// Dates in history are read, not scanned, so the long form is worth the
  /// width. Times stay mono because those ARE scanned.
  static String formatDate(DateTime when) {
    return DateFormat('EEEE, d MMMM y', 'id_ID').format(when);
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final coalition = entry.coalition;
    final badge = _badgeFor(coalition.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge.background,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Icon(Icons.menu_book_outlined,
                size: 18, color: badge.foreground),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Sesi belajar',
                        style: display(size: 14, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusChip(badge: badge),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  formatDate(coalition.startTime),
                  style: display(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.grayMid,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '${_hhmm(coalition.startTime)}–${_hhmm(coalition.endTime)}',
                      style: mono(size: 11),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${coalition.memberCount} orang'
                        '${coalition.faculties.isEmpty ? '' : ' · ${coalition.faculties.join(", ")}'}',
                        overflow: TextOverflow.ellipsis,
                        style: mono(size: 11, color: AppColors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge {
  const _Badge(this.label, this.foreground, this.background);

  final String label;
  final Color foreground;
  final Color background;
}

/// Status colours. None of these is yellow — yellow belongs to the moment a
/// session is found, and a history row is the opposite of that.
_Badge _badgeFor(CoalitionStatus status) {
  switch (status) {
    case CoalitionStatus.completed:
      return const _Badge('Tuntas', AppColors.greenDeep, AppColors.greenLight);
    case CoalitionStatus.failed:
      return const _Badge('Gagal', AppColors.red, AppColors.redLight);
    case CoalitionStatus.active:
      return const _Badge('Aktif', AppColors.blue, AppColors.blueLight);
    case CoalitionStatus.waiting:
      return const _Badge('Menunggu', AppColors.grayMid, AppColors.gray);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.badge});

  final _Badge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: badge.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        badge.label,
        style: display(
          size: 11,
          weight: FontWeight.w700,
          color: badge.foreground,
        ),
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.total,
    required this.hours,
    required this.completed,
  });

  final int total;
  final double hours;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Total', '$total'),
      ('Jam', '${hours.round()}j'),
      ('Sesi', '$completed'),
    ];

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
                      ? const Border(right: BorderSide(color: AppColors.gray))
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
