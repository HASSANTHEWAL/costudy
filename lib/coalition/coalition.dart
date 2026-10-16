import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a coalition (proposal F.7).
enum CoalitionStatus {
  waiting('menunggu'),
  active('aktif'),
  completed('tuntas'),
  failed('gagal');

  const CoalitionStatus(this.wireValue);

  final String wireValue;

  static CoalitionStatus fromWire(Object? value) {
    return CoalitionStatus.values.firstWhere(
      (s) => s.wireValue == value,
      // A status this build has never seen must not throw inside a stream
      // builder — that would take out the whole Sesi tab.
      orElse: () => CoalitionStatus.waiting,
    );
  }
}

/// A student's confirmation of their own attendance.
enum ConfirmationStatus {
  pending('menunggu'),
  attending('hadir');

  const ConfirmationStatus(this.wireValue);

  final String wireValue;

  static ConfirmationStatus fromWire(Object? value) {
    return ConfirmationStatus.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => ConfirmationStatus.pending,
    );
  }
}

/// A formed session.
///
/// Note what this class does NOT expose: any way to reach a member's name.
/// The privacy requirement is enforced by shape, not by remembering — session
/// detail can only render what is here, and the roster is faculties.
class Coalition {
  const Coalition({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.lat,
    required this.lng,
    required this.memberCount,
    required this.minimumThreshold,
    required this.status,
    this.faculties = const [],
    this.formedAt,
  });

  final String id;
  final DateTime startTime;
  final DateTime endTime;

  /// The agreed meeting point. Never rendered as coordinates — the session
  /// detail card reverse-geocodes it, and falls back to a place description
  /// rather than ever printing numbers at a student.
  final double lat;
  final double lng;

  final int memberCount;
  final int minimumThreshold;
  final CoalitionStatus status;

  /// Faculty labels of the members, resolved server-side by the matcher.
  ///
  /// Denormalised on purpose: assembling this client-side would require
  /// listing the coalition's roster and reading other students' profiles, both
  /// of which firestore.rules refuses. The client is handed labels and has no
  /// path to the people behind them.
  final List<String> faculties;

  final DateTime? formedAt;

  static DateTime _millis(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Timestamp) return value.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Coalition fromFirestore(String id, Map<String, Object?> data) {
    final location = data['lokasiFinal'] as Map<String, Object?>?;
    return Coalition(
      id: id,
      startTime: _millis(data['waktuMulai']),
      endTime: _millis(data['waktuSelesai']),
      lat: (location?['lat'] as num?)?.toDouble() ?? 0,
      lng: (location?['lng'] as num?)?.toDouble() ?? 0,
      memberCount: (data['jumlahAnggota'] as num?)?.toInt() ?? 0,
      minimumThreshold: (data['ambangMinimum'] as num?)?.toInt() ?? 2,
      status: CoalitionStatus.fromWire(data['status']),
      faculties: (data['jurusanAnggota'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      formedAt: data['waktuTerbentuk'] == null
          ? null
          : _millis(data['waktuTerbentuk']),
    );
  }
}

/// The signed-in student's own membership record.
class CoalitionMembership {
  const CoalitionMembership({
    required this.id,
    required this.coalitionId,
    required this.userId,
    required this.confirmation,
  });

  final String id;
  final String coalitionId;
  final String userId;
  final ConfirmationStatus confirmation;

  bool get hasConfirmed => confirmation == ConfirmationStatus.attending;

  static CoalitionMembership fromFirestore(
    String id,
    Map<String, Object?> data,
  ) {
    return CoalitionMembership(
      id: id,
      coalitionId: data['idKoalisi'] as String? ?? '',
      userId: data['idPengguna'] as String? ?? '',
      confirmation: ConfirmationStatus.fromWire(data['statusKonfirmasi']),
    );
  }
}

/// A coalition paired with the caller's own membership — what both the Sesi
/// tab and Riwayat actually render.
class CoalitionWithMembership {
  const CoalitionWithMembership({
    required this.coalition,
    required this.membership,
  });

  final Coalition coalition;
  final CoalitionMembership membership;
}
