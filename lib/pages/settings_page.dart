import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound_service.dart';
import '../core/theme_settings.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/network_settings.dart';

/// Page Paramètres : apparence (thème sombre), réglages réseau & mosaïque,
/// notifications, compte, à propos.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.userEmail, this.onLogout});

  final String? userEmail;
  final VoidCallback? onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _notifications = true;
  late bool _sounds = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final enabled = await PushToggle.load();
    if (!mounted) return;
    setState(() {
      _notifications = enabled;
      _sounds = SoundService.enabled;
    });
  }

  /// Change le mot de passe du compte connecté (vérifie l'ancien).
  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Changer mon mot de passe',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pwdField(current, 'Mot de passe actuel'),
                const SizedBox(height: 10),
                _pwdField(next, 'Nouveau mot de passe'),
                const SizedBox(height: 10),
                _pwdField(confirm, 'Confirmer le nouveau'),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: monoStyle(10.5, height: 1.4, color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            PrimaryButton(
              label: busy ? 'Enregistrement…' : 'Changer',
              icon: Icons.check_outlined,
              height: 42,
              uppercase: false,
              onTap: busy
                  ? null
                  : () async {
                      if (next.text.length < 6) {
                        setDialogState(
                          () => error =
                              'Le nouveau mot de passe doit faire au moins '
                              '6 caractères.',
                        );
                        return;
                      }
                      if (next.text != confirm.text) {
                        setDialogState(
                          () => error =
                              'Les deux nouveaux mots de passe '
                              'ne correspondent pas.',
                        );
                        return;
                      }
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final client = Supabase.instance.client;
                        // 1. Vérifie l'ancien mot de passe en se
                        //    réauthentifiant (évite le changement par
                        //    quelqu'un qui aurait emprunté la session).
                        final email = client.auth.currentUser?.email;
                        if (email == null) {
                          throw const AuthException(
                            'Session invalide — reconnectez-vous.',
                          );
                        }
                        await client.auth.signInWithPassword(
                          email: email,
                          password: current.text,
                        );
                        // 2. Applique le nouveau.
                        await client.auth.updateUser(
                          UserAttributes(password: next.text),
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppColors.onSurface,
                                content: const Text(
                                  '✔ Mot de passe changé — utilisez-le à votre '
                                  'prochaine connexion.',
                                ),
                              ),
                            );
                        }
                      } on AuthException catch (e) {
                        setDialogState(() {
                          busy = false;
                          error = e.statusCode == '400'
                              ? 'Mot de passe actuel incorrect.'
                              : 'Changement impossible (${e.code ?? 'erreur'}).';
                        });
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          error =
                              'Changement impossible. Vérifiez votre '
                              'connexion.';
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  Widget _pwdField(TextEditingController controller, String label) {
    var obscure = true;
    return StatefulBuilder(
      builder: (context, setFieldState) => TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
          ),
          filled: true,
          fillColor: AppColors.surfaceLow,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.onSurfaceFaint,
            ),
            onPressed: () => setFieldState(() => obscure = !obscure),
          ),
        ),
        style: monoStyle(12, color: AppColors.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);

    Widget sectionTitle(String label) => Text(
      label.toUpperCase(),
      style: monoStyle(
        10,
        weight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.onSurfaceFaint,
      ),
    );

    // Écoute le thème : la page ENTIERE se rafraîchit instantanément quand
    // l'utilisateur tape un mode (sinon seul le segmented control change et
    // la page reste sur l'ancienne palette).
    return ListenableBuilder(
      listenable: ThemeSettings.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              PageHeader(
                title: 'Paramètres',
                subtitle:
                    'Lecture direct, notifications et compte — '
                    'mémorisés sur cet appareil.',
              ),
              const SizedBox(height: 32),

              // ── Lecture direct ──
              sectionTitle('Lecture direct'),
              const SizedBox(height: 12),
              WhiteCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _settingRow(
                      icon: Icons.grid_view_outlined,
                      title: 'Réseaux & mosaïque',
                      subtitle:
                          'Quota de flux live simultanés, serveurs STUN/TURN '
                          '(perçage NAT).',
                      onTap: () => showNetworkSettingsDialog(context, data),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Notifications ──
              sectionTitle('Notifications'),
              const SizedBox(height: 12),
              WhiteCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alertes & signalements',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Nouveaux tickets, réponses du technicien et '
                            'interventions planifiées.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _notifications,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) {
                        setState(() => _notifications = v);
                        PushToggle.save(v);
                      },
                    ),
                  ],
                ),
              ),
              // Sons de notification — bip local sur événements caméras.
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.volume_up_outlined,
                    size: 20,
                    color: _sounds
                        ? AppColors.primary
                        : AppColors.onSurfaceFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sons d\'alerte',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bip sonore local quand une caméra détecte un '
                          'mouvement ou une intrusion (même app ouverte).',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _sounds,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() => _sounds = v);
                      SoundService.setEnabled(v);
                      // Aperçu sonore à l'activation.
                      if (v) SoundService.play(NotificationSound.alert);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // ── Compte ──
              if (widget.onLogout != null) ...[
                sectionTitle('Compte'),
                const SizedBox(height: 12),
                WhiteCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 20,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.roleLabel,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                if (widget.userEmail != null)
                                  Text(
                                    widget.userEmail!,
                                    style: monoStyle(
                                      11,
                                      color: AppColors.onSurfaceFaint,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Changer SON mot de passe — auto-service : plus besoin
                      // de l'administrateur ni de la clé service_role.
                      GhostButton(
                        label: 'Changer mon mot de passe',
                        icon: Icons.password_outlined,
                        height: 42,
                        expanded: true,
                        onTap: _changePassword,
                      ),
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: 'Se déconnecter',
                        icon: Icons.logout_outlined,
                        color: AppColors.error,
                        height: 42,
                        uppercase: false,
                        expanded: true,
                        onTap: () async {
                          final confirmed = await confirmSignOut(context);
                          if (!confirmed || !context.mounted) return;
                          // Refermer la page Paramètres avant la déconnexion :
                          // elle vit au-dessus du AuthGate et masquerait sinon
                          // le LoginPage après le signOut.
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          widget.onLogout?.call();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // ── À propos ──
              sectionTitle('À propos'),
              const SizedBox(height: 12),
              WhiteCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EYESAFE — Espace client vidéosurveillance',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0 · Protocoles en Dart pur : ONVIF, ISAPI, '
                      'VAPIX, LAPI, Dahua HTTP, go2rtc, WHEP — zéro SDK natif '
                      'constructeur.',
                      style: monoStyle(
                        10.5,
                        height: 1.5,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_outlined,
            size: 18,
            color: AppColors.onSurfaceFaint,
          ),
        ],
      ),
    );
  }
}

/// Bascule Notifications — mémorisée sur l'appareil, lue par PushService
/// (les notifications locales ne s'affichent que si activées).
class PushToggle {
  PushToggle._();

  static const _key = 'eyesafe_notifications_enabled';

  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> save(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {
      // Stockage indisponible : réglage volatile.
    }
  }
}

/// Confirmation avant déconnexion (identique au menu compte).
Future<bool> confirmSignOut(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Se déconnecter ?',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.onSurface,
        ),
      ),
      content: Text(
        'Vous revenez à l\'écran de connexion et pourrez vous reconnecter '
        'avec vos identifiants client ou technicien.',
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: 'Se déconnecter',
          icon: Icons.logout_outlined,
          color: AppColors.error,
          height: 42,
          uppercase: false,
          onTap: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
