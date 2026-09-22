import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/site_controller.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});

  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}

class _EquipmentPageState extends State<EquipmentPage> {
  EquipmentCategory? _filter;


  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final padding = EdgeInsets.all(wide ? 32.0 : 20);

        final all = data.equipment;
        final items = _filter == null
            ? all
            : all.where((e) => e.category == _filter).toList();

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Mes équipements',
                subtitle:
                    'Inventaire complet de votre installation : caméras, '
                    'enregistreur, stockage et réseau, avec suivi des garanties.',
                actions: [
                  PrimaryButton(
                    label: 'Demander une extension',
                    icon: Icons.add_circle_outline,
                    // Vrai ticket côté backend — plus de simulation.
                    onTap: () => _requestExtension(data),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('Tout', null),
                  for (final c in EquipmentCategory.values)
                    _filterChip(c.label, c),
                ],
              ),
              const SizedBox(height: 24),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 460,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 180,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _EquipmentCard(
                  equipment: items[i],
                  onTap: () => _showDetail(context, items[i]),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${all.length} équipements suivis par votre installateur',
                style: monoStyle(
                  11,
                  letterSpacing: 0.5,
                  color: AppColors.onSurfaceFaint,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, EquipmentCategory? category) {
    final selected = _filter == category;
    return GestureDetector(
      onTap: () => setState(() => _filter = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outline,
          ),
        ),
        child: Text(
          label,
          style: monoStyle(
            11.5,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Equipment e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _EquipmentDetail(
        equipment: e,
        // Vrais tickets créés côté backend (plus de simulation « démo »).
        onIncident: () {
          Navigator.of(sheetCtx).pop();
          _createTicket(
            e,
            title: 'Incident signalé — ${e.name}',
            description:
                'Incident ouvert depuis la fiche équipement '
                '(${e.model.isNotEmpty ? e.model : e.category.label}).',
          );
        },
        onReplace: () {
          Navigator.of(sheetCtx).pop();
          _createTicket(
            e,
            title: 'Demande de remplacement — ${e.name}',
            description:
                'Remplacement demandé depuis la fiche équipement '
                '(modèle ${e.model.isNotEmpty ? e.model : 'inconnu'}, '
                'n° ${e.serial}).',
          );
        },
        // Le contexte de la PAGE reste valide après fermeture de la fiche.
        onDisconnect: () => _disconnectEquipment(e),
      ),
    );
  }

  /// Crée un vrai ticket pour cet équipement (mode réel : insertion
  /// Supabase + notification temps réel de l'installateur).
  Future<void> _createTicket(
    Equipment e, {
    required String title,
    required String description,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final data = DataScope.of(context);
    final error = await data.createTicket(
      title: title,
      equipmentId: e.id,
      description: description,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.onSurface,
          content: Text(
            error ??
                'Ticket créé pour ${e.name} — votre installateur est '
                    'notifié.',
          ),
        ),
      );
  }

  /// Demande d'extension d'installation : vrai ticket global (sans
  /// équipement précis — porte sur l'installation entière).
  Future<void> _requestExtension(SiteController data) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await data.createExtensionRequest(
      description:
          'Demande d\'extension d\'installation : ajout de '
          'caméras ou d\'équipements supplémentaires.',
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.onSurface,
          content: Text(
            error ??
                'Demande d\'extension envoyée — votre installateur est '
                    'notifié et vous répondra sous 24 h.',
          ),
        ),
      );
  }

