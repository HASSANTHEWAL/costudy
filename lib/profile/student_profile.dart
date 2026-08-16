import 'package:cloud_firestore/cloud_firestore.dart';

/// The faculties offered at Profile Setup.
///
/// A fixed list rather than free text: `jurusan` is the only thing shown about
/// another member of a session (never a name), so it has to be a small,
/// recognisable vocabulary. Free text would leak identity — "TI 2023 kelas B"
/// names a person on a campus this size.
const List<String> kJurusanOptions = [
  'Teknik Informatika',
  'Teknik Industri',
  'Teknik Sipil',
  'Hukum',
  'Psikologi',
  'Ekonomi',
  'FIAI',
  'FMIPA',
  'Kedokteran',
  'Farmasi',
  'Lainnya',
];

/// A student's own record at users/{uid}.
///
/// firestore.rules makes this strictly owner-readable and owner-writable, so
/// the only fields another student ever sees are the ones the session detail
/// screen fetches deliberately — and that is `jurusan` alone.
class StudentProfile {
  const StudentProfile({
    required this.uid,
    this.nama,
    this.jurusan,
    this.emailKampus,
    this.preferensiSuasana,
    this.statusVerifikasi = false,
  });

  final String uid;
  final String? nama;
  final String? jurusan;
  final String? emailKampus;
  final String? preferensiSuasana;
  final bool statusVerifikasi;

  /// Whether Profile Setup still needs to run.
  ///
  /// Keyed on `jurusan` because that is the field the session detail screen
  /// depends on: a member with no jurusan would appear as a blank in another
  /// student's session card.
  bool get needsSetup => (jurusan ?? '').trim().isEmpty;

  /// Shortened for display: "Teknik Informatika" -> "Teknik".
  ///
  /// Session detail lists several of these side by side, and the full names
  /// wrap badly. Only the leading word is dropped-to, never an abbreviation
  /// that could be mistaken for a different faculty.
  static String shortJurusan(String? jurusan) {
    final value = (jurusan ?? '').trim();
    if (value.isEmpty) return 'Mahasiswa';
    if (value.startsWith('Teknik ')) return 'Teknik';
    return value;
  }

  static StudentProfile fromFirestore(String uid, Map<String, Object?>? data) {
    if (data == null) return StudentProfile(uid: uid);
    return StudentProfile(
      uid: uid,
      nama: data['nama'] as String?,
      jurusan: data['jurusan'] as String?,
      emailKampus: data['emailKampus'] as String?,
      preferensiSuasana: data['preferensiSuasana'] as String?,
      statusVerifikasi: data['statusVerifikasi'] as bool? ?? false,
    );
  }
}

/// Raised when a profile write is refused, carrying copy fit to show a
/// student plus the underlying code for logs.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'ProfileFailure($code): $message';
}

/// Reads and writes the signed-in student's own profile.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  late final FirebaseFirestore _db = _injected ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  Future<StudentProfile> load(String uid) async {
    final snapshot = await _users.doc(uid).get();
    return StudentProfile.fromFirestore(uid, snapshot.data());
  }

  /// Read another member's faculty for the session detail card.
  ///
  /// Returns the faculty and nothing else — deliberately not a StudentProfile,
  /// so a name cannot reach a widget by accident.
  Future<String?> jurusanOf(String uid) async {
    try {
      final snapshot = await _users.doc(uid).get();
      return snapshot.data()?['jurusan'] as String?;
    } on FirebaseException {
      return null;
    }
  }

  /// Save the one-time setup answers.
  ///
  /// Merged, not overwritten: fcmToken lives on the same document and is
  /// written by a different code path.
  ///
  /// Throws [ProfileFailure] with copy fit to show a student. Mapping the
  /// error here rather than letting the screen guess matters: the failure a
  /// student actually hits is `permission-denied`, and reporting that as
  /// "check your connection" sends them to fix their wifi when the real
  /// problem is that they have not opened their sign-in link yet.
  Future<void> saveSetup({
    required String uid,
    required String nama,
    required String jurusan,
    String? emailKampus,
  }) async {
    final data = <String, Object?>{
      'nama': nama.trim(),
      'jurusan': jurusan,
      'statusVerifikasi': true,
    };
    if (emailKampus != null) data['emailKampus'] = emailKampus;

    try {
      await _users.doc(uid).set(data, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      throw ProfileFailure(_describe(error), code: error.code);
    }
  }

  String _describe(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        // firestore.rules allows an owner to create and update their own
        // record, so a denial here is almost always isCampusVerified()
        // failing: email_verified stays false until the student opens the
        // sign-in link, and a session resumed from a cached token can still
        // be carrying the pre-verification claim.
        return 'Akunmu belum terverifikasi. Buka tautan masuk dari emailmu, '
            'lalu coba lagi.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Tidak ada koneksi. Periksa jaringanmu lalu coba lagi.';
      default:
        return 'Belum tersimpan (${error.code}). Coba lagi sebentar lagi.';
    }
  }
}
