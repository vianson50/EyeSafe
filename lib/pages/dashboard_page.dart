import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/site_controller.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.onOpenEquipment,
    required this.onOpenSupport,
    required this.onOpenMaintenance,
    required this.onReportIncident,
  });

  final VoidCallback onOpenEquipment;
  final VoidCallback onOpenSupport;
  final VoidCallback onOpenMaintenance;
  final VoidCallback onReportIncident;

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final medium = constraints.maxWidth >= 700;
        final padding = EdgeInsets.all(wide ? 32.0 : 20);

        final openTickets = data.tickets
            .where((t) => t.status != TicketStatus.resolved)
            .length;
        final onlineCameras = data.equipment
            .where((e) => e.category == EquipmentCategory.camera)
            .length;
        final upcomingVisits = data.visits.where((v) => !v.isPast).toList();
        final nextVisit = upcomingVisits.isEmpty ? null : upcomingVisits.first;
        final recentAlerts = data.alerts.take(3).toList();

        // Grille de stats : hauteur fixe (mainAxisExtent) pour éviter tout
        // débordement, et cartes compactes (icône à gauche) quand les
        // cellules sont étroites — sinon les labels se coupent verticalement.
        final statColumns = wide ? 4 : 2;
        final statSpacing = 16.0 * (statColumns - 1);
        final statCellWidth =
            (constraints.maxWidth - padding.horizontal - statSpacing) /
            statColumns;
        final compactStats = statCellWidth < 210;

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              wide
                  ? IntrinsicHeight(
                      // IntrinsicHeight : le Row(stretch) est dans un
                      // SingleChildScrollView (hauteur non bornée) — sans
                      // cela, stretch propage une hauteur infinie.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: _hero(context)),
                          const SizedBox(width: 24),
                          Expanded(flex: 7, child: _systemStatusCard(data)),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _hero(context),
                        const SizedBox(height: 24),
                        _systemStatusCard(data),
                      ],
                    ),
              const SizedBox(height: 40),
              const SectionHeader('Vue d\'ensemble'),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: statColumns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: compactStats ? 92.0 : 126.0,
                children: [
                  _StatCard(
                    icon: Icons.videocam_outlined,
                    color: const Color(0xFF6D3BD7),
                    value: '$onlineCameras/$onlineCameras',
                    label: 'CAMÉRAS EN LIGNE',
                    compact: compactStats,
                  ),
                  _StatCard(
                    icon: Icons.support_agent_outlined,
                    color: const Color(0xFFD97706),
                    value: '$openTickets',
                    label: 'TICKETS OUVERTS',
                    onTap: onOpenSupport,
                    compact: compactStats,
                  ),
                  _StatCard(
                    icon: Icons.event_available_outlined,
                    color: const Color(0xFF0891B2),
                    value: nextVisit == null
                        ? '—'
                        : 'J+${nextVisit.date.difference(DateTime.now()).inDays}',
                    label: 'PROCHAINE RÉVISION',
                    onTap: onOpenMaintenance,
                    compact: compactStats,
                  ),
                  _StatCard(
                    icon: Icons.verified_user_outlined,
                    color: const Color(0xFF0C9E6C),
                    value: 'ACTIF',
                    label: 'CONTRAT MAINTENANCE',
                    onTap: onOpenMaintenance,
                    compact: compactStats,
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const SectionHeader('Alertes récentes'),
              const SizedBox(height: 16),
              medium
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < recentAlerts.length; i++) ...[
                          if (i > 0) const SizedBox(width: 16),
                          Expanded(
                            child: _AlertPreview(
                              alert: recentAlerts[i],
                              onTap: onOpenSupport,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < recentAlerts.length; i++) ...[
                          if (i > 0) const SizedBox(height: 16),
                          _AlertPreview(
                            alert: recentAlerts[i],
                            onTap: onOpenSupport,
                          ),
                        ],
                      ],
                    ),
              const SizedBox(height: 40),
              const SectionHeader('Actions rapides'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  PrimaryButton(
                    label: 'Signaler un incident',
                    icon: Icons.report_problem_outlined,
                    onTap: onReportIncident,
                  ),
                  GhostButton(
                    label: 'Mes équipements',
                    icon: Icons.videocam_outlined,
                    onTap: onOpenEquipment,
                  ),
                  GhostButton(
                    label: 'Planning d\'entretien',
                    icon: Icons.event_outlined,
                    onTap: onOpenMaintenance,
                    color: AppColors.secondary,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TechBadge(
          'Espace client',
          color: AppColors.primary,
          background: AppColors.primaryContainer,
        ),
        const SizedBox(height: 14),
        Text(
          'Bonjour,\nbienvenue sur EyeSafe.',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Votre installation de vidéosurveillance est surveillée en permanence. '
          'Retrouvez ici l\'état de votre système, vos équipements et vos demandes.',
          style: TextStyle(
            fontSize: 15,
            height: 1.55,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _systemStatusCard(SiteController data) {
    const navy = Color(0xFF0D1727);
    const cyan = Color(0xFF22D3EE);

    final siteLabel = (data.contract?.siteLabel ?? 'MON SITE').toUpperCase();
    final storage = data.equipment
        .where((e) => e.storageUsed != null)
        .map((e) => e.storageUsed!)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final storageLabel = storage > 0
        ? '${(storage * 100).round()} % UTILISÉS'
        : 'N/A';
    final cameras = data.equipment
        .where((e) => e.category == EquipmentCategory.camera)
        .length;

    Widget row(String label, String value, Color valueColor) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(
                  11.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(
                  12.5,
                  weight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF34D399),
                  boxShadow: [
                    BoxShadow(color: Color(0xFF34D399), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SYSTÈME OPÉRATIONNEL',
                    style: monoStyle(
                      12,
                      weight: FontWeight.w700,
                      letterSpacing: 2,
                      color: const Color(0xFF34D399),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          row('SITE', siteLabel, Colors.white),
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          row('CAMÉRAS', '$cameras/$cameras EN LIGNE', cyan),
          row('ENREGISTREMENT', 'NVR ACTIF · 24/7', const Color(0xFF34D399)),
          row('DISQUE NVR', storageLabel, const Color(0xFFD97706)),
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          row(
            'DERNIÈRE SYNCHRO',
            'IL Y A 4 MIN',
            Colors.white.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  /// Layout horizontal (icône à gauche) pour les cellules étroites.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: compact ? 36 : 34,
      height: compact ? 36 : 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.1),
      ),
      child: Icon(icon, size: 18, color: color),
    );

    if (compact) {
      return WhiteCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(
                      9.5,
                      weight: FontWeight.w600,
                      letterSpacing: 0.5,
                      height: 1.3,
                      color: AppColors.onSurfaceFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return WhiteCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconBox,
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(
              10,
              weight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.onSurfaceFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertPreview extends StatelessWidget {
  const _AlertPreview({required this.alert, this.onTap});

  final SupportAlert alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return WhiteCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.secondaryContainer,
                ),
                child: Icon(alert.icon, size: 18, color: AppColors.secondary),
              ),
              const Spacer(),
              Text(
                alert.time,
                style: monoStyle(
                  9.5,
                  letterSpacing: 1,
                  color: AppColors.onSurfaceFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            alert.title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            alert.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
