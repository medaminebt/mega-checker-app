import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'appearance_button.dart';
import 'mega_logo.dart';

/// `.field label` — small uppercase label above an input.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: AppTheme.label.copyWith(fontSize: 11.5),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// `.section-title` — heading with the red accent bar on its left.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.megaRed,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppTheme.h3.copyWith(fontSize: 17)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTheme.caption,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Full-window black canvas with a centred panel — used by the Supabase setup
/// and sign-in screens.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.width = 460,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBase,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          const Positioned(
            top: 10,
            right: 10,
            child: SafeArea(child: AppearanceButton()),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MegaLogo(size: 64, glow: true),
              const SizedBox(height: 22),
              Text(title, style: AppTheme.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: AppTheme.bodySecondary.copyWith(fontSize: 13.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              // Panel with a red accent strip on top (a rounded border
              // must be uniform, so the strip is drawn separately).
              Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 3, color: AppTheme.megaRed),
                    Padding(padding: const EdgeInsets.all(26), child: child),
                  ],
                ),
              ),
              if (footer != null) ...[const SizedBox(height: 18), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline error / warning box used inside forms.
class InlineMessage extends StatelessWidget {
  const InlineMessage(this.text, {super.key, this.error = true, this.trailing});

  final String text;
  final bool error;

  /// Optional button at the right edge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tint = error ? AppTheme.megaRed : AppTheme.megaBlue;
    final fg = error ? AppTheme.dangerSoft : AppTheme.megaBlueSoft;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 17,
            color: fg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: AppTheme.font,
                fontSize: 12.5,
                height: 1.45,
                color: fg,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
