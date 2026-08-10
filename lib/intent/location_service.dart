import 'package:geolocator/geolocator.dart';

/// Raised when a position cannot be obtained, with copy fit to show a student.
class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;

  @override
  String toString() => 'LocationFailure: $message';
}

/// One coordinate, used only for matching.
///
/// NFR-04: a student's position is never broadcast. It goes into their own
/// private intent document, the coalition engine uses it to test radius
/// overlap server-side, and a precise location only ever surfaces once a
/// coalition is active and every member verified. Nothing in the app displays
/// another student's position at any point.
class LocationService {
  const LocationService();

  Future<({double lat, double lng})> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'Layanan lokasi mati. Nyalakan dulu lewat pengaturan.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Izin lokasi ditolak permanen. Aktifkan lewat pengaturan aplikasi.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        'CoStudy perlu lokasimu untuk mencari titik temu yang masuk akal.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        // Matching works at a radius of hundreds of metres, so metre-accurate
        // GPS would cost battery and time for precision nobody uses.
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    );

    return (lat: position.latitude, lng: position.longitude);
  }
}
