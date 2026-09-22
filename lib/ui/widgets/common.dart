import 'package:flutter/material.dart';

import '../theme.dart';

class WhiteCard extends StatefulWidget {
  const WhiteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 16,
    this.margin,
    this.onTap,
  });

  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<WhiteCard> createState() => _WhiteCardState();
}

class _WhiteCardState extends State<WhiteCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      margin: widget.margin,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: _hover
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.outlineVariant,
        ),
        boxShadow: [
          _hover
              ? BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                )
              : BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
        ],
      ),
      child: widget.child,
    );

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.onTap != null
          ? GestureDetector(onTap: widget.onTap, child: card)
          : card,
    );
  }
}

// ignore: prefer_const_constructors_in_immutables
class TechBadge extends StatelessWidget {
  const TechBadge(this.label, {super.key, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? AppColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (color ?? AppColors.primary).withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: monoStyle(
          10.5,
          weight: FontWeight.w600,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

// ignore: prefer_const_constructors_in_immutables
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.color,
    this.expanded = false,
    this.height = 46,
    this.uppercase = true,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool expanded;
  final double height;

  /// Les dialogues de confirmation gardent la casse naturelle
  /// (« Se déconnecter » au lieu de « SE DÉCONNECTER »).
  final bool uppercase;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hover = false;

  bool get _enabled => widget.onTap != null;

  Color get _fill => _hover && _enabled
      ? Color.lerp(widget.color ?? AppColors.primary, Colors.black, 0.12)!
      : widget.color ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _enabled
            ? [
                BoxShadow(
                  color: (widget.color ?? AppColors.primary).withValues(
                    alpha: _hover ? 0.4 : 0.28,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.uppercase ? widget.label.toUpperCase() : widget.label,
                style: monoStyle(
                  12.5,
                  weight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: _enabled ? 1 : 0.45,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: widget.expanded
              ? SizedBox(
                  width: double.infinity,
                  child: Center(child: content),
                )
              : content,
        ),
      ),
    );
  }
}

// ignore: prefer_const_constructors_in_immutables
class GhostButton extends StatefulWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.color,
    this.expanded = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool expanded;
  final double height;

  @override
  State<GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<GhostButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _hover
            ? (widget.color ?? AppColors.primary).withValues(alpha: 0.08)
            : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (widget.color ?? AppColors.primary).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 18,
              color: widget.color ?? AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label.toUpperCase(),
                style: monoStyle(
                  12.5,
                  weight: FontWeight.w600,
                  letterSpacing: 1,
                  color: widget.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.expanded
            ? SizedBox(
                width: double.infinity,
                child: Center(child: content),
              )
            : content,
      ),
    );
  }
}

class CircleIconButton extends StatefulWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.iconSize = 20,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  @override
  State<CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<CircleIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hover ? AppColors.primaryContainer : AppColors.card,
            border: Border.all(
              color: _hover
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.outline,
            ),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Confirmation avant déconnexion d'un équipement/caméra connecté.
/// Retourne true si l'utilisateur confirme.
Future<bool> confirmRemoveEquipment(
  BuildContext context, {
  required String name,
  String description =
      'Il sera retiré de votre installation. '
      'Vous pourrez le reconnecter à tout moment.',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Déconnecter ?',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: Text(
        '« $name » — $description',
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
          label: 'Déconnecter',
          icon: Icons.link_off_outlined,
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

/// En-tête de page adaptatif : titre + sous-titre à gauche, actions alignées
/// à droite sur écran large. Sur écran étroit, les actions passent sous le
/// texte pour ne jamais comprimer le titre (texte vertical) sur mobile.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (actions.isEmpty) return text;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: text),
              const SizedBox(width: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            text,
            const SizedBox(height: 20),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        );
      },
    );
  }
}
