import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../format.dart';
import '../links.dart';
import '../models.dart';
import 'badges.dart';
import 'dialogs.dart';

/// Column geometry shared by the table header and the rows.
class AccountCols {
  static const double status = 112;
  static const int emailFlex = 3;
  static const int passwordFlex = 2;
  static const int keyFlex = 2;
  static const double login = 224;
  static const double bin = 122;
  static const int uploadFlex = 2;
  static const int notesFlex = 2;
  static const double actions = 124;
  static const double gap = 12;
  static const EdgeInsets padding = EdgeInsets.symmetric(horizontal: 18);

  /// Below this width the table scrolls sideways instead of squeezing.
  static const double minTableWidth = 1270;
}

/// One editable account row. Email / password / MEGA key / upload folder URL
/// are inline text fields, notes open a bigger editor; every edit is reported
/// through [onFieldChanged] (column name in snake_case) and saved to Supabase
/// by the page.
class AccountRow extends StatefulWidget {
  const AccountRow({
    super.key,
    required this.account,
    required this.index,
    required this.showSecrets,
    required this.enabled,
    required this.onFieldChanged,
    required this.onCheck,
    required this.onDelete,
    required this.onOpenUpload,
    this.checkTooltip = 'Check this account now',
    this.onFreeUp,
    this.freeUpTooltip = 'Free up space',
    this.onTogglePin,
  });

  final Account account;
  final int index;
  final bool showSecrets;

  /// False while a check run is in progress (rows are read-only then).
  final bool enabled;

  final void Function(String column, String value) onFieldChanged;

  /// Null when this build can't run checks (web).
  final VoidCallback? onCheck;
  final String checkTooltip;
  final VoidCallback onDelete;
  final void Function(Uri uri) onOpenUpload;

  /// Empty the Rubbish Bin / delete old versions. Null when this build can't
  /// run MEGAcmd (web).
  final void Function(FreeUpAction action)? onFreeUp;
  final String freeUpTooltip;

  /// Pin to / unpin from the top of the table.
  final VoidCallback? onTogglePin;

