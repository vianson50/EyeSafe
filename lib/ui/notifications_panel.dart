import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/site_controller.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Ouvre le centre de notifications (cloche de l'en-tête).
///
/// [data] est fourni par l'appelant (le contexte de l'AppShell est situé
/// au-dessus du DataScope, il ne peut donc pas y lire le contrôleur).
Future<void> showNotificationsPanel(
  BuildContext context,
  SiteController data,
) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.85,
      minChildSize: 0.4,
      builder: (context, scrollController) =>
          _NotificationsPanel(data: data, scrollController: scrollController),
    ),
  );
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({
    required this.data,
    required this.scrollController,
  });

  final SiteController data;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final items = data.notifications;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                      if (data.unreadCount > 0)
                        GhostButton(
                          label: 'Tout marquer lu',
                          icon: Icons.done_all,
                          height: 38,
                          color: AppColors.tertiary,
                          onTap: () => data.markAllRead(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_outlined,
                            size: 42,
                            color: AppColors.onSurfaceFaint,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Aucune notification.\nVous serez prévenu dès qu\'un événement '
                            'concerne votre installation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _NotificationRow(
                        item: items[i],
                        onTap: () => data.markRead(items[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, this.onTap});

  final NotificationItem item;
  final VoidCallback? onTap;

  IconData get _icon => switch (item.type) {
    'ticket' => Icons.support_agent_outlined,
    'alert' => Icons.warning_amber_outlined,
    _ => Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final unread = item.isUnread;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: unread ? AppColors.primaryContainer : AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: unread
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: unread ? Colors.white : AppColors.surface,
                  ),
                  child: Icon(
                    _icon,
                    size: 19,
                    color: unread
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
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
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                              ),
                            ),
                        ],
                      ),
                      if (item.body?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.body!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        SiteController.relativeTimeLabel(item.createdAt),
                        style: monoStyle(
                          9.5,
                          letterSpacing: 1,
                          color: AppColors.onSurfaceFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
