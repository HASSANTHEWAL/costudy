import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';

/// Turns a meeting point into something a student can read.
///
/// HARD RULE: raw coordinates are never shown to a user, at any point. A
/// lat/lng pair on screen is both useless to a person walking to a library and
/// a precision this product deliberately does not trade in — NFR-04 keeps
/// positions for matching, not for display.
///
/// Every failure path therefore returns a human phrase, never a number. The
/// fallback is intentionally vague rather than apologetic: "Sekitar kampus
/// UII" is true, actionable, and does not read as an error.
class PlaceNameResolver {
  const PlaceNameResolver();

  static const String fallback = 'Sekitar kampus UII';

  Future<String> describe(double lat, double lng) async {
    try {
      // geocoding 5.x moved this off a top-level function and onto Geocoding,
      // with an Indonesian locale so the result reads in the app's language.
      final placemarks = await Geocoding(locale: const Locale('id', 'ID'))
          .placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return fallback;

      final place = placemarks.first;

      // Most specific first. `name` is often the building or POI, which is
      // exactly what a student needs; the rest degrade gracefully toward a
      // district name.
      for (final candidate in [
        place.name,
        place.street,
        place.subLocality,
        place.locality,
      ]) {
        final value = candidate?.trim() ?? '';
        if (value.isEmpty) continue;
        // Reverse geocoders return the coordinate itself as `name` when they
        // have nothing better. Passing that through would print numbers at a
        // student, so it is treated as a failure.
        if (_looksLikeCoordinates(value)) continue;
        return value;
      }
      return fallback;
    } catch (_) {
      // Offline, no platform geocoder, rate limited — all the same to a
      // student standing in a corridor.
      return fallback;
    }
  }

  static bool _looksLikeCoordinates(String value) {
    return RegExp(r'^-?\d+\.\d+\s*,\s*-?\d+\.\d+$').hasMatch(value) ||
        RegExp(r'^-?\d+\.\d{4,}$').hasMatch(value);
  }
}
