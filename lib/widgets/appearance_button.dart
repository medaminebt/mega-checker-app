import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../appearance.dart';

/// Header / sign-in corner button: Match system · Light · Dark.
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Appearance.mode,
      builder: (context, mode, _) => PopupMenuButton<ThemeMode>(
        tooltip: 'Appearance: ${Appearance.label(mode)}',
        icon: Icon(Appearance.icon(mode), size: size),
        initialValue: mode,
        position: PopupMenuPosition.under,
        onSelected: Appearance.set,
        itemBuilder: (_) => [
          for (final m in const [
            ThemeMode.system,
            ThemeMode.light,
            ThemeMode.dark,
          ])
            PopupMenuItem(
              value: m,
              child: Row(
                children: [
                  Icon(
                    Appearance.icon(m),
                    size: 18,
                    color: m == mode
                        ? AppTheme.megaRed
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(Appearance.label(m), style: AppTheme.body),
                  ),
                  if (m == mode)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppTheme.megaBlueSoft,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
