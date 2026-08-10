import 'package:flutter/material.dart';

import '../intent/intent_repository.dart';
import '../intent/location_service.dart';
import '../intent/study_intent.dart';
import '../theme/app_theme.dart';

/// Screen 6 of the design — register an availability window (FR-02).
///
/// The core input screen. Its whole job is to collect a time range, a travel
/// radius and an atmosphere, and store them PRIVATELY. There is deliberately
/// nothing here about other students: no count of who else is waiting, no
/// suggestions, no map of people. Showing any of that would reintroduce the
/// first-initiative risk the assurance contract exists to remove (B.3), and it
/// is why firestore.rules forbids reading anyone else's intents at all.
class RegisterIntentScreen extends StatefulWidget {
  const RegisterIntentScreen({
    super.key,
    required this.userId,
    this.repository,
    this.locationService,
  });

  final String userId;

  /// Injectable so widget tests can drive the form without Firebase or a GPS
  /// fix. Null in the app, where the real implementations are constructed.
  final IntentRepository? repository;
  final LocationService? locationService;

  @override
  State<RegisterIntentScreen> createState() => _RegisterIntentScreenState();
}

class _RegisterIntentScreenState extends State<RegisterIntentScreen> {
  static const List<int> _radiusStops = [500, 1000, 2000];

  late final IntentRepository _repository =
      widget.repository ?? IntentRepository();
  late final LocationService _location =
      widget.locationService ?? const LocationService();

  TimeOfDay? _start;
  TimeOfDay? _end;
  int _radiusM = 1000;
  Atmosphere _atmosphere = Atmosphere.any;

  double? _lat;
  double? _lng;

  bool _locating = false;
  bool _saving = false;
  String? _error;

  /// Combine a wall-clock time with today's date.
  ///
  /// An end time earlier in the day than the start is read as "tonight into
  /// tomorrow" rather than rejected — 22:00 to 00:30 is an ordinary library
  /// session, and refusing it would be a bug the student cannot work around.
  DateTime? _resolve(TimeOfDay? time, {DateTime? after}) {
    if (time == null) return null;
    final now = DateTime.now();
    var resolved =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (after != null && !resolved.isAfter(after)) {
      resolved = resolved.add(const Duration(days: 1));
    }
    return resolved;
  }

  DateTime? get _startAt => _resolve(_start);
  DateTime? get _endAt => _resolve(_end, after: _startAt);

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isStart ? _start : _end) ??
          TimeOfDay.fromDateTime(
            DateTime.now().add(Duration(hours: isStart ? 1 : 3)),
          ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      final position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _lat = position.lat;
        _lng = position.lng;
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;

    final validation = IntentValidation.check(
      startTime: _startAt,
      endTime: _endAt,
      lat: _lat,
      lng: _lng,
      radiusM: _radiusM,
    );
    if (!validation.isValid) {
      setState(() => _error = validation.message);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _repository.register(
        StudyIntent(
          userId: widget.userId,
          startTime: _startAt!,
          endTime: _endAt!,
          lat: _lat!,
          lng: _lng!,
          radiusM: _radiusM,
          atmosphere: _atmosphere,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on IntentFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
        title: const Text('Saya ingin belajar'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kapan?', style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Mulai',
                      value: _start,
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: 'Selesai',
                      value: _end,
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Text('Seberapa jauh kamu mau jalan?',
                  style: textTheme.headlineMedium),
              const SizedBox(height: 8),
              _RadiusSlider(
                stops: _radiusStops,
                value: _radiusM,
                onChanged: (value) => setState(() => _radiusM = value),
              ),
              const SizedBox(height: 12),
              _LocationRow(
                lat: _lat,
                lng: _lng,
                busy: _locating,
                onPressed: _useCurrentLocation,
              ),
              const SizedBox(height: 32),

              Text('Suasana belajar', style: textTheme.headlineMedium),
              const SizedBox(height: 12),
              for (final option in Atmosphere.values) ...[
                _AtmosphereCard(
                  atmosphere: option,
                  selected: _atmosphere == option,
                  onTap: () => setState(() => _atmosphere = option),
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 12),
              const _PrivacyReassurance(),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.red),
                ),
              ],

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Daftarkan niat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? '--:--'
        : '${value!.hour.toString().padLeft(2, '0')}:'
            '${value!.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.gray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.grayMid),
            ),
            const SizedBox(height: 4),
            Text(
              display,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                // Tabular figures so the two fields stay aligned as digits
                // change — the design reserves mono for times exactly here.
                fontFeatures: const [FontFeature.tabularFigures()],
                color: value == null ? AppColors.grayMid : AppColors.charcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({
    required this.stops,
    required this.value,
    required this.onChanged,
  });

  final List<int> stops;
  final int value;
  final ValueChanged<int> onChanged;

  static String _format(int metres) =>
      metres >= 1000 ? '${metres ~/ 1000} km' : '$metres m';

  @override
  Widget build(BuildContext context) {
    final index = stops.indexOf(value).clamp(0, stops.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _format(value),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.blue,
          ),
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: (stops.length - 1).toDouble(),
          divisions: stops.length - 1,
          label: _format(value),
          activeColor: AppColors.blue,
          onChanged: (raw) => onChanged(stops[raw.round()]),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final stop in stops)
              Text(
                _format(stop),
                style: const TextStyle(fontSize: 13, color: AppColors.grayMid),
              ),
          ],
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.lat,
    required this.lng,
    required this.busy,
    required this.onPressed,
  });

  final double? lat;
  final double? lng;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasFix = lat != null && lng != null;

    return Row(
      children: [
        Icon(
          hasFix ? Icons.check_circle_outline : Icons.my_location,
          size: 20,
          color: hasFix ? AppColors.green : AppColors.blue,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: busy
              ? const Text('Mencari lokasi…',
                  style: TextStyle(color: AppColors.charcoalMid))
              : TextButton(
                  onPressed: onPressed,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, kMinTouchTarget),
                  ),
                  child: Text(
                    hasFix
                        ? 'Lokasi tersimpan · ketuk untuk perbarui'
                        : 'Gunakan lokasi saya sekarang',
                  ),
                ),
        ),
      ],
    );
  }
}

class _AtmosphereCard extends StatelessWidget {
  const _AtmosphereCard({
    required this.atmosphere,
    required this.selected,
    required this.onTap,
  });

  final Atmosphere atmosphere;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: kMinTouchTarget + 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueLight : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.gray,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    atmosphere.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? AppColors.blue : AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    atmosphere.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.charcoalMid,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.blue, size: 22),
          ],
        ),
      ),
    );
  }
}

/// The line that makes the assurance contract legible to the student.
///
/// Quiet by design but never omitted: the entire reason it is safe to register
/// an intent is that nobody sees it, and a student who does not know that is
/// still carrying the social risk the product removes.
class _PrivacyReassurance extends StatelessWidget {
  const _PrivacyReassurance();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: AppColors.charcoalMid),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Niatmu tidak terlihat oleh siapa pun sampai sesi terbentuk.',
              style: TextStyle(fontSize: 14, color: AppColors.charcoalMid),
            ),
          ),
        ],
      ),
    );
  }
}
