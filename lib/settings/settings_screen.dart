import 'package:flutter/material.dart';

import '../features/auth/data/repositories/auth_repository.dart';

class SettingsScreen extends StatelessWidget {
  SettingsScreen({super.key});

  final AuthRepository _authRepository = AuthRepository();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _authRepository.currentUser;
    final email = user?.email ?? 'Nincs elérhető e-mail-cím';
    final isEmailPasswordUser =
        _authRepository.isEmailPasswordUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beállítások'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Fiók',
              style: theme.textTheme.titleSmall,
            ),
          ),

          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('E-mail cím'),
            subtitle: Text(email),
          ),
          if (isEmailPasswordUser) ...[
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: const Text('E-mail-cím módosítása'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
    ListTile(
    leading: const Icon(Icons.lock_outline),
    title: const Text('Jelszó módosítása'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
    final messenger = ScaffoldMessenger.of(context);

    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final passwordChanged = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
    String? errorText;
    bool isLoading = false;

    return StatefulBuilder(
    builder: (context, setDialogState) {
    Future<void> submitPasswordChange() async {
    final currentPassword =
    currentPasswordController.text.trim();
    final newPassword =
    newPasswordController.text.trim();
    final confirmPassword =
    confirmPasswordController.text.trim();

    if (currentPassword.isEmpty ||
    newPassword.isEmpty ||
    confirmPassword.isEmpty) {
    setDialogState(() {
    errorText = 'Minden mezőt tölts ki!';
    });
    return;
    }

    if (newPassword.length < 6) {
    setDialogState(() {
    errorText =
    'Az új jelszó legalább 6 karakter legyen.';
    });
    return;
    }

    if (newPassword != confirmPassword) {
    setDialogState(() {
    errorText = 'A két új jelszó nem egyezik.';
    });
    return;
    }

    if (newPassword == currentPassword) {
    setDialogState(() {
    errorText =
    'Az új jelszó nem lehet azonos a jelenlegivel.';
    });
    return;
    }

    setDialogState(() {
    isLoading = true;
    errorText = null;
    });

    try {
    await _authRepository.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
    );

    if (!dialogContext.mounted) {
    return;
    }

    Navigator.of(dialogContext).pop(true);
    } catch (error) {
    if (!dialogContext.mounted) {
    return;
    }

    setDialogState(() {
    isLoading = false;
    errorText =
    'A jelenlegi jelszó hibás, vagy nem sikerült a módosítás.';
    });
    }
    }

    return AlertDialog(
    title: const Text('Jelszó módosítása'),
    content: SingleChildScrollView(
    child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
    TextField(
    controller: currentPasswordController,
    obscureText: true,
    enabled: !isLoading,
    decoration: const InputDecoration(
    labelText: 'Jelenlegi jelszó',
    border: OutlineInputBorder(),
    ),
    ),
    const SizedBox(height: 16),
    TextField(
    controller: newPasswordController,
    obscureText: true,
    enabled: !isLoading,
    decoration: const InputDecoration(
    labelText: 'Új jelszó',
    border: OutlineInputBorder(),
    ),
    ),
    const SizedBox(height: 16),
    TextField(
    controller: confirmPasswordController,
    obscureText: true,
    enabled: !isLoading,
    decoration: const InputDecoration(
    labelText: 'Új jelszó ismét',
    border: OutlineInputBorder(),
    ),
    ),
    if (errorText != null) ...[
    const SizedBox(height: 16),
    Text(
    errorText!,
    style: TextStyle(
    color: Theme.of(context).colorScheme.error,
    ),
    ),
    ],
    ],
    ),
    ),
    actions: [
    TextButton(
    onPressed: isLoading
    ? null
        : () {
    Navigator.of(dialogContext).pop(false);
    },
    child: const Text('Mégsem'),
    ),
    FilledButton(
    onPressed:
    isLoading ? null : submitPasswordChange,
    child: isLoading
    ? const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(
    strokeWidth: 2,
    ),
    )
        : const Text('Mentés'),
    ),
    ],
    );
    },
    );
    },
    );

    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    if (passwordChanged == true) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A jelszó sikeresen módosult.'),
        ),
      );
    }
    },
    ),
          ],

          const Divider(height: 32),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Támogatás',
              style: theme.textTheme.titleSmall,
            ),
          ),

          const ListTile(
            leading: Icon(Icons.feedback_outlined),
            title: Text('Kapcsolat és visszajelzés'),
            trailing: Icon(Icons.chevron_right),
          ),

          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Adatvédelem'),
            trailing: Icon(Icons.chevron_right),
          ),

          const Divider(height: 32),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Kijelentkezés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final navigator = Navigator.of(context);

              final shouldSignOut = await showDialog<bool>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Text('Kijelentkezés'),
                    content: const Text(
                      'Biztosan ki szeretnél jelentkezni?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop(false);
                        },
                        child: const Text('Mégsem'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop(true);
                        },
                        child: const Text('Kijelentkezés'),
                      ),
                    ],
                  );
                },
              );

              if (shouldSignOut != true) {
                return;
              }

              await _authRepository.signOut();

              if (!context.mounted) {
                return;
              }

              navigator.popUntil((route) => route.isFirst);
            },
          ),

          const SizedBox(height: 32),

          Center(
            child: Column(
              children: [
                Text(
                  'Kuktám',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'v0.1.0',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

              const SizedBox(height: 24),
    ],
    ),
    );
  }
}