import 'package:cloud_firestore/cloud_firestore.dart';

import 'study_intent.dart';

/// Raised when an intent cannot be stored, carrying copy fit to show a student.
class IntentFailure implements Exception {
  const IntentFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'IntentFailure($code): $message';
}

/// Firestore access for availability windows (FR-02, FR-03).
///
/// Every query here filters on `idPengguna`. That is not defensive style — it
/// is required. firestore.rules allows `list` only when the query itself
/// proves each result belongs to the caller, so an unfiltered read of /intents
/// is rejected outright rather than returning a trimmed set. Dropping the
/// filter does not leak data; it breaks the query.
class IntentRepository {
  IntentRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  static const String collectionPath = 'intents';

  final FirebaseFirestore? _injected;

  /// Resolved lazily so the class can be constructed before Firebase starts.
  late final FirebaseFirestore _db = _injected ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _intents =>
      _db.collection(collectionPath);

  /// Store a new private availability window.
  ///
  /// Returns the new document id. Nothing about this document is visible to
  /// any other student — see firestore.rules.
  Future<String> register(StudyIntent intent) async {
    try {
      final reference = await _intents.add(intent.toFirestore());
      return reference.id;
    } on FirebaseException catch (error) {
      throw IntentFailure(_describe(error), code: error.code);
    }
  }

  /// The caller's own active intents, newest first.
  Stream<List<StudyIntent>> watchMyActiveIntents(String userId) {
    return _intents
        .where('idPengguna', isEqualTo: userId)
        .where('status', isEqualTo: IntentStatus.active.wireValue)
        .orderBy('waktuMulai', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => StudyIntent.fromFirestore(d.data())).toList());
  }

  /// Withdraw an intent. The only mutation firestore.rules permits a client.
  Future<void> cancel(String intentId) async {
    try {
      await _intents.doc(intentId).update({
        'status': IntentStatus.cancelled.wireValue,
      });
    } on FirebaseException catch (error) {
      throw IntentFailure(_describe(error), code: error.code);
    }
  }

  String _describe(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        // In practice this means the account is not a verified student, since
        // the rules refuse writes from anyone else. Worth saying plainly
        // rather than showing a raw Firestore code.
        return 'Akunmu belum terverifikasi sebagai mahasiswa UII. '
            'Buka tautan masuk dari emailmu dulu, ya.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Tidak ada koneksi. Periksa jaringanmu lalu coba lagi.';
      default:
        return 'Niatmu belum tersimpan. Coba lagi sebentar lagi.';
    }
  }
}
