import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// Notifications push FCM.
///
/// - Demande la permission (Android 13+)
/// - Enregistre le token de l'appareil dans `profiles.fcm_token`
/// - Affiche les notifications reçues au premier plan (canal local)
/// - Gère le fond via [FirebaseMessaging.onBackgroundMessage]
///
/// Degrade silencieusement si Firebase n'est pas configuré
/// (google-services.json absent) : l'app fonctionne sans push.
class PushService {
  PushService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'eyesafe_push',
    'Notifications EyeSafe',
    description: 'Signalements, alertes et interventions',
    importance: Importance.high,
  );

  /// Handler d'arrière-plan — doit être une fonction top-level.
  @pragma('vm:entry-point')
  static Future<void> onBackgroundMessage(RemoteMessage message) async {
    await Firebase.initializeApp();
    debugPrint('PushService (background): ${message.notification?.title}');
  }

  /// À appeler après [Supabase.initialize] quand le backend est configuré.
  static Future<void> init() async {
    if (!AppConfig.isBackendConfigured) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      // google-services.json absent ou Firebase indisponible :
      // l'app continue sans push.
      debugPrint('PushService: Firebase indisponible ($e)');
      return;
    }

    final messaging = FirebaseMessaging.instance;

    // Permission (Android 13+, iOS)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Canal local pour l'affichage au premier plan.
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    // Token initial + renouvellements → enregistrés sur le profil.
    _saveToken(await messaging.getToken());
    messaging.onTokenRefresh.listen(_saveToken);

    // Premier plan : afficher la notification localement.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'eyesafe_push',
            'Notifications EyeSafe',
            channelDescription: 'Signalements, alertes et interventions',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });

    // Fond / retour au premier plan.
    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);

    // À chaque changement de session, ré-enregistrer le token
    // (le profil est propre à l'utilisateur connecté).
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      final token = messaging.getToken();
      token.then(_saveToken);
    });
  }

  static Future<void> _saveToken(String? token) async {
    if (token == null) return;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await client.from('profiles').update({'fcm_token': token}).eq('id', uid);
    } catch (e) {
      debugPrint('PushService: enregistrement token impossible ($e)');
    }
  }
}
