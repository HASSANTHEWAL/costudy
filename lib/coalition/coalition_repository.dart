import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'coalition.dart';

/// Reads the caller's own coalitions and confirms their attendance.
///
/// Every read starts from `coalitionMembers` filtered by `idPengguna`, never
/// from `coalitions`. That is forced by firestore.rules: coalitions cannot be
/// listed at all, and an individual coalition is readable only when the
/// caller's own member document exists at the deterministic id
/// `<idKoalisi>_<idPengguna>`. Membership is the entry point by design — there
/// is no path from "a session exists" to "who is in it".
class CoalitionRepository {
  CoalitionRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  late final FirebaseFirestore _db = _injected ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('coalitionMembers');

  CollectionReference<Map<String, dynamic>> get _coalitions =>
      _db.collection('coalitions');

  /// Deterministic member document id — the same shape firestore.rules uses
  /// to prove membership with a single exists().
  static String memberDocId(String coalitionId, String userId) =>
      '${coalitionId}_$userId';

  /// Every coalition this student belongs to, newest session first.
  ///
  /// A collection-group query is deliberately not used: no
  /// `match /{path=**}/coalitionMembers/{id}` rule exists, so one would be
  /// refused outright. The `where('idPengguna')` filter is what makes this
  /// query provably the caller's own.
  Stream<List<CoalitionWithMembership>> watchMyCoalitions(String userId) {
    return _members
        .where('idPengguna', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      final memberships = snapshot.docs
          .map((d) => CoalitionMembership.fromFirestore(d.id, d.data()))
          .where((m) => m.coalitionId.isNotEmpty)
          .toList();

      final results = <CoalitionWithMembership>[];
      for (final membership in memberships) {
        final doc = await _coalitions.doc(membership.coalitionId).get();
        final data = doc.data();
        if (data == null) continue;
        results.add(
          CoalitionWithMembership(
            coalition: Coalition.fromFirestore(doc.id, data),
            membership: membership,
          ),
        );
      }

      results.sort(
        (a, b) => b.coalition.startTime.compareTo(a.coalition.startTime),
      );
      return results;
    });
  }

  /// The one session worth showing on Sesi: the active one, if any.
  Stream<CoalitionWithMembership?> watchActiveCoalition(String userId) {
    return watchMyCoalitions(userId).map((all) {
      for (final entry in all) {
        if (entry.coalition.status == CoalitionStatus.active ||
            entry.coalition.status == CoalitionStatus.completed) {
          return entry;
        }
      }
      return null;
    });
  }

  /// FR-07 — confirm the caller's own attendance.
  ///
  /// Writes exactly one field. firestore.rules pins every other field to its
  /// current value, so a wider write would be rejected rather than partially
  /// applied — in particular `statusKehadiran`, which is not a self-report.
  Future<void> confirmAttendance({
    required String coalitionId,
    required String userId,
  }) async {
    await _members.doc(memberDocId(coalitionId, userId)).update({
      'statusKonfirmasi': ConfirmationStatus.attending.wireValue,
    });
  }
}
