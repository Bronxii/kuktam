import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import '../../data/repositories/auth_repository.dart';

import '../../../../core/theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isGoogleLoading = false;
  String _lastLoginEmail = '';
  final AuthRepository _authRepository = AuthRepository();
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      await _authRepository.signInWithGoogle();

      if (!mounted) {
        return;
      }

    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A Google-bejelentkezés sikertelen: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _showEmailSignInDialog() async {
    final emailController = TextEditingController();
    emailController.addListener(() {
      _lastLoginEmail = emailController.text;
    });
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isLoading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> signIn() async {
              final email = emailController.text.trim();
              final password = passwordController.text;

              if (email.isEmpty || password.isEmpty) {
                setDialogState(() {
                  errorMessage = 'Add meg az e-mail-címedet és a jelszavadat.';
                });
                return;
              }

              setDialogState(() {
                isLoading = true;
                errorMessage = null;
              });

              try {
                await _authRepository.signInWithEmail(
                  email: email,
                  password: password,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext).pop();

              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isLoading = false;
                  errorMessage = 'A bejelentkezés sikertelen. Ellenőrizd az adatokat.';
                });
              }
            }

            return AlertDialog(
              title: const Text('Bejelentkezés e-maillel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail-cím',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: isLoading ? null : (_) => signIn(),
                    decoration: InputDecoration(
                      labelText: 'Jelszó',
                      prefixIcon: const Icon(Icons.lock_outline),
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
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: isLoading ? null : signIn,
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Bejelentkezés'),
                ),
              ],
            );
          },
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    emailController.dispose();
    passwordController.dispose();
  }
  Future<void> _showPasswordResetDialog() async {
    final emailController = TextEditingController(text: _lastLoginEmail);
    bool isSending = false;
    String? errorMessage;

    try {
      final sent = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> sendResetEmail() async {
                if (isSending) return;

                final email = emailController.text.trim();
                if (email.isEmpty) {
                  setDialogState(() {
                    errorMessage = 'Add meg az e-mail-címedet.';
                  });
                  return;
                }
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  setDialogState(() {
                    errorMessage = 'Adj meg egy érvényes e-mail-címet.';
                  });
                  return;
                }

                setDialogState(() {
                  isSending = true;
                  errorMessage = null;
                });

                try {
                  await _authRepository.resetPassword(email);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } on FirebaseAuthException catch (error) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSending = false;
                    errorMessage = switch (error.code) {
                      'invalid-email' => 'Adj meg egy érvényes e-mail-címet.',
                      'network-request-failed' =>
                        'Hálózati hiba. Ellenőrizd az internetkapcsolatot, majd próbáld újra.',
                      'too-many-requests' =>
                        'Túl sok próbálkozás. Kérjük, próbáld újra később.',
                      _ => 'Nem sikerült elküldeni a visszaállító e-mailt. Próbáld újra később.',
                    };
                  });
                } catch (_) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    isSending = false;
                    errorMessage =
                        'Nem sikerült elküldeni a visszaállító e-mailt. Próbáld újra később.';
                  });
                }
              }

              return PopScope(
                canPop: !isSending,
                child: AlertDialog(
                  title: const Text('Jelszó visszaállítása'),
                  content: SingleChildScrollView(
                    child: TextField(
                      controller: emailController,
                      autofocus: true,
                      enabled: !isSending,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.email],
                      onSubmitted: isSending ? null : (_) => sendResetEmail(),
                      decoration: InputDecoration(
                        labelText: 'E-mail-cím',
                        prefixIcon: const Icon(Icons.email_outlined),
                        errorText: errorMessage,
                        errorMaxLines: 4,
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: isSending
                          ? null
                          : () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Mégse'),
                    ),
                    FilledButton(
                      onPressed: isSending ? null : sendResetEmail,
                      child: isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Visszaállító e-mail küldése'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (sent == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ha a megadott e-mail-címhez tartozik Kuktám-fiók, elküldtük a jelszó-visszaállító levelet. Ellenőrizd a Spam mappát is.',
            ),
          ),
        );
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      emailController.dispose();
    }
  }

  Future<void> _showRegistrationDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;
    final confirmPasswordController = TextEditingController();
    bool isConfirmPasswordVisible = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool isLoading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> register() async {
              final email = emailController.text.trim();
              final password = passwordController.text;
              final confirmPassword = confirmPasswordController.text;

              if (email.isEmpty ||
                  password.isEmpty ||
                  confirmPassword.isEmpty) {
                setDialogState(() {
                  errorMessage = 'Minden mező kitöltése kötelező.';
                });
                return;
              }

              if (password.length < 6) {
                setDialogState(() {
                  errorMessage =
                  'A jelszónak legalább 6 karakterből kell állnia.';
                });
                return;
              }

              if (password != confirmPassword) {
                setDialogState(() {
                  errorMessage = 'A két jelszó nem egyezik.';
                });
                return;
              }

              setDialogState(() {
                isLoading = true;
                errorMessage = null;
              });

              try {
                await _authRepository.registerWithEmail(
                  email: email,
                  password: password,
                );

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext).pop();

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Sikeres regisztráció! Megerősítő levelet küldtünk '
                          'az e-mail-címedre.',
                    ),
                  ),
                );
              } catch (error) {
                if (!dialogContext.mounted) {
                  return;
                }

                setDialogState(() {
                  isLoading = false;
                  errorMessage =
                  'A regisztráció sikertelen. Ellenőrizd az adatokat.';
                });
              }
            }

            return AlertDialog(
              title: const Text('Regisztráció'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'E-mail-cím',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Jelszó',
                        helperText: 'Legalább 6 karakter',
                        prefixIcon: const Icon(Icons.lock_outline),
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: !isConfirmPasswordVisible,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: isLoading ? null : (_) => register(),
                      decoration: InputDecoration(
                        labelText: 'Jelszó megerősítése',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
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
                    if (errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage!,
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
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: isLoading ? null : register,
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Regisztráció'),
                ),
              ],
            );
          },
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));

    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 170,
                ),
                const SizedBox(height: 12),
                Text(
                  'Kuktám',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.forestGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                    child: _isGoogleLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Folytatás Google-lel'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _showEmailSignInDialog,
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Bejelentkezés e-maillel'),
                  ),
                ),
                const SizedBox(height: 12),
            TextButton(
              onPressed: _showRegistrationDialog,
              child: const Text('Regisztráció'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _showPasswordResetDialog,
                  child: const Text('Elfelejtett jelszó'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}