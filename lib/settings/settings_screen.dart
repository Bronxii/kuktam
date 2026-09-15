import 'package:flutter/material.dart';

import '../features/auth/data/repositories/auth_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/privacy_screen.dart';
import '../features/auth/data/repositories/account_deletion_repository.dart';
import '../features/auth/presentation/widgets/account_deletion_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.authRepository, this.deletionRepository});

  final AuthRepository? authRepository;
  final AccountDeletionRepository? deletionRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AuthRepository _authRepository =
      widget.authRepository ?? AuthRepository();

  String _appVersion = '';
  bool _deletionDialogOpen = false;
  bool _isSigningOut = false;

  Future<void> _deleteAccount() async {
    if (_deletionDialogOpen) return;
    _deletionDialogOpen = true;
    final navigator = Navigator.of(context);
    try {
      final repository = widget.deletionRepository ?? AccountDeletionRepository();
      final deleted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AccountDeletionDialog(
          repository: repository,
        ),
      );
      if (deleted == true && navigator.mounted) {
        navigator.popUntil((route) => route.isFirst);
      }
    } finally {
      _deletionDialogOpen = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();

    if (!mounted) {
      return;
    }

    setState(() {
      _appVersion =
      'v${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _sendFeedback() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: 'kuktam.support@gmail.com',
      query: _encodeQueryParameters({
        'subject': 'Kuktám – visszajelzés',
        'body': 'Szia!\n\n'
            'Az alábbi visszajelzést szeretném küldeni a Kuktám alkalmazással kapcsolatban:\n\n',
      }),
    );

    final launched = await launchUrl(emailUri);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nem sikerült megnyitni a levelezőalkalmazást.',
          ),
        ),
      );
    }
  }

  String? _encodeQueryParameters(Map<String, String> parameters) {
    return parameters.entries
        .map(
          (entry) =>
      '${Uri.encodeComponent(entry.key)}='
          '${Uri.encodeComponent(entry.value)}',
    )
        .join('&');
  }

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
              onTap: () async {
                final emailController = TextEditingController();
                final passwordController = TextEditingController();
                bool isPasswordVisible = false;

                String? errorText;
                bool isLoading = false;
                bool? emailChanged;
                try {
                emailChanged = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) {

                    return StatefulBuilder(
                      builder: (context, setDialogState) {
                        Future<void> submitEmailChange() async {
                          if (isLoading) return;
                          final newEmail = emailController.text.trim();
                          final password = passwordController.text;

                          if (newEmail.isEmpty || password.isEmpty) {
                            setDialogState(() {
                              errorText = 'Minden mezőt tölts ki!';
                            });
                            return;
                          }

                          final emailRegex = RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          );

                          if (!emailRegex.hasMatch(newEmail)) {
                            setDialogState(() {
                              errorText = 'Adj meg egy érvényes e-mail címet!';
                            });
                            return;
                          }

                          if (newEmail.toLowerCase() == email.toLowerCase()) {
                            setDialogState(() {
                              errorText =
                              'Az új e-mail cím nem lehet azonos a jelenlegivel.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            errorText = null;
                          });

                          try {
                            await _authRepository.changeEmail(
                              currentPassword: password,
                              newEmail: newEmail,
                            );

                            if (!dialogContext.mounted) {
                              return;
                            }

                            Navigator.of(dialogContext).pop(true);
                          } catch (_) {
                            if (!dialogContext.mounted) {
                              return;
                            }

                            setDialogState(() {
                              isLoading = false;
                              errorText =
                              'Hibás jelszó vagy sikertelen e-mail módosítás.';
                            });
                          }
                        }

                        return PopScope(
                          canPop: !isLoading,
                          child: AlertDialog(
                          title: const Text('E-mail cím módosítása'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: emailController,
                                  enabled: !isLoading,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Új e-mail cím',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: passwordController,
                                  enabled: !isLoading,
                                  obscureText: !isPasswordVisible,
                                  decoration: InputDecoration(
                                    labelText: 'Jelenlegi jelszó',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: isPasswordVisible
                                          ? 'Jelszó elrejtése'
                                          : 'Jelszó megjelenítése',
                                      icon: Icon(
                                        isPasswordVisible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: isLoading ? null : () {
                                        setDialogState(() {
                                          isPasswordVisible = !isPasswordVisible;
                                        });
                                      },
                                    ),
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
                              isLoading ? null : submitEmailChange,
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
                          ),
                        );
                      },
                    );
                  },
                );


                } finally {
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  emailController.dispose();
                  passwordController.dispose();
                }
                if (emailChanged == true && context.mounted) {
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (successContext) => PopScope(
                      canPop: false,
                      child: AlertDialog(
                        title: const Text('E-mail-cím módosítása'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Megerősítő e-mailt küldtünk az új e-mail-címre.\n\n'
                            'A módosítás véglegesítéséhez nyisd meg a levelet, '
                            'és erősítsd meg az új címet.\n\n'
                            'Ha nem találod, ellenőrizd a Spam mappát is.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(successContext).pop(),
                            child: const Text('Rendben'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
            ),

    ListTile(
    leading: const Icon(Icons.lock_outline),
    title: const Text('Jelszó módosítása'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
    final currentPasswordController = TextEditingController();
    bool isCurrentPasswordVisible = false;
    final newPasswordController = TextEditingController();
    bool isNewPasswordVisible = false;
    final confirmPasswordController = TextEditingController();
    bool isConfirmPasswordVisible = false;

    String? errorText;
    bool isLoading = false;
    bool? passwordChanged;
    try {
    passwordChanged = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {

    return StatefulBuilder(
    builder: (context, setDialogState) {
    Future<void> submitPasswordChange() async {
    if (isLoading) return;
    final currentPassword =
    currentPasswordController.text;
    final newPassword =
    newPasswordController.text;
    final confirmPassword =
    confirmPasswordController.text;

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

    return PopScope(
    canPop: !isLoading,
    child: AlertDialog(
    title: const Text('Jelszó módosítása'),
    content: SingleChildScrollView(
    child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
    TextField(
    controller: currentPasswordController,
    obscureText: !isCurrentPasswordVisible,
    enabled: !isLoading,
    decoration: InputDecoration(
    labelText: 'Jelenlegi jelszó',
    border: const OutlineInputBorder(),
    suffixIcon: IconButton(
      tooltip: isCurrentPasswordVisible
          ? 'Jelszó elrejtése'
          : 'Jelszó megjelenítése',
      icon: Icon(
        isCurrentPasswordVisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      onPressed: isLoading ? null : () {
        setDialogState(() {
          isCurrentPasswordVisible = !isCurrentPasswordVisible;
        });
      },
    ),
    ),
    ),
    const SizedBox(height: 16),
    TextField(
    controller: newPasswordController,
    obscureText: !isNewPasswordVisible,
    enabled: !isLoading,
    decoration: InputDecoration(
    labelText: 'Új jelszó',
    border: const OutlineInputBorder(),
    suffixIcon: IconButton(
      tooltip: isNewPasswordVisible
          ? 'Jelszó elrejtése'
          : 'Jelszó megjelenítése',
      icon: Icon(
        isNewPasswordVisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      onPressed: isLoading ? null : () {
        setDialogState(() {
          isNewPasswordVisible = !isNewPasswordVisible;
        });
      },
    ),
    ),
    ),
    const SizedBox(height: 16),
    TextField(
    controller: confirmPasswordController,
    obscureText: !isConfirmPasswordVisible,
    enabled: !isLoading,
    decoration: InputDecoration(
    labelText: 'Új jelszó ismét',
    border: const OutlineInputBorder(),
    suffixIcon: IconButton(
      tooltip: isConfirmPasswordVisible
          ? 'Jelszó elrejtése'
          : 'Jelszó megjelenítése',
      icon: Icon(
        isConfirmPasswordVisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      onPressed: isLoading ? null : () {
        setDialogState(() {
          isConfirmPasswordVisible = !isConfirmPasswordVisible;
        });
      },
    ),
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
    ),
    );
    },
    );
    },
    );


    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      currentPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
    }
    if (passwordChanged == true && context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (successContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Jelszó módosítva'),
            content: const SingleChildScrollView(
              child: Text('A jelszavad sikeresen megváltozott.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(successContext).pop(),
                child: const Text('Rendben'),
              ),
            ],
          ),
        ),
      );
    }
    },
    ),
          ],

          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
            title: Text('Fiók törlése', style: TextStyle(color: theme.colorScheme.error)),
            onTap: _deleteAccount,
          ),

          const Divider(height: 32),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Támogatás',
              style: theme.textTheme.titleSmall,
            ),
          ),

          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Kapcsolat és visszajelzés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    icon: const Icon(
                      Icons.feedback_outlined,
                      size: 40,
                    ),
                    title: const Text(
                      'Kapcsolat és visszajelzés',
                      textAlign: TextAlign.center,
                    ),
                    content: const Text(
                      'Kérdésed vagy ötleted van, esetleg hibát találtál?\n\n'
                          'Írd le minél pontosabban a tapasztalataidat. '
                          'Hibajelentés esetén lehetőség szerint azt is írd meg, '
                          'hogy milyen művelet közben jelentkezett a probléma.',
                      textAlign: TextAlign.center,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('Mégsem'),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _sendFeedback();
                        },
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('Visszajelzés küldése'),
                      ),
                    ],
                  );
                },
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Adatvédelem'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PrivacyScreen(),
                ),
              );
            },
          ),

          const Divider(height: 32),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Kijelentkezés'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              if (_isSigningOut) return;
              _isSigningOut = true;
              final navigator = Navigator.of(context);
              try {
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
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('A kijelentkezés sikertelen. Próbáld újra.'),
                  ));
                }
              } finally {
                _isSigningOut = false;
              }
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
                  _appVersion,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2026 Bronxii',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
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
