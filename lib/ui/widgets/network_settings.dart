import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/rtc_config.dart';
import '../../data/site_controller.dart';
import '../../ui/theme.dart';
import 'common.dart';

/// Dialogue « Réseaux & mosaïque » partagé entre la page Caméras (⚙) et
/// la page Paramètres : quota de flux live + STUN/TURN.
Future<void> showNetworkSettingsDialog(
  BuildContext context,
  SiteController data,
) async {
  final rtc = await RtcConfig.loadAll();
  if (!context.mounted) return;

  final scheduler = data.streams;

  final stunController = TextEditingController(text: rtc.stunUrls);
  final turnUrlController = TextEditingController(text: rtc.turnUrl);
  final turnUserController = TextEditingController(text: rtc.turnUser);
  final turnPassController = TextEditingController(text: rtc.turnPass);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Réglages réseau & mosaïque',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FLUX LIVE SIMULTANÉS (MOSAÏQUE)',
                  style: monoStyle(
                    10,
                    weight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.onSurfaceFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Les caméras au-delà du quota affichent un snapshot JPG '
                  'rafraîchi toutes les 5 secondes.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in [1, 2, 4, 6, 8, 12])
                      GestureDetector(
                        onTap: () {
                          setDialogState(() => scheduler.setMaxLivePreviews(n));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheduler.maxLivePreviews == n
                                ? AppColors.primary
                                : AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheduler.maxLivePreviews == n
                                  ? AppColors.primary
                                  : AppColors.outline,
                            ),
                          ),
                          child: Text(
                            '$n',
                            style: monoStyle(
                              12,
                              weight: FontWeight.w700,
                              color: scheduler.maxLivePreviews == n
                                  ? Colors.white
                                  : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Sur réseau faible (4G/ADSL), l\'app réduit automatiquement '
                  'ce quota si les snapshots deviennent lents.',
                  style: monoStyle(
                    10,
                    height: 1.4,
                    color: AppColors.onSurfaceFaint,
                  ),
                ),
                const Divider(height: 28),
                Text(
                  'WEBRTC — STUN / TURN (PERÇAGE NAT)',
                  style: monoStyle(
                    10,
                    weight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.onSurfaceFaint,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Le direct tente d\'abord la connexion UDP directe (STUN). '
                  'Sur NAT restrictif, un serveur TURN évite le repli HLS '
                  '(plus lourd et plus latence).',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stunController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Serveurs STUN (séparés par des virgules)',
                    labelStyle: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceLow,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: monoStyle(11, color: AppColors.onSurface),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: turnUrlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'TURN (optionnel, ex: turn:turn.ci:3478)',
                    labelStyle: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceLow,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  style: monoStyle(11, color: AppColors.onSurface),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: turnUserController,
                        decoration: InputDecoration(
                          labelText: 'TURN utilisateur',
                          labelStyle: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceLow,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        style: monoStyle(11, color: AppColors.onSurface),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: turnPassController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'TURN mot de passe',
                          labelStyle: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceLow,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        style: monoStyle(11, color: AppColors.onSurface),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.check_outlined,
              height: 42,
              uppercase: false,
              onTap: () {
                unawaited(scheduler.savePrefs());
                unawaited(
                  RtcConfig.save(
                    stunUrls: stunController.text,
                    turnUrl: turnUrlController.text,
                    turnUser: turnUserController.text,
                    turnPass: turnPassController.text,
                  ),
                );
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    ),
  );
}