  Future<void> _disconnectEquipment(Equipment e) async {
    final confirmed = await confirmRemoveEquipment(context, name: e.name);
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final data = DataScope.of(context);
    final error = await data.removeEquipment(e);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.onSurface,
          content: Text(
            error ??
                '${e.name} déconnecté. Reconnectez-le à tout moment depuis la '
                    'page Caméras (bouton « Connecter un NVR »).',
          ),
        ),
      );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.equipment, this.onTap});

  final Equipment equipment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final color = e.category.color;

    return WhiteCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withValues(alpha: 0.1),
                ),
                child: Icon(e.category.icon, size: 22, color: color),
              ),
              const Spacer(),
              _WarrantyBadge(equipment: e),
            ],
          ),
          const Spacer(),
          Text(
            e.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${e.model} · ${e.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(11, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (e.storageUsed != null) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: e.storageUsed,
                      minHeight: 5,
                      backgroundColor: AppColors.surfaceHigh,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${(e.storageUsed! * 100).round()} % · ${e.storageTotal}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(10.5, color: AppColors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Flexible(
                child: Text(
                  'N° ${e.serial}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(10.5, color: AppColors.onSurfaceFaint),
                ),
              ),
              const SizedBox(width: 12),
              Spacer(),
              Flexible(
                child: Text(
                  'Installé le ${e.installDateLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(10.5, color: AppColors.onSurfaceFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarrantyBadge extends StatelessWidget {
  const _WarrantyBadge({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    final e = equipment;

    if (!e.underWarranty) {
      return TechBadge('Garantie expirée', color: AppColors.error);
    }
    if (e.warrantyExpiringSoon) {
      final days = e.warrantyUntil!.difference(DateTime.now()).inDays;
      return TechBadge('Garantie J-$days', color: const Color(0xFFD97706));
    }
    return TechBadge('Sous garantie', color: AppColors.tertiary);
  }
}

class _EquipmentDetail extends StatelessWidget {
  const _EquipmentDetail({
    required this.equipment,
    required this.onIncident,
    required this.onReplace,
    this.onDisconnect,
  });

  final Equipment equipment;
  final VoidCallback onIncident;
  final VoidCallback onReplace;

  /// Déconnexion / retrait de l'équipement (optionnel).
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final e = equipment;
    final color = e.category.color;

    Widget specRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: monoStyle(
                  11,
                  letterSpacing: 0.5,
                  color: AppColors.onSurfaceFaint,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: monoStyle(
                  12,
                  weight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: color.withValues(alpha: 0.1),
                  ),
                  child: Icon(e.category.icon, size: 26, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TechBadge(e.category.label, color: color),
                    ],
                  ),
                ),
                _WarrantyBadge(equipment: e),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  specRow('MODÈLE', e.model),
                  Divider(color: AppColors.outlineVariant),
                  specRow('N° SÉRIE', e.serial),
                  Divider(color: AppColors.outlineVariant),
                  specRow('EMPLACEMENT', e.location),
                  Divider(color: AppColors.outlineVariant),
                  specRow('INSTALLÉ LE', e.installDateLabel),
                  Divider(color: AppColors.outlineVariant),
                  specRow(
                    'GARANTIE',
                    e.warrantyUntil == null
                        ? 'Expirée'
                        : 'Jusqu\'au ${e.warrantyUntil!.day.toString().padLeft(2, '0')}/${e.warrantyUntil!.month.toString().padLeft(2, '0')}/${e.warrantyUntil!.year}',
                  ),
                  if (e.storageUsed != null) ...[
                    Divider(color: AppColors.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              'STOCKAGE',
                              style: monoStyle(
                                11,
                                letterSpacing: 0.5,
                                color: AppColors.onSurfaceFaint,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: e.storageUsed,
                                minHeight: 5,
                                backgroundColor: AppColors.surfaceHigh,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(e.storageUsed! * 100).round()} % · ${e.storageTotal}',
                            style: monoStyle(
                              11,
                              weight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Signaler un incident',
                    icon: Icons.report_problem_outlined,
                    onTap: onIncident,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(
                    label: 'Demander remplacement',
                    icon: Icons.swap_horiz,
                    onTap: onReplace,
                  ),
                ),
              ],
            ),
            if (onDisconnect != null) ...[
              const SizedBox(height: 12),
              GhostButton(
                label: 'Déconnecter cet équipement',
                icon: Icons.link_off_outlined,
                color: AppColors.error,
                expanded: true,
                height: 42,
                onTap: () {
                  // Ferme la fiche d'abord, puis lance la confirmation.
                  Navigator.of(context).pop();
                  onDisconnect?.call();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
