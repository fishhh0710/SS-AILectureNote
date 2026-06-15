import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const distractionNotificationId = 889;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _fcmToken;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;

  Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    try {
      await _localNotifications.initialize(settings: settings);
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      final ios = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (error) {
      debugPrint('NotificationService: local initialization failed: $error');
    }

    if (_supportsFirebaseMessaging) {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        _fcmToken = await messaging.getToken();
        _tokenSubscription = messaging.onTokenRefresh.listen((token) {
          _fcmToken = token;
        });
        _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
          if (message.data['type'] == 'attention_distraction') {
            unawaited(
              showDistractionNotification(
                teacherPage: int.tryParse(message.data['teacherPage'] ?? ''),
              ),
            );
          }
        });
      } catch (error) {
        debugPrint('NotificationService: FCM initialization failed: $error');
      }
    }

    _initialized = true;
  }

  bool get _supportsFirebaseMessaging {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<String?> getToken() async {
    await initialize();
    return _fcmToken;
  }

  Future<void> showDistractionNotification({int? teacherPage}) async {
    await initialize();
    final pageText = teacherPage == null ? '' : '，老師目前正在講第 $teacherPage 頁';

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'attention_notification_channel',
        '課堂專注提醒',
        channelDescription: '只在 Attention Agent 判斷學生分心時顯示',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _localNotifications.show(
        id: distractionNotificationId,
        title: '課堂仍在進行',
        body: '你似乎暫時離開了課程$pageText。',
        notificationDetails: details,
        payload: 'attention_distraction',
      );
    } catch (error) {
      debugPrint('NotificationService: failed to show notification: $error');
    }
  }

  void dispose() {
    unawaited(_tokenSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
  }
}
