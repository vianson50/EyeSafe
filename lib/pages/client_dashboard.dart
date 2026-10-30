import 'package:flutter/material.dart';

import '../data/models.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

/// Dashboard client redessiné : l'état du parc en premier, l'action en 1 tap.
/// Le client voit immédiatement :
///   → Combien de caméras sont en ligne / hors ligne
///   → Ses tickets ouverts avec gravité
///   → Bouton "Signaler une panne" en évidence
class ClientDashboard extends StatelessWidget {
  const ClientDashboard({
    super.key,
    required this.onOpenCameras,
    required this.onOpenSupport,
    required this.onReportIncident,
  });

  final VoidCallback onOpenCameras;
  final VoidCallback onOpenSupport;
  final VoidCallback onReportIncident;

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    final cameras = data.equipment
        .where((e) => e.category == EquipmentCategory.camera)
        .toList();
    final openTickets = data.tickets
        .where((t) => t.status != TicketStatus.resolved)
        .toList();
    final critical = openTickets.where((t) => t.title.contains('🔴')).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // ÉTAT DU PARC (en gros, en premier)
          _ParkStatusCard(
            cameras: cameras,
            critical: critical,
            onTap: onOpenCameras,
          ),
          const SizedBox(height: 24),

          // Bouton principal : SIGNALER
          PrimaryButton(
            label: 'Signaler une panne',
            icon: Icons.report_problem_outlined,
            color: AppColors.error,
            expanded: true,
            height: 54,
            onTap: onReportIncident,
          ),
          const SizedBox(height: 24),

          // TICKETS OUVERTS
          Text(
            'MES DEMANDES (${openTickets.length})',
            style: monoStyle(
              10,
              weight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.onSurfaceFaint,
            ),
          ),
          const SizedBox(height: 12),
          if (openTickets.isEmpty)
            Text(
              'Aucune demande en cours.',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            )
          else
            for (final t in openTickets.take(3))
              _TicketRow(ticket: t, onTap: onOpenSupport),
        ],
      ),
    );
  }
}

class _ParkStatusCard extends StatelessWidget {
  const _ParkStatusCard({
    required this.cameras,
    required this.critical,
    this.onTap,
  });

  final List<Equipment> cameras;
  final int critical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final online = cameras.where((e) => e.streamUrl != null).length;
    final offline = cameras.length - online;

    return WhiteCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Icône état
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: offline > 0
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.tertiary.withValues(alpha: 0.1),
            ),
            child: Icon(
              offline > 0
                  ? Icons.warning_amber_outlined
                  : Icons.check_circle_outline,
              size: 28,
              color: offline > 0 ? AppColors.error : AppColors.tertiary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offline > 0
                      ? '$offline caméra${offline > 1 ? 's' : ''} hors ligne'
                      : 'Toutes vos caméras fonctionnent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$online/${cameras.length} en ligne'
                  '${critical > 0 ? ' · $critical urgent${critical > 1 ? 's' : ''}' : ''}',
                  style: monoStyle(11, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, this.onTap});

  final Ticket ticket;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ticket.title.contains('🔴')
                ? AppColors.error.withValues(alpha: 0.4)
                : AppColors.outline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ticket.title.contains('🔴')
                    ? AppColors.error
                    : ticket.title.contains('🟠')
                    ? Color(0xFFD97706)
                    : AppColors.tertiary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.title.replaceFirst(RegExp('^[^—]+— '), ''),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    ticket.status.label,
                    style: monoStyle(10, color: AppColors.onSurfaceFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
