import 'package:cloud_firestore/cloud_firestore.dart';

/// Study atmosphere preference — a hard matching constraint, not a hint.
///
/// The proposal's B.2 rests on this: the largest collaboration profile found
/// in the literature was "Inefficient Socializers", high on emotional support
/// and low on academic engagement. Pairing someone who wants silence with
/// someone who wants to talk reliably produces that failure, so the coalition
/// engine treats quiet and discussion as mutually exclusive rather than as
/// preferences to be traded off.
enum Atmosphere {
  quiet('hening', 'Hening', 'Fokus tanpa suara, dilarang bicara'),
  discussion('diskusi', 'Diskusi', 'Boleh bertanya dan berdiskusi pelan'),
  any('bebas', 'Bebas', 'Tidak ada aturan suasana tertentu');

  const Atmosphere(this.wireValue, this.label, this.description);

  /// Stored value, Indonesian, matching firestore.rules' `suasana` check.
  ///
  /// The coalition engine still speaks 'quiet' | 'discussion' | 'any' —
  /// functions/src/intentMapper.js translates at the boundary so the
  /// algorithm stays free of domain vocabulary. Change one, change the other.
  final String wireValue;

  final String label;
  final String description;
}

/// Lifecycle of an intent (proposal F.7).
///
/// Only [active] is ever written by the client — firestore.rules enforces
/// that. Everything past it is the coalition engine's to set, through the
/// Admin SDK.
enum IntentStatus {
  active('aktif'),
  matched('tercocokkan'),
  expired('kedaluwarsa'),
  cancelled('dibatalkan');

  const IntentStatus(this.wireValue);

  final String wireValue;
}

/// A private availability window (FR-02, proposal F.7).
///
/// ── FIELD NAMING ────────────────────────────────────────────────────────────
/// F.7 lists these attributes in ERD notation (user_id, start_time, radius_m).
/// The stored documents use camelCase instead, because the coalition formation
/// engine in functions/src/coalitionEngine.js already consumes exactly this
/// shape. Matching it means the scheduled function reads Firestore documents
/// directly with no translation layer — and a mapping layer between two
/// spellings of the same field is precisely where a silent mismatch would
/// hide.
///
/// Times are epoch milliseconds rather than Firestore Timestamps, for the same
/// reason: that is what the engine's overlap arithmetic expects.
class StudyIntent {
  const StudyIntent({
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.atmosphere,
    this.status = IntentStatus.active,
  });

  final String userId;
  final DateTime startTime;
  final DateTime endTime;
  final double lat;
  final double lng;
  final int radiusM;
  final Atmosphere atmosphere;
  final IntentStatus status;

  Duration get duration => endTime.difference(startTime);

  /// Serialise for Firestore.
  ///
  /// The key set here must match `isValidIntent` in firestore.rules exactly —
  /// that rule uses hasOnly(), so an extra field is a rejected write rather
  /// than a silently ignored one. That is deliberate: it turns a client/rules
  /// mismatch into a loud failure.
  Map<String, Object?> toFirestore() {
    return {
      'idPengguna': userId,
      'waktuMulai': startTime.millisecondsSinceEpoch,
      'waktuSelesai': endTime.millisecondsSinceEpoch,
      'lat': lat,
      'lng': lng,
      'radiusM': radiusM,
      'suasana': atmosphere.wireValue,
      'status': status.wireValue,
      'dibuatPada': FieldValue.serverTimestamp(),
    };
  }

  static StudyIntent fromFirestore(Map<String, Object?> data) {
    return StudyIntent(
      userId: data['idPengguna']! as String,
      startTime:
          DateTime.fromMillisecondsSinceEpoch(data['waktuMulai']! as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(data['waktuSelesai']! as int),
      lat: (data['lat']! as num).toDouble(),
      lng: (data['lng']! as num).toDouble(),
      radiusM: data['radiusM']! as int,
      atmosphere:
          Atmosphere.values.firstWhere((a) => a.wireValue == data['suasana']),
      // Falls back rather than throwing: the matcher can advance an intent to
      // a status this build has never seen, and a StateError deep inside a
      // stream would take out the screen showing the student their own window.
      status: IntentStatus.values.firstWhere(
        (s) => s.wireValue == data['status'],
        orElse: () => IntentStatus.expired,
      ),
    );
  }
}

/// Why an intent cannot be registered as entered.
///
/// Mirrors the range checks in firestore.rules so the student gets a sentence
/// instead of a PERMISSION_DENIED. The rules remain the enforcement point;
/// this only saves a round trip.
class IntentValidation {
  const IntentValidation._(this.message);

  final String? message;

  bool get isValid => message == null;

  static const _ok = IntentValidation._(null);

  /// Shortest window worth travelling for — the same 60 minutes the coalition
  /// engine uses as its minimum overlap. An intent below it could never form a
  /// coalition, so accepting one would mean guaranteed silent expiry.
  static const Duration minimumWindow = Duration(minutes: 60);

  static IntentValidation check({
    required DateTime? startTime,
    required DateTime? endTime,
    required double? lat,
    required double? lng,
    required int radiusM,
  }) {
    if (startTime == null || endTime == null) {
      return const IntentValidation._('Pilih waktu mulai dan selesai dulu.');
    }
    if (!endTime.isAfter(startTime)) {
      return const IntentValidation._(
        'Waktu selesai harus setelah waktu mulai.',
      );
    }
    if (endTime.difference(startTime) < minimumWindow) {
      return const IntentValidation._(
        'Sesi minimal 1 jam supaya sepadan dengan perjalanannya.',
      );
    }
    if (lat == null || lng == null) {
      return const IntentValidation._(
        'Kami belum tahu lokasimu. Ketuk "Gunakan lokasi saya sekarang".',
      );
    }
    if (radiusM <= 0 || radiusM > 5000) {
      return const IntentValidation._('Jarak tempuh tidak valid.');
    }
    return _ok;
  }
}
