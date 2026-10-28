import 'package:flutter/material.dart';

import '../models/strings.dart';

/// Selection and persistence stay outside the form; no contact access or save
/// occurs until the corresponding explicit action.
class SosContactDialog extends StatefulWidget {
  final String initialNumber;
  final Future<String?> Function() pickNumber;
  final Future<bool> Function(String) saveNumber;
  final bool Function()? canInteract;
  const SosContactDialog({
    super.key,
    required this.initialNumber,
    required this.pickNumber,
    required this.saveNumber,
    this.canInteract,
  });

  @override
  State<SosContactDialog> createState() => _SosContactDialogState();
}

class _SosContactDialogState extends State<SosContactDialog> {
  late final _number = TextEditingController(text: widget.initialNumber);
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;
  bool get _canInteract => mounted && (widget.canInteract?.call() ?? true);

  @override
  void dispose() {
    _number.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (!_canInteract || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final number = await widget.pickNumber();
      if (!_canInteract) return;
      if (number != null) {
        if (number.trim().isEmpty) {
          _error = AppStrings.get('sos_contact_no_number');
        } else {
          _number.text = number;
        }
      }
    } catch (_) {
      if (mounted) _error = AppStrings.get('sos_contact_pick_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_canInteract || _busy) return;
    if (_number.text.replaceAll(RegExp(r'\D'), '').length < 7) {
      setState(() => _error = AppStrings.get('sos_invalid_number'));
      _focus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.saveNumber(_number.text);
      if (!mounted || !_canInteract) return;
      if (saved) {
        Navigator.of(context).pop(true);
      } else {
        _error = AppStrings.get('sos_contact_save_failed');
      }
    } catch (_) {
      if (mounted) _error = AppStrings.get('sos_contact_save_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    localeForSubtree: Locale(AppStrings.current.name),
    child: AlertDialog(
      scrollable: true,
      title: Text(AppStrings.get('sos_settings')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Text(AppStrings.get('sos_contact_number'))),
          const SizedBox(height: 8),
          Semantics(
            label: AppStrings.get('sos_contact_number'),
            hint: '+7 XXX XXX XX XX',
            child: TextField(
              controller: _number,
              focusNode: _focus,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hint: ExcludeSemantics(child: Text('+7 XXX XXX XX XX')),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.contact_phone),
            label: Text(AppStrings.get('sos_contact_pick')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_error!)),
          ],
          if (_busy)
            Semantics(
              liveRegion: true,
              child: Text(AppStrings.get('sos_contact_wait')),
            ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.get('cancel')),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : _save,
          child: Text(AppStrings.get('save')),
        ),
      ],
    ),
  );
}
