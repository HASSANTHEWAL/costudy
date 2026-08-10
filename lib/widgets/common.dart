import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Section label: a small coloured dot and an uppercase tracked caption.
/// The prototype's `SL` component — used to head each group on the intent form.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: display(
              size: 11,
              weight: FontWeight.w700,
              color: AppColors.grayMid,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen heading with an optional round back button, as used on every
/// secondary screen in the prototype.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          _RoundIconButton(icon: Icons.chevron_left, onTap: onBack!),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: display(
                  size: 20,
                  weight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: display(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.grayMid,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.button),
          border: Border.all(color: AppColors.gray, width: 1.5),
        ),
        child: Icon(icon, size: 24, color: AppColors.charcoal),
      ),
    );
  }
}

/// Square avatar with initials — the prototype uses a rounded square, not a
/// circle, and never a photo. There are no profile pictures in CoStudy: the
/// app deliberately does not look like something you browse people on.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.source, this.size = 44});

  /// Email or name to derive initials from.
  final String source;
  final double size;

  String get _initials {
    final local = source.split('@').first;
    final parts = local
        .split(RegExp(r'[.\-_ ]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        _initials,
        style: display(
          size: size * 0.32,
          weight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// Small rounded chip used for the intent summary tags ("⏰ 10:00–13:00").
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    this.background,
    this.border,
    this.foreground,
  });

  final String label;
  final Color? background;
  final Color? border;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? AppColors.blueLight,
        borderRadius: BorderRadius.circular(8),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        style: display(
          size: 12,
          weight: FontWeight.w600,
          color: foreground ?? AppColors.charcoalMid,
        ),
      ),
    );
  }
}

/// The privacy reassurance panel. Quiet but never omitted — the reason it is
/// safe to register an intent is that nobody sees it, and a student who does
/// not know that is still carrying the social risk the product removes.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.lavenderLight,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.lavender),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 16, color: AppColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: display(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.blue,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A styled empty state — never a blank page and never a shrug.
///
/// The design brief is explicit that the failure mode of comparable products
/// is an empty board, and that History's empty state should be inviting
/// ("Sesi pertamamu akan muncul di sini"). Note there is deliberately no
/// "no results" variant anywhere: unmatched intents expire silently, so the
/// app never has an absence to report.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.accent = AppColors.blue,
    this.accentBackground = AppColors.blueLight,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  final Color accentBackground;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: accentBackground,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, size: 38, color: accent),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: display(size: 17, weight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: display(
                size: 14,
                weight: FontWeight.w500,
                color: AppColors.grayMid,
                height: 1.55,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
