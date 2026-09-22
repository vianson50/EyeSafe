import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/theme.dart';

/// Écran de connexion / inscription.
/// Le design prolonge celui du splash (fond marine, accents cyan).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _navy = Color(0xFF0D1727);
  static const _navyDeep = Color(0xFF0A1220);
  static const _cyan = Color(0xFF22D3EE);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final client = Supabase.instance.client;
      if (_isSignUp) {
        final response = await client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'full_name': _nameController.text.trim()},
        );
        if (response.session == null) {
          // Confirmation email requise par le projet Supabase.
          if (mounted) {
            setState(() {
              _isSignUp = false;
              _info =
                  'Compte créé. Vérifiez votre boîte mail pour confirmer votre email, puis connectez-vous.';
            });
          }
        }
      } else {
        await client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // La navigation est gérée par AuthGate via onAuthStateChange.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } catch (e) {
      debugPrint('login: $e');
      if (mounted) {
        setState(
          () => _error =
              'Connexion impossible. Vérifiez votre connexion internet et réessayez.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Envoie un email de réinitialisation (auto-service — l'utilisateur
  /// reçoit un lien Supabase pour choisir un nouveau mot de passe).
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _error =
            'Saisissez votre email ci-dessus, puis touchez '
            '« Mot de passe oublié ? ».',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(
          () => _info =
              'Email de réinitialisation envoyé à $email. '
              'Ouvrez-le et cliquez sur le lien pour choisir un nouveau '
              'mot de passe.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'over_request_rate_limit'
              ? 'Trop de demandes. Réessayez dans quelques minutes.'
              : 'Envoi impossible — vérifiez l\'email saisi.',
        );
      }
    } catch (e) {
      debugPrint('forgotPassword: $e');
      if (mounted) {
        setState(() => _error = 'Envoi impossible. Vérifiez votre connexion.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(AuthException e) {
    return switch (e.code) {
      'invalid_credentials' => 'Email ou mot de passe incorrect.',
      'user_already_exists' ||
      'email_exists' => 'Un compte existe déjà avec cet email.',
      'weak_password' =>
        'Mot de passe trop faible (12 caractères minimum recommandés).',
      'email_not_confirmed' =>
        'Email non confirmé — vérifiez votre boîte de réception.',
      'over_request_rate_limit' =>
        'Trop de tentatives. Réessayez dans quelques instants.',
      _ => e.message,
    };
  }

  InputDecoration _decoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      floatingLabelStyle: const TextStyle(color: _cyan, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _cyan, width: 1.4),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFCA5A5)),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [_navy, _navyDeep],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'Logo/securcam_logo.png',
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'EYESAFE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppColors.card,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp
                          ? 'CRÉER UN COMPTE CLIENT'
                          : 'ESPACE CLIENT — CONNEXION',
                      textAlign: TextAlign.center,
                      style: monoStyle(
                        10.5,
                        weight: FontWeight.w600,
                        letterSpacing: 2.5,
                        color: _cyan,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isSignUp)
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decoration('Nom complet'),
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Indiquez votre nom.'
                            : null,
                      ),
                    if (_isSignUp) const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration('Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: [AutofillHints.email],
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Indiquez votre email.';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Email invalide.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration(
                        'Mot de passe',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      autofillHints: [AutofillHints.password],
                      validator: (value) => (value == null || value.length < 6)
                          ? '6 caractères minimum.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFDC2626,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFFDC2626,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFFCA5A5),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _cyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _cyan.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: _cyan,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _info!,
                                style: const TextStyle(
                                  color: Color(0xFFA5F3FC),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _loading ? null : _submit,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: _cyan,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _cyan.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: _navy,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    _isSignUp
                                        ? 'Créer mon compte'
                                        : 'Se connecter',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Mot de passe oublié — auto-service : Supabase envoie
                    // un email de réinitialisation (plus besoin de l'admin).
                    if (!_isSignUp)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _loading ? null : _forgotPassword,
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            'Mot de passe oublié ?',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12.5,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!_isSignUp) const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _loading
                          ? null
                          : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _error = null;
                              _info = null;
                            }),
                      behavior: HitTestBehavior.opaque,
                      child: Text.rich(
                        TextSpan(
                          text: _isSignUp
                              ? 'Déjà un compte ? '
                              : 'Pas encore de compte ? ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13.5,
                          ),
                          children: [
                            TextSpan(
                              text: _isSignUp
                                  ? 'Se connecter'
                                  : 'Créer un compte',
                              style: const TextStyle(
                                color: _cyan,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
