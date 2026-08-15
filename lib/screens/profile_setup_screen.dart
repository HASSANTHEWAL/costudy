import 'package:flutter/material.dart';

import '../profile/student_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/mascot.dart';

/// Screen 4 — Profile Setup, first run only.
///
/// A gate, not a form the student can skip. `jurusan` is the only thing ever
/// shown about them to another member of a session, so a session cannot be
/// rendered until it exists — a member with no faculty would appear as a blank
/// in someone else's card.
///
/// Deliberately not reachable from the Profil tab. It runs once, and the
/// answers are not the kind a student needs to revise mid-term.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.uid,
    required this.emailKampus,
    this.repository,
    this.onCompleted,
  });

  final String uid;
  final String? emailKampus;

  /// Injectable for tests; the app constructs the real one.
  final ProfileRepository? repository;

  /// Called after a successful save. The auth gate swaps in the shell.
  final VoidCallback? onCompleted;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final ProfileRepository _repository =
      widget.repository ?? ProfileRepository();

  final _nameController = TextEditingController();
  String? _jurusan;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty && _jurusan != null && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _repository.saveSetup(
        uid: widget.uid,
        nama: _nameController.text.trim(),
        jurusan: _jurusan!,
        emailKampus: widget.emailKampus,
      );
      widget.onCompleted?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Belum tersimpan. Periksa koneksimu lalu coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No back button and no pop: this screen cannot be dismissed without
    // completing it, so the system back gesture must not escape it either.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: CoStudyMascot(width: 150)),
                const SizedBox(height: 24),
                Text(
                  'Kenalan dulu, yuk',
                  style: display(
                    size: 24,
                    weight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Dipakai sekali saja. Teman sesimu hanya melihat jurusanmu, '
                  'tidak pernah namamu.',
                  style: display(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.grayMid,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  'NAMA LENGKAP',
                  style: display(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.grayMid,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  style: display(size: 15, weight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Nama sesuai KTM',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'JURUSAN',
                  style: display(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.grayMid,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _jurusan,
                  isExpanded: true,
                  hint: Text(
                    'Pilih jurusanmu',
                    style: display(
                      size: 15,
                      weight: FontWeight.w500,
                      color: AppColors.grayMid,
                    ),
                  ),
                  icon: const Icon(Icons.expand_more, color: AppColors.grayMid),
                  style: display(size: 15, weight: FontWeight.w600),
                  items: [
                    for (final option in kJurusanOptions)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _jurusan = value),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: display(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.red,
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Simpan & mulai'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
