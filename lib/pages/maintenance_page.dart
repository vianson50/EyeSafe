import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  bool _reminders = true;
  bool _remindersReady = false;
  String? _downloadingRef;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadReminders());
    });
  }

  Future<void> _loadReminders() async {
    final value = await DataScope.of(context).loadMaintenanceReminders();
    if (!mounted) return;
    setState(() {
      _reminders = value;
      _remindersReady = true;
    });
  }

  Future<void> _setReminders(bool v) async {
    setState(() => _reminders = v);
    await DataScope.of(context).saveMaintenanceReminders(v);
    if (!mounted) return;
    _snack(
      v
          ? 'Rappels automatiques activés'
          : 'Rappels automatiques désactivés',
    );
  }

  /// Ouvre le rapport PDF réel : URL signée du stockage (ou URL absolue).
  Future<void> _downloadReport(MaintenanceVisit visit) async {
    if (_downloadingRef != null) return;
    setState(() => _downloadingRef = visit.reportRef);
    try {
      final data = DataScope.of(context);
      final url = await data.signedReportUrl(visit.reportRef);
      if (!mounted) return;
      if (url == null) {
        _snack('Rapport indisponible pour le moment.');
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _snack('Ouverture du rapport impossible sur cet appareil.');
      }
    } finally {
      if (mounted) setState(() => _downloadingRef = null);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.onSurface,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final medium = constraints.maxWidth >= 700;
        final padding = EdgeInsets.all(wide ? 32.0 : 20);

        final upcoming = data.visits.where((v) => !v.isPast).toList();
        final past = data.visits.where((v) => v.isPast).toList();

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 24),
              _contractBanner(context, data.contract),
              const SizedBox(height: 32),
              medium
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeader('Prochaines révisions'),
                              const SizedBox(height: 16),
                              if (upcoming.isEmpty)
                                Text(
                                  'Aucune visite planifiée pour le moment.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              for (final visit in upcoming) ...[
                                _UpcomingVisitCard(visit: visit),
                                const SizedBox(height: 12),
                              ],
                              const SizedBox(height: 24),
                              const SectionHeader('Rapports d\'intervention'),
                              const SizedBox(height: 16),
                              if (past.isEmpty)
                                Text(
                                  'Aucun rapport d\'intervention disponible.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              for (final visit in past) ...[
                                _PastVisitCard(
                                  visit: visit,
                                  downloading:
                                      _downloadingRef == visit.reportRef,
                                  onDownload: () => _downloadReport(visit),
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: _ChecklistCard(visits: data.visits)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Prochaines révisions'),
                        const SizedBox(height: 16),
                        if (upcoming.isEmpty)
                          Text(
                            'Aucune visite planifiée pour le moment.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        for (final visit in upcoming) ...[
                          _UpcomingVisitCard(visit: visit),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 32),
                        _ChecklistCard(visits: data.visits),
                        const SizedBox(height: 32),
                        const SectionHeader('Rapports d\'intervention'),
                        const SizedBox(height: 16),
                        if (past.isEmpty)
                          Text(
                            'Aucun rapport d\'intervention disponible.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        for (final visit in past) ...[
                          _PastVisitCard(
                            visit: visit,
                            downloading: _downloadingRef == visit.reportRef,
                            onDownload: () => _downloadReport(visit),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Entretiens & maintenance',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vos visites de maintenance préventive, les rapports signés par nos '
          'techniciens et les rappels de votre contrat.',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _contractBanner(BuildContext context, ContractInfo? contract) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D3BD7), Color(0xFF592CB4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.workspace_premium_outlined,
              color: AppColors.card,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contract?.plan ?? 'Contrat maintenance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.card,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contract?.siteLabel ?? 'Mon site'} · Renouvellement le ${contract?.renewalLabel ?? '—'}',
                  style: monoStyle(
                    11,
                    letterSpacing: 0.5,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RAPPELS AUTO',
                style: monoStyle(
                  9.5,
                  weight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Switch(
                value: _reminders,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF4CD7F6),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                onChanged:
                    _remindersReady ? _setReminders : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingVisitCard extends StatelessWidget {
  const _UpcomingVisitCard({required this.visit});

  final MaintenanceVisit visit;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final daysLeft = v.date.difference(DateTime.now()).inDays;

    return WhiteCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  v.dayNumber,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
                Text(
                  v.monthLabel,
                  style: monoStyle(
                    9.5,
                    weight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TechBadge(
                      'Dans $daysLeft jours',
                      color: AppColors.primary,
                      background: AppColors.primaryContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  v.technician,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                for (final task in v.tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: AppColors.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            task,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastVisitCard extends StatelessWidget {
  const _PastVisitCard({
    required this.visit,
    required this.onDownload,
    this.downloading = false,
  });

  final MaintenanceVisit visit;
  final VoidCallback onDownload;

  /// Vrai pendant la récupération de l'URL signée du rapport.
  final bool downloading;

  @override
  Widget build(BuildContext context) {
    final v = visit;

    // Carte adaptative : sur largeur étroite, le badge et le bouton PDF
    // passent sous les textes — sinon le Row écrase les textes et le
    // contenu s'affiche verticalement lettre par lettre.
    return WhiteCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final texts = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.dateLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${v.technician.split('—').first.trim()} · ${v.tasks.length} intervention${v.tasks.length > 1 ? 's' : ''}',
                  style: monoStyle(10.5, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          );

          final icon = Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.tertiaryContainer,
            ),
            child: Icon(Icons.history, size: 19, color: AppColors.tertiary),
          );

          final badge = Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TechBadge(
                'Rapport signé',
                color: AppColors.tertiary,
                background: AppColors.tertiaryContainer,
              ),
            ),
          );

          final pdfButton = GhostButton(
            label: downloading ? '…' : 'PDF',
            icon: downloading ? null : Icons.download_outlined,
            color: AppColors.secondary,
            height: 38,
            onTap: downloading ? null : onDownload,
          );

          if (constraints.maxWidth >= 460) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 12),
                texts,
                const SizedBox(width: 12),
                badge,
                const SizedBox(width: 12),
                pdfButton,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [icon, const SizedBox(width: 12), texts]),
              const SizedBox(height: 12),
              Row(children: [badge, const Spacer(), pdfButton]),
            ],
          );
        },
      ),
    );
  }
}

/// Élément du programme préventif déduit des visites réelles du site.
class _ProgramItem {
  const _ProgramItem(this.label, this.freq, this.icon);

  final String label;
  final String freq;
  final IconData icon;

  /// Construit le programme depuis les visites réelles : chaque tâche
  /// distincte devient une ligne ; sa fréquence est déduite de l'intervalle
  /// moyen entre les visites qui la contiennent (≈6 mois → semestrielle,
  /// sinon annuelle). L'icône est choisie par mots-clés.
  static List<_ProgramItem> fromVisits(List<MaintenanceVisit> visits) {
    final byTask = <String, List<DateTime>>{};
    for (final v in visits) {
      for (final task in v.tasks) {
        final label = task.trim();
        if (label.isEmpty) continue;
        byTask.putIfAbsent(label, () => []).add(v.date);
      }
    }

    final items = <_ProgramItem>[];
    byTask.forEach((label, dates) {
      String freq = 'Annuelle';
      if (dates.length >= 2) {
        final sorted = dates..sort();
        final spanDays =
            sorted.last.difference(sorted.first).inDays / (sorted.length - 1);
        if (spanDays <= 213) freq = 'Tous les 6 mois'; // ≈ 7 mois max
      } else if (dates.length == 1) {
        // Une seule occurrence : on ne peut pas déduire de périodicité.
        freq = 'Selon planning';
      }
      items.add(_ProgramItem(label, freq, _iconFor(label)));
    });

    items.sort((a, b) => a.label.compareTo(b.label));
    return items;
  }

  static IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l.contains('nettoy') || l.contains('objectif')) {
      return Icons.cleaning_services_outlined;
    }
    if (l.contains('alimentation') ||
        l.contains('onduleur') ||
        l.contains('électr')) {
      return Icons.electrical_services_outlined;
    }
    if (l.contains('disque') || l.contains('stockage') || l.contains('dis dur')) {
      return Icons.storage_outlined;
    }
    if (l.contains('firmware') || l.contains('mise à jour') || l.contains('maj')) {
      return Icons.system_update_outlined;
    }
    if (l.contains('align') || l.contains('cadrag') || l.contains('caméra')) {
      return Icons.center_focus_strong_outlined;
    }
    if (l.contains('batterie')) return Icons.battery_charging_full_outlined;
    if (l.contains('câble') || l.contains('reseau') || l.contains('réseau')) {
      return Icons.cable_outlined;
    }
    return Icons.build_circle_outlined;
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.visits});

  final List<MaintenanceVisit> visits;

  @override
  Widget build(BuildContext context) {
    final items = _ProgramItem.fromVisits(visits);

    return WhiteCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Programme préventif'),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Text(
              'Aucun programme défini pour ce site. Il apparaîtra dès la '
              'première visite planifiée.',
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          for (final item in items) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final iconBox = Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.surface,
                  ),
                  child: Icon(
                    item.icon,
                    size: 17,
                    color: AppColors.onSurfaceVariant,
                  ),
                );

                final labelText = Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                );

                final freqText = Text(
                  item.freq.toUpperCase(),
                  style: monoStyle(
                    9.5,
                    weight: FontWeight.w600,
                    letterSpacing: 1,
                    color: AppColors.onSurfaceFaint,
                  ),
                );

                if (constraints.maxWidth >= 340) {
                  return Row(
                    children: [
                      iconBox,
                      const SizedBox(width: 12),
                      Expanded(child: labelText),
                      const SizedBox(width: 8),
                      freqText,
                    ],
                  );
                }

                // Cellule étroite : la fréquence passe sous le label pour
                // ne pas comprimer le texte.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          labelText,
                          const SizedBox(height: 2),
                          freqText,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
          ],
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vous êtes notifié 7 jours avant chaque visite.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
