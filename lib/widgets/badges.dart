import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

/// Pill badge from the theme sheet (`.badge-red`, `.badge-blue`,
/// `.badge-grey`): tinted background, 1px border, uppercase bold label.
class MegaBadge extends StatelessWidget {
  const MegaBadge({
    super.key,
    required this.label,
    required this.text,
    required this.tint,
    this.icon,
    this.spinner = false,
  });

  final String label;

  /// Label colour.
  final Color text;

  /// Base colour for the tinted background and border.
  final Color tint;

  final IconData? icon;
  final bool spinner;

  factory MegaBadge.status(AccountStatus status) {
    switch (status) {
      case AccountStatus.ok:
        return MegaBadge(
          label: 'OK',
          text: AppTheme.successSoft,
          tint: AppTheme.success,
          icon: Icons.check_rounded,
        );
      case AccountStatus.failed:
        return MegaBadge(
          label: 'Failed',
          text: AppTheme.dangerSoft,
          tint: AppTheme.megaRed,
          icon: Icons.close_rounded,
        );
      case AccountStatus.running:
        return MegaBadge(
          label: 'Checking',
          text: AppTheme.megaBlueSoft,
          tint: AppTheme.megaBlue,
          spinner: true,
        );
      case AccountStatus.untested:
        return MegaBadge(
          label: 'Untested',
          text: AppTheme.textSecondary,
          tint: AppTheme.textMuted,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: text),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: text),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.font,
                color: text,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.65,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
