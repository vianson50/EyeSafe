import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../ui/data_scope.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => SupportPageState();
}

class SupportPageState extends State<SupportPage> {
  XFile? _photoFile;

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

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70, // compression avant upload
      maxWidth: 1600, // limite la taille des fichiers (réseaux mobiles)
    );
    if (picked != null) setState(() => _photoFile = picked);
  }

  void openIncidentForm() {
    final data = DataScope.of(context);
    if (data.equipment.isEmpty) {
      _snack('Aucun équipement référencé sur ce site pour l\'instant');
      return;
    }
    setState(() => _photoFile = null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _IncidentForm(
        equipment: data.equipment,
        photoAttached: _photoFile != null,
        onPhoto: (source) => _pickPhoto(source),
        onSubmit: (type, equipmentId, description, photoAttached) async {
          Navigator.of(context).pop();
          final photo = _photoFile;
          final error = await data.createTicket(
            title: type,
            equipmentId: equipmentId,
            description: description,
            photoBytes: photo == null ? null : await photo.readAsBytes(),
            photoExtension: photo?.name.split('.').last ?? 'jpg',
          );
          _snack(
            error ?? 'Incident signalé — votre installateur a été notifié',
          );
        },
      ),
    );
  }

  void _openRespondForm(Ticket ticket) {
    final data = DataScope.of(context);
    showDialog(
      context: context,
      builder: (context) => _RespondDialog(
        ticket: ticket,
        onSubmit: (deadline, note) async {
          Navigator.of(context).pop();
          final error = await data.respondToTicket(
            ticket: ticket,
            deadline: deadline,
            note: note,
          );
          _snack(
            error ??
                'Intervention planifiée — le client a été notifié du délai',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    final tickets = data.tickets;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final medium = constraints.maxWidth >= 700;
        final padding = EdgeInsets.all(wide ? 32.0 : 20);

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Alertes & support',
                subtitle:
                    'Signalez un incident en quelques secondes et suivez la prise '
                    'en charge par votre installateur en temps réel.',
                actions: [
                  PrimaryButton(
                    label: 'Signaler un incident',
                    icon: Icons.report_problem_outlined,
                    color: AppColors.error,
                    onTap: openIncidentForm,
                  ),
                ],
              ),
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
                              const SectionHeader('Mes demandes de support'),
                              const SizedBox(height: 16),
                              if (tickets.isEmpty)
                                Text(
                                  'Aucune demande de support. Tout semble fonctionner.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              for (final ticket in tickets) ...[
                                _TicketCard(
                                  ticket: ticket,
                                  onRespond: data.isTechnician
                                      ? (t) => _openRespondForm(t)
                                      : null,
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SectionHeader('Alertes préventives'),
                              const SizedBox(height: 16),
                              for (final alert in data.alerts) ...[
                                _AlertCard(alert: alert),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader('Mes demandes de support'),
                        const SizedBox(height: 16),
                        if (tickets.isEmpty)
                          Text(
                            'Aucune demande de support. Tout semble fonctionner.',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        for (final ticket in tickets) ...[
                          _TicketCard(
                            ticket: ticket,
                            onRespond: data.isTechnician
                                ? (t) => _openRespondForm(t)
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 32),
                        const SectionHeader('Alertes préventives'),
                        const SizedBox(height: 16),
                        for (final alert in data.alerts) ...[
                          _AlertCard(alert: alert),
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
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, this.onRespond});

  final Ticket ticket;

  /// Affiché pour les tickets en attente quand l'utilisateur est technicien.
  final void Function(Ticket ticket)? onRespond;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final statusColor = t.status.color;
    final stepIndex = switch (t.status) {
      TicketStatus.pending => 0,
      TicketStatus.enRoute => 1,
      TicketStatus.resolved => 2,
    };

    return WhiteCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '${t.id} · ${t.openedLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(
                    10.5,
                    weight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.onSurfaceFaint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (t.hasPhoto)
                Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: AppColors.onSurfaceFaint,
                ),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: TechBadge(
                    t.status.label,
                    color: statusColor,
                    background: statusColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.equipment,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(11, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (t.photoPath != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _PhotoThumb(
                  photoPath: t.photoPath!,
                  onTap: (url) => _showPhoto(context, url),
                ),
              ],
            )
          else
            Text(
              t.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          if (t.interventionAt != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'INTERVENTION PRÉVUE · ${t.interventionLabel}'
                      '${t.technicianNote?.isNotEmpty == true ? ' — ${t.technicianNote}' : ''}',
                      style: monoStyle(
                        10,
                        weight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: AppColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i <= stepIndex
                          ? statusColor.withValues(alpha: 0.5)
                          : AppColors.surfaceHigh,
                    ),
                  ),
                _StepDot(
                  label: const ['Reçu', 'En route', 'Résolu'][i],
                  active: i <= stepIndex,
                  color: statusColor,
                ),
              ],
            ],
          ),
          if (onRespond != null && t.status == TicketStatus.pending) ...[
            const SizedBox(height: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onRespond?.call(ticket),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.engineering_outlined,
                          color: AppColors.card,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'RÉPONDRE — DONNER UN DÉLAI',
                          style: monoStyle(
                            10.5,
                            weight: FontWeight.w700,
                            letterSpacing: 1,
                            color: AppColors.card,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Visionneuse plein écran (zoom piincé via InteractiveViewer).
  void _showPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            maxScale: 4,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'Photo indisponible (lien expiré)',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vignette photo : URL signée via le contrôleur, tap = plein écran.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photoPath, this.onTap});

  final String photoPath;
  final void Function(String url)? onTap;

  @override
  Widget build(BuildContext context) {
    final data = DataScope.of(context);
    return FutureBuilder<String?>(
      future: data.signedPhotoUrl(photoPath),
      builder: (context, snapshot) {
        final url = snapshot.data;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: url == null ? null : () => onTap?.call(url),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: url == null
                  ? snapshot.hasError
                        ? Icon(
                            Icons.broken_image_outlined,
                            size: 22,
                            color: AppColors.onSurfaceFaint,
                          )
                        : const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          size: 22,
                          color: AppColors.onSurfaceFaint,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : AppColors.surfaceHigh,
            border: Border.all(color: active ? color : AppColors.outline),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: monoStyle(
            9.5,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
            color: active ? color : AppColors.onSurfaceFaint,
          ),
        ),
      ],
    );
  }
}

class _RespondDialog extends StatefulWidget {
  const _RespondDialog({required this.ticket, required this.onSubmit});

  final Ticket ticket;
  final Future<void> Function(DateTime deadline, String? note) onSubmit;

  @override
  State<_RespondDialog> createState() => _RespondDialogState();
}

class _RespondDialogState extends State<_RespondDialog> {
  late DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  final _note = TextEditingController();
  bool _submitting = false;

  /// Raccourci actuellement sélectionné (null = date/heure personnalisée).
  int? _selectedQuick;

  static const _quickDelays = [
    ('2 H', 2),
    ('4 H', 4),
    ('24 H', 24),
    ('48 H', 48),
    ('7 J', 168),
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _deadline = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _deadline.hour,
          _deadline.minute,
        ),
      );
      _clearQuickSelection();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (picked != null) {
      setState(
        () => _deadline = DateTime(
          _deadline.year,
          _deadline.month,
          _deadline.day,
          picked.hour,
          picked.minute,
        ),
      );
      _clearQuickSelection();
    }
  }

  /// Retire le surlignage du raccourci quand la date/heure est personnalisée.
  void _clearQuickSelection() {
    if (_selectedQuick != null) {
      setState(() => _selectedQuick = null);
    }
  }

  String get _deadlineLabel {
    final d = _deadline;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
        '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Répondre au signalement',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.ticket.title,
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DÉLAI D\'INTERVENTION',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.onSurfaceFaint,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, hours) in _quickDelays)
                  _quickChip(label, hours),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: _deadlineLabel.split(' à ')[0],
                    icon: Icons.calendar_today_outlined,
                    height: 42,
                    color: _selectedQuick == null
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GhostButton(
                    label: _deadlineLabel.split(' à ')[1],
                    icon: Icons.schedule_outlined,
                    height: 42,
                    color: _selectedQuick == null
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _deadlineLabel,
                style: monoStyle(
                  11,
                  weight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Message pour le client (optionnel)',
                hintStyle: TextStyle(
                  color: AppColors.onSurfaceFaint,
                  fontSize: 13.5,
                ),
                filled: true,
                fillColor: AppColors.surfaceLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.outline),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        PrimaryButton(
          label: _submitting ? 'Envoi…' : 'Confirmer',
          icon: Icons.send_outlined,
          height: 42,
          onTap: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  await widget.onSubmit(
                    _deadline,
                    _note.text.trim().isEmpty ? null : _note.text.trim(),
                  );
                },
        ),
      ],
    );
  }

  Widget _quickChip(String label, int hours) {
    final selected = _selectedQuick == hours;
    return GestureDetector(
      onTap: () => setState(() {
        _deadline = DateTime.now().add(Duration(hours: hours));
        _selectedQuick = hours;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryDim : AppColors.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: monoStyle(
            11,
            weight: selected ? FontWeight.w800 : FontWeight.w700,
            color: selected ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final SupportAlert alert;

  @override
  Widget build(BuildContext context) {
    return WhiteCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.secondaryContainer,
            ),
            child: Icon(alert.icon, size: 19, color: AppColors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      alert.time,
                      style: monoStyle(
                        9.5,
                        letterSpacing: 0.5,
                        color: AppColors.onSurfaceFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  alert.message,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.onSurfaceVariant,
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

class _IncidentForm extends StatefulWidget {
  const _IncidentForm({
    required this.equipment,
    required this.photoAttached,
    required this.onPhoto,
    required this.onSubmit,
  });

  final List<Equipment> equipment;
  final bool photoAttached;
  final ValueChanged<ImageSource> onPhoto;
  final Future<void> Function(
    String type,
    String equipmentId,
    String description,
    bool photoAttached,
  )
  onSubmit;

  @override
  State<_IncidentForm> createState() => _IncidentFormState();
}

class _IncidentFormState extends State<_IncidentForm> {
  final _formKey = GlobalKey<FormState>();
  String? _type;
  String? _equipment;
  final _description = TextEditingController();
  bool _submitting = false;

  static const _types = [
    'Écran noir / perte d\'image',
    'Caméra déplacée',
    'Câble détérioré',
    'Problème d\'enregistrement',
    'Autre',
  ];

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
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
              const SizedBox(height: 18),
              Text(
                'Signaler un incident',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Décrivez le problème, votre installateur prend le relais.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: _inputDecoration('Type d\'incident'),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t, style: const TextStyle(fontSize: 14)),
                    ),
                ],
                validator: (v) => v == null ? 'Sélectionnez un type' : null,
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _equipment,
                decoration: _inputDecoration('Équipement concerné'),
                items: [
                  for (final e in widget.equipment)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.id} · ${e.name}',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                validator: (v) =>
                    v == null ? 'Sélectionnez un équipement' : null,
                onChanged: (v) => setState(() => _equipment = v),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: _inputDecoration('Description du problème'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Décrivez le problème'
                    : null,
              ),
              const SizedBox(height: 14),
              if (widget.photoAttached)
                GhostButton(
                  label: 'Photo jointe ✓',
                  icon: Icons.check_circle_outline,
                  color: AppColors.tertiary,
                  expanded: true,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'Caméra',
                        icon: Icons.photo_camera_outlined,
                        color: AppColors.primary,
                        onTap: () => widget.onPhoto(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GhostButton(
                        label: 'Galerie',
                        icon: Icons.photo_library_outlined,
                        color: AppColors.secondary,
                        onTap: () => widget.onPhoto(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: _submitting ? 'Envoi en cours…' : 'Envoyer la demande',
                icon: Icons.send_outlined,
                expanded: true,
                onTap: _submitting
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _submitting = true);
                        await widget.onSubmit(
                          _type!,
                          _equipment!,
                          _description.text.trim(),
                          widget.photoAttached,
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.onSurfaceFaint, fontSize: 14),
      filled: true,
      fillColor: AppColors.surfaceLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}
