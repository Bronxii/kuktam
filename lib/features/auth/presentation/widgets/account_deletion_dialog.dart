import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/repositories/account_deletion_repository.dart';

class AccountDeletionDialog extends StatefulWidget {
  const AccountDeletionDialog({super.key, required this.repository});
  final AccountDeletionRepository repository;

  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  final _password = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    if (widget.repository.requiresPassword && _password.text.isEmpty) {
      setState(() => _error = 'Add meg a jelenlegi jelszavadat.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.deleteCurrentAccount(password: _password.text);
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error is GoogleSignInException &&
            error.code == GoogleSignInExceptionCode.canceled) {
          _error =
              'A Google-hitelesítést megszakítottad. A törlés nem indult el.';
        } else if (error is FirebaseAuthException &&
            [
              'wrong-password',
              'invalid-credential',
              'user-mismatch',
              'invalid-login-credentials',
            ].contains(error.code)) {
          _error =
              'Az újrahitelesítés nem sikerült. Ellenőrizd a jelszót vagy a kiválasztott fiókot, és próbáld újra.';
        } else {
          _error =
              'A fióktörlés nem fejeződött be. Egyes adatok már törlődhettek. '
              'A fiókod törléséhez próbáld újra a műveletet.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Fiók törlése'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_confirmed)
                const Text(
                  'Biztosan törölni szeretnéd a fiókodat?\n\n'
                  'A fiókod, a receptjeid, a bevásárlólistád és minden kapcsolódó '
                  'személyes Kuktám-adat véglegesen törlődik.\n\n'
                  'Ez a művelet nem vonható vissza.',
                )
              else if (widget.repository.requiresPassword)
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Jelenlegi jelszó',
                    suffixIcon: IconButton(
                      tooltip: _visible
                          ? 'Jelszó elrejtése'
                          : 'Jelszó megjelenítése',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _visible = !_visible),
                      icon: Icon(
                        _visible ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                )
              else
                const Text(
                  'A végleges törléshez erősítsd meg a személyazonosságodat a Google-fiókoddal.',
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Fiók törlése folyamatban…'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: _busy
                ? null
                : () {
                    if (!_confirmed) {
                      setState(() => _confirmed = true);
                    } else {
                      _delete();
                    }
                  },
            child: const Text('Fiók törlése'),
          ),
        ],
      ),
    );
  }
}
