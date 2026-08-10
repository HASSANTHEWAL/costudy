import 'package:flutter/material.dart';

import '../intent/intent_repository.dart';
import '../intent/location_service.dart';
import '../intent/study_intent.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// What a successful registration hands back to the caller, so Home and the
/// Waiting screen can show the student their own window without re-reading
/// Firestore.
class RegisteredIntentSummary {
  const RegisteredIntentSummary({
    required this.intentId,
    required this.startTime,
    required this.endTime,
    required this.radiusM,
    required this.atmosphere,
  });

  final String intentId;
  final DateTime startTime;
  final DateTime endTime;
  final int radiusM;
  final Atmosphere atmosphere;

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String formatRadius(int metres) =>
      metres >= 1000 ? '${metres ~/ 1000}km' : '${metres}m';

  static String atmosphereEmoji(Atmosphere a) => switch (a) {
        Atmosphere.quiet => '🔇',
        Atmosphere.discussion => '💬',
        Atmosphere.any => '✨',
      };

  /// The three chips shown on Home and Waiting.
  List<String> get tags => [
        '⏰ ${_hhmm(startTime)}–${_hhmm(endTime)}',
        '📍 Dalam ${formatRadius(radiusM)}',
        '${atmosphereEmoji(atmosphere)} ${atmosphere.label}',
      ];
}

/// Screen 6 — Daftarkan Niat (FR-02).
///
/// The core input screen. Collects a time range, a travel radius and an
/// atmosphere, and stores them PRIVATELY. Deliberately nothing about other
/// students: no count of who else is waiting, no suggestions, no map of
/// people. Any of those would reintroduce the first-initiative risk the
/// assurance contract exists to remove (B.3), which is also why
/// firestore.rules forbids reading anyone else's intents at all.
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
      final id = await _repository.register(
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
      Navigator.of(context).pop(
        RegisteredIntentSummary(
          intentId: id,
          startTime: _startAt!,
          endTime: _endAt!,
          radiusM: _radiusM,
          atmosphere: _atmosphere,
        ),
      );
    } on IntentFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
              child: ScreenHeader(
                title: 'Daftarkan Niat',
                subtitle: 'Kapan ingin belajar?',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel(
                      color: AppColors.blue,
                      label: 'Jendela waktu',
                    ),
                    _TimeCard(
                      start: _start,
                      end: _end,
                      onPickStart: () => _pickTime(isStart: true),
                      onPickEnd: () => _pickTime(isStart: false),
                    ),
                    const SizedBox(height: 22),

                    const SectionLabel(
                      color: AppColors.lavender,
                      label: 'Radius pencarian',
                    ),
                    _RadiusCard(
                      stops: _radiusStops,
                      value: _radiusM,
                      onChanged: (v) => setState(() => _radiusM = v),
                    ),
                    const SizedBox(height: 10),
                    _LocationButton(
                      hasFix: _lat != null && _lng != null,
                      busy: _locating,
                      onTap: _useCurrentLocation,
                    ),
                    const SizedBox(height: 22),

                    const SectionLabel(
                      color: AppColors.green,
                      label: 'Suasana belajar',
                    ),
                    for (final option in Atmosphere.values) ...[
                      _AtmosphereCard(
                        atmosphere: option,
                        selected: _atmosphere == option,
                        onTap: () => setState(() => _atmosphere = option),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 12),

                    const PrivacyNote(
                      text: 'Niatmu tidak terlihat oleh siapa pun sampai '
                          'sesi terbentuk.',
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: AppColors.red),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _error!,
                              style: display(
                                size: 13,
                                weight: FontWeight.w500,
                                color: AppColors.red,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
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
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.podcasts_rounded, size: 18),
                                SizedBox(width: 10),
                                Text('Daftarkan niat'),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final TimeOfDay? start;
  final TimeOfDay? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _TimeRow(
            icon: Icons.schedule,
            iconColor: AppColors.blue,
            label: 'Mulai',
            value: start,
            onTap: onPickStart,
            divider: true,
          ),
          _TimeRow(
            icon: Icons.schedule,
            iconColor: AppColors.lavender,
            label: 'Selesai',
            value: end,
            onTap: onPickEnd,
            divider: false,
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    required this.divider,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? '--:--'
        : '${value!.hour.toString().padLeft(2, '0')}:'
            '${value!.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          border: divider
              ? const Border(bottom: BorderSide(color: AppColors.hairline))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: display(
                  size: 14,
                  weight: FontWeight.w500,
                  color: AppColors.grayMid,
                ),
              ),
            ),
            Text(
              text,
              // Mono keeps the two rows' digits in the same columns as they
              // change — the design reserves it for times exactly like this.
              style: mono(
                size: 18,
                weight: FontWeight.w500,
                color: value == null ? AppColors.grayMid : AppColors.charcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three discrete stops, not a continuous slider.
///
/// The prototype draws them as dots on a track because 500m / 1km / 2km are
/// the only meaningful choices — a free slider would invite 1.3km, which is
/// false precision for a constraint the engine tests against a centroid.
class _RadiusCard extends StatelessWidget {
  const _RadiusCard({
    required this.stops,
    required this.value,
    required this.onChanged,
  });

  final List<int> stops;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = stops.indexOf(value).clamp(0, stops.length - 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: cardDecoration(),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppColors.blue,
              inactiveTrackColor: AppColors.gray,
              thumbColor: AppColors.blue,
              overlayColor: AppColors.blueLight,
              activeTickMarkColor: AppColors.blue,
              inactiveTickMarkColor: AppColors.gray,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: index.toDouble(),
              min: 0,
              max: (stops.length - 1).toDouble(),
              divisions: stops.length - 1,
              onChanged: (raw) => onChanged(stops[raw.round()]),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < stops.length; i++)
                Text(
                  RegisteredIntentSummary.formatRadius(stops[i]),
                  style: display(
                    size: 12,
                    weight: i == index ? FontWeight.w700 : FontWeight.w500,
                    color: i == index ? AppColors.blue : AppColors.grayMid,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationButton extends StatelessWidget {
  const _LocationButton({
    required this.hasFix,
    required this.busy,
    required this.onTap,
  });

  final bool hasFix;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasFix ? AppColors.greenLight : AppColors.blueLight,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.blue,
                ),
              )
            else
              Icon(
                hasFix ? Icons.check_circle_outline : Icons.place_outlined,
                size: 15,
                color: hasFix ? AppColors.greenDeep : AppColors.blue,
              ),
            const SizedBox(width: 7),
            // Flexible: the confirmed-state label is the longest string on
            // this screen and overflows a narrow phone without it.
            Flexible(
              child: Text(
                busy
                    ? 'Mencari lokasi…'
                    : hasFix
                        ? 'Lokasi tersimpan · ketuk untuk perbarui'
                        : 'Gunakan lokasi saya sekarang',
                overflow: TextOverflow.ellipsis,
                style: display(
                  size: 13,
                  weight: FontWeight.w700,
                  color: hasFix ? AppColors.greenDeep : AppColors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: kMinTouchTarget + 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueLight : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.gray,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              RegisteredIntentSummary.atmosphereEmoji(atmosphere),
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    atmosphere.label,
                    style: display(
                      size: 15,
                      weight: FontWeight.w700,
                      color: selected ? AppColors.blue : AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    atmosphere.description,
                    style: display(
                      size: 13,
                      weight: FontWeight.w500,
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
