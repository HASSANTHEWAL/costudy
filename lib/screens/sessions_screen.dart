import 'package:flutter/material.dart';

import '../coalition/coalition.dart';
import '../coalition/coalition_repository.dart';
import '../coalition/place_name.dart';
import '../profile/student_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'session_detail_card.dart';

/// Sesi — the student's one active session, or nothing.
///
/// One session at a time by construction: the matcher will not place a student
/// in two coalitions whose windows overlap, and this tab shows the first
/// active one. There is no list to browse, because there is never more than
/// one thing here worth looking at.
///
/// The empty state does not apologise. A student with no session has not
/// failed at anything — the system simply has not found an overlap yet, and
/// saying more than that would turn silence into a verdict.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    super.key,
    this.userId,
    this.repository,
    this.profiles,
    this.placeResolver,
    this.activeCoalitionStream,
  });

  final String? userId;

  /// Injectable for tests; the app constructs the real ones.
  final CoalitionRepository? repository;
  final ProfileRepository? profiles;
  final PlaceNameResolver? placeResolver;

  /// Lets a test drive the screen without Firestore.
  final Stream<CoalitionWithMembership?>? activeCoalitionStream;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final CoalitionRepository _repository =
      widget.repository ?? CoalitionRepository();
  late final ProfileRepository _profiles =
      widget.profiles ?? ProfileRepository();
  late final PlaceNameResolver _placeResolver =
      widget.placeResolver ?? const PlaceNameResolver();

  bool _confirming = false;
  String? _dismissedCompletionId;
  String? _error;

  Stream<CoalitionWithMembership?> get _stream {
    if (widget.activeCoalitionStream != null) {
      return widget.activeCoalitionStream!;
    }
    final uid = widget.userId;
    if (uid == null) return const Stream.empty();
    return _repository.watchActiveCoalition(uid);
  }

  Future<void> _confirm(CoalitionWithMembership entry) async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _error = null;
    });

    try {
      await _repository.confirmAttendance(
        coalitionId: entry.coalition.id,
        userId: entry.membership.userId,
      );
      // No local state flip: the stream re-emits with statusKonfirmasi
      // updated, so the confirmed badge appears from the source of truth
      // rather than from an optimistic guess that could disagree with it.
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Belum tersimpan. Periksa koneksimu lalu coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

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
          Expanded(
            child: StreamBuilder<CoalitionWithMembership?>(
              stream: _stream,
              builder: (context, snapshot) {
                final entry = snapshot.data;

                if (entry == null) return const _EmptySessions();

                if (entry.coalition.status == CoalitionStatus.completed) {
                  if (_dismissedCompletionId == entry.coalition.id) {
                    return const _EmptySessions();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: SessionCompletedCard(
                      onDismiss: () => setState(
                        () => _dismissedCompletionId = entry.coalition.id,
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                  child: _ActiveSession(
                    entry: entry,
                    profiles: _profiles,
                    placeResolver: _placeResolver,
                    confirming: _confirming,
                    error: _error,
                    onConfirm: () => _confirm(entry),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads the two pieces of context the card needs — a place name and the
/// members' faculties — then renders it.
///
/// Both are resolved here rather than in the card so the card itself stays a
/// pure function of already-safe data: it is handed strings, and there is no
/// path from it back to a coordinate or a name.
class _ActiveSession extends StatefulWidget {
  const _ActiveSession({
    required this.entry,
    required this.profiles,
    required this.placeResolver,
    required this.confirming,
    required this.error,
    required this.onConfirm,
  });

  final CoalitionWithMembership entry;
  final ProfileRepository profiles;
  final PlaceNameResolver placeResolver;
  final bool confirming;
  final String? error;
  final VoidCallback onConfirm;

  @override
  State<_ActiveSession> createState() => _ActiveSessionState();
}

class _ActiveSessionState extends State<_ActiveSession> {
  String _placeName = PlaceNameResolver.fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ActiveSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.coalition.id != widget.entry.coalition.id) _load();
  }

  Future<void> _load() async {
    final name = await widget.placeResolver.describe(
      widget.entry.coalition.lat,
      widget.entry.coalition.lng,
    );
    if (mounted) setState(() => _placeName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SessionDetailCard(
          entry: widget.entry,
          placeName: _placeName,
          confirming: widget.confirming,
          onConfirm: widget.onConfirm,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 12),
          Text(
            widget.error!,
            style: display(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.red,
            ),
          ),
        ],
        const SizedBox(height: 16),
        const PrivacyNote(
          text: 'Kamu hanya melihat jurusan teman sesimu, bukan nama mereka.',
        ),
      ],
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.groups_2_outlined,
      title: 'Belum ada sesi terbentuk',
      body: 'Begitu jadwalmu beririsan dengan orang lain, kami memberi tahu '
          'semua orang di saat yang sama.',
    );
  }
}
