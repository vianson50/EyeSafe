import 'package:flutter/material.dart';

import '../data/site_controller.dart';

/// Expose le [SiteController] aux pages : toute page dépendante est
/// reconstruite quand les données changent (chargement ou temps réel).
class DataScope extends InheritedNotifier<SiteController> {
  const DataScope({
    super.key,
    required SiteController controller,
    required super.child,
  }) : super(notifier: controller);

  static SiteController of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DataScope>()!.notifier!;
}