  @override
  State<AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<AccountRow> {
  late final _email = TextEditingController(text: widget.account.email);
  late final _pass = TextEditingController(text: widget.account.password);
  late final _key = TextEditingController(text: widget.account.megaKey);
  late final _upload = TextEditingController(
    text: widget.account.uploadFolderUrl,
  );
  final _emailF = FocusNode();
  final _passF = FocusNode();
  final _keyF = FocusNode();
  final _uploadF = FocusNode();
  bool _hover = false;

  @override
  void didUpdateWidget(covariant AccountRow old) {
    super.didUpdateWidget(old);
    // Sync values changed elsewhere (e.g. a re-import), but never clobber a
    // field the user is typing in.
    void sync(TextEditingController c, FocusNode f, String v) {
      if (!f.hasFocus && c.text != v) c.text = v;
    }

    sync(_email, _emailF, widget.account.email);
    sync(_pass, _passF, widget.account.password);
    sync(_key, _keyF, widget.account.megaKey);
    sync(_upload, _uploadF, widget.account.uploadFolderUrl);
  }

  @override
  void dispose() {
    for (final c in [_email, _pass, _key, _upload]) {
      c.dispose();
    }
    for (final f in [_emailF, _passF, _keyF, _uploadF]) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final Color bg;
    if (a.running) {
      bg = AppTheme.megaBlue.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = AppTheme.rowHover;
    } else {
      bg = widget.index.isOdd ? AppTheme.rowAlt : AppTheme.bgSurface;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Pinned rows get a red bar on the left; the padding gives its
        // width back so the columns stay lined up with the header.
        decoration: BoxDecoration(
          color: bg,
          border: a.pinned
              ? const Border(
                  left: BorderSide(color: AppTheme.megaRed, width: 3),
                )
              : null,
        ),
        padding: AccountCols.padding.copyWith(
          top: 9,
          bottom: 9,
          left: AccountCols.padding.left - (a.pinned ? 3 : 0),
        ),
        child: Row(
          children: [
            SizedBox(
              width: AccountCols.status,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(a),
              ),
            ),
            Expanded(
              flex: AccountCols.emailFlex,
              child: _field(
                controller: _email,
                focus: _emailF,
                column: 'email',
                hint: 'email@example.com',
                style: AppTheme.body.copyWith(fontSize: 13.5),
                onChanged: (v) => a.email = v,
              ),
            ),
            const SizedBox(width: AccountCols.gap),
            Expanded(
              flex: AccountCols.passwordFlex,
              child: _field(
                controller: _pass,
                focus: _passF,
                column: 'password',
                hint: 'password',
                obscure: !widget.showSecrets,
                style: AppTheme.mono,
                onChanged: (v) => a.password = v,
              ),
            ),
            const SizedBox(width: AccountCols.gap),
            Expanded(
              flex: AccountCols.keyFlex,
              child: _field(
                controller: _key,
                focus: _keyF,
                column: 'mega_key',
                hint: 'paste MEGA key…',
                obscure: !widget.showSecrets && _key.text.isNotEmpty,
                style: AppTheme.mono.copyWith(fontSize: 12),
                onChanged: (v) => a.megaKey = v,
              ),
            ),
            const SizedBox(width: AccountCols.gap),
            SizedBox(width: AccountCols.login, child: _loginCell(a)),
            const SizedBox(width: AccountCols.gap),
            SizedBox(width: AccountCols.bin, child: _binCell(a)),
            const SizedBox(width: AccountCols.gap),
            Expanded(flex: AccountCols.uploadFlex, child: _uploadCell(a)),
            const SizedBox(width: AccountCols.gap),
            Expanded(flex: AccountCols.notesFlex, child: _notesCell(a)),
            const SizedBox(width: AccountCols.gap),
            SizedBox(
              width: AccountCols.actions,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _iconAction(
                    tooltip: a.pinned ? 'Unpin' : 'Pin to top',
                    icon: a.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 17,
                    color: a.pinned ? AppTheme.megaRed : AppTheme.textMuted,
                    hoverColor: AppTheme.megaRed,
                    onPressed: widget.onTogglePin,
                  ),
                  const SizedBox(width: 6),
                  _iconAction(
                    tooltip: widget.checkTooltip,
                    icon: Icons.play_arrow_rounded,
                    color: AppTheme.megaBlueSoft,
                    tint: AppTheme.megaBlue,
                    onPressed: widget.enabled ? widget.onCheck : null,
                  ),
                  const SizedBox(width: 6),
                  _iconAction(
                    tooltip: 'Delete account',
                    icon: Icons.delete_outline_rounded,
                    color: AppTheme.textMuted,
                    hoverColor: AppTheme.dangerSoft,
                    onPressed: widget.enabled ? widget.onDelete : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required FocusNode focus,
    required String column,
    required String hint,
    required TextStyle style,
    required void Function(String) onChanged,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      enabled: widget.enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: style,
      decoration: InputDecoration(hintText: hint),
      onChanged: (v) {
        onChanged(v);
        widget.onFieldChanged(column, v);
        // MEGA key: toggles obscuring. Upload URL: enables the open button.
        if (column == 'mega_key' || column == 'upload_folder_url') {
          setState(() {});
        }
      },
    );
  }

  /// Upload folder link + a button that opens it in the browser. The button
  /// stays usable during a check run (only the text is read-only then).
  Widget _uploadCell(Account a) {
    final uri = Links.webUri(_upload.text);
    return Row(
      children: [
        Expanded(
          child: _field(
            controller: _upload,
            focus: _uploadF,
            column: 'upload_folder_url',
            hint: 'paste upload link…',
            keyboardType: TextInputType.url,
            style: AppTheme.caption.copyWith(
              color: AppTheme.textPrimary,
              fontSize: 12,
            ),
            onChanged: (v) => a.uploadFolderUrl = v.trim(),
          ),
        ),
        const SizedBox(width: 4),
        _iconAction(
          tooltip: uri == null
              ? 'Paste an upload folder link to open it here'
              : 'Open upload folder in the browser',
          icon: Icons.open_in_new_rounded,
          size: 16,
          color: AppTheme.megaBlueSoft,
          onPressed: uri == null ? null : () => widget.onOpenUpload(uri),
        ),
      ],
    );
  }

  /// One-line preview of the notes; click to edit them in a big dialog.
  Widget _notesCell(Account a) {
    final text = a.notes.trim();
    final preview = text.replaceAll(RegExp(r'\s*\n+\s*'), '  ·  ');
    final cell = Material(
      color: AppTheme.bgBase,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: AppTheme.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.enabled ? () => _editNotes(a) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text.isEmpty ? 'notes' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.isEmpty
                      ? TextStyle(
                          fontFamily: AppTheme.font,
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        )
                      : AppTheme.caption.copyWith(color: AppTheme.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_note_rounded,
                size: 17,
                color: widget.enabled
                    ? AppTheme.textMuted
                    : AppTheme.stateHover,
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Edit notes',
      child: Tooltip(
        message: text.isEmpty
            ? 'Add notes'
            : (text.length > 600 ? '${text.substring(0, 600)}…' : text),
        child: cell,
      ),
    );
  }

  Future<void> _editNotes(Account a) async {
    final onChanged = widget.onFieldChanged; // still valid if the row is gone
    final v = await showNotesDialog(context, email: a.email, notes: a.notes);
    if (v == null || v == a.notes) return;
    a.notes = v;
    onChanged('notes', v);
    if (mounted) setState(() {});
  }

  Widget _statusBadge(Account a) {
    final badge = MegaBadge.status(a.status);
    final checked = a.lastCheckedAt;
    String? tip;
    if (a.status == AccountStatus.failed) {
      tip =
          '${a.lastError ?? 'Login failed'}'
          '${checked != null ? '\nChecked ${Fmt.dateTime(checked)}' : ''}';
    } else if (a.status == AccountStatus.ok && checked != null) {
      tip = 'Checked ${Fmt.dateTime(checked)}';
    }
    return tip == null ? badge : Tooltip(message: tip, child: badge);
  }

  Widget _loginCell(Account a) {
    final last = a.lastLoginAt;
    final storage = a.storage;
    final loginText = Row(
      children: [
        Icon(
          Icons.schedule_rounded,
          size: 13,
          color: last == null ? AppTheme.textMuted : AppTheme.textSecondary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            last == null
                ? const TextSpan(text: 'Never')
                : TextSpan(
                    text: Fmt.dateTime(last),
                    children: [
                      TextSpan(
                        text: '  ·  ${Fmt.ago(last)}',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: last == null ? AppTheme.textMuted : AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );

    Widget storageLine;
    if (storage == null) {
      storageLine = Text(
        'Storage —',
        style: TextStyle(
          fontFamily: AppTheme.font,
          fontSize: 11.5,
          color: AppTheme.textMuted,
        ),
      );
    } else {
      final full = storage.fraction >= 0.9;
      storageLine = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${Fmt.bytes(storage.usedBytes)} / ${Fmt.bytes(storage.totalBytes)}'
            '  ·  ${(storage.fraction * 100).toStringAsFixed(storage.fraction < 0.1 ? 1 : 0)}%',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.font,
              fontSize: 11.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: storage.fraction,
              minHeight: 3,
              color: full ? AppTheme.megaRed : AppTheme.megaBlue,
              backgroundColor: AppTheme.stateHover,
            ),
          ),
        ],
      );
    }

    return Tooltip(
      message: last == null
          ? 'No successful login recorded yet'
          : 'Last successful login: ${Fmt.dateTime(last)}'
                '${storage == null ? '' : '\nStorage: ${Fmt.bytes(storage.usedBytes)} used of ${Fmt.bytes(storage.totalBytes)} · ${Fmt.bytes(storage.freeBytes)} free'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [loginText, const SizedBox(height: 5), storageLine],
      ),
    );
  }

  /// Rubbish Bin and old-versions sizes, plus a menu to free that space.
  Widget _binCell(Account a) {
    final bin = a.storageRubbishBytes;
    final versions = a.storageVersionsBytes;

    Widget line(IconData icon, String label, int? bytes) {
      final has = bytes != null && bytes > 0;
      return Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: has ? AppTheme.textSecondary : AppTheme.textMuted,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              bytes == null ? '$label —' : Fmt.bytes(bytes),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.font,
                fontSize: 11.5,
                fontWeight: has ? FontWeight.w500 : FontWeight.w400,
                color: has ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    String size(int? b) => b == null ? 'not measured yet' : Fmt.bytes(b);
    // Unknown (never measured) counts as "maybe something to free".
    bool worth(int? b) => b == null || b > 0;
    final onFreeUp = widget.onFreeUp;
    final canFree =
        onFreeUp != null && widget.enabled && (worth(bin) || worth(versions));

    final menu = PopupMenuButton<FreeUpAction>(
      enabled: canFree,
      tooltip: onFreeUp == null ? widget.freeUpTooltip : 'Free up space',
      padding: EdgeInsets.zero,
      iconSize: 17,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 380),
      icon: Icon(
        Icons.cleaning_services_rounded,
        color: canFree ? AppTheme.megaBlueSoft : AppTheme.disabledIcon,
      ),
      onSelected: (action) => onFreeUp?.call(action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: FreeUpAction.emptyRubbishBin,
          enabled: worth(bin),
          child: Row(
            children: [
              const Icon(Icons.delete_sweep_rounded, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Empty Rubbish Bin'
                  '${bin == null ? '' : ' (${Fmt.bytes(bin)})'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: FreeUpAction.deleteVersions,
          enabled: worth(versions),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Delete old file versions'
                  '${versions == null ? '' : ' (${Fmt.bytes(versions)})'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message:
                'Rubbish Bin: ${size(bin)}\nOld file versions: '
                '${size(versions)}\nBoth count towards the used storage.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                line(Icons.delete_sweep_rounded, 'Bin', bin),
                const SizedBox(height: 6),
                line(Icons.history_rounded, 'Versions', versions),
              ],
            ),
          ),
        ),
        SizedBox.square(dimension: 34, child: menu),
      ],
    );
  }

  Widget _iconAction({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    double size = 19,
    Color? tint,
    Color? hoverColor,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        fixedSize: const WidgetStatePropertyAll(Size.square(34)),
        minimumSize: const WidgetStatePropertyAll(Size.square(34)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStatePropertyAll(
          tint?.withValues(alpha: 0.16) ?? Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return AppTheme.disabledIcon;
          if (hoverColor != null && s.contains(WidgetState.hovered)) {
            return hoverColor;
          }
          return color;
        }),
        overlayColor: WidgetStatePropertyAll(AppTheme.stateHover),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
      ),
    );
  }
}
