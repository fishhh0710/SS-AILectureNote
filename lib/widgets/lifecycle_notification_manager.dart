import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class LifecycleNotificationManager extends StatefulWidget {
  final Widget child;
  final String title;
  final String body;
  final bool cleanOnResume;
  final bool enableDynamicContent;
  final String Function()? dynamicTitleBuilder;
  final String Function()? dynamicBodyBuilder;

  const LifecycleNotificationManager({
    super.key,
    required this.child,
    this.title = '您已離開 App',
    this.body = 'AI 教學助手仍在後台運作中',
    this.cleanOnResume = true,
    this.enableDynamicContent = false,
    this.dynamicTitleBuilder,
    this.dynamicBodyBuilder,
  });

  @override
  State<LifecycleNotificationManager> createState() => _LifecycleNotificationManagerState();
}

class _LifecycleNotificationManagerState extends State<LifecycleNotificationManager> with WidgetsBindingObserver {
  late FlutterLocalNotificationsPlugin _notificationsPlugin;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();

    // Android Initialization settings
    // @mipmap/ic_launcher is the standard flutter app launcher icon
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/Darwin Initialization settings
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );
      _initialized = true;
      
      // Request permission using permission_handler or native APIs
      await _requestPermissions();
    } catch (e) {
      debugPrint('LifecycleNotificationManager: Notification init failed: $e');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      // First try permission_handler for convenience and unified API
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }

      // Fallback or double-check with local notifications platform specific implementations
      final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      final iosImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint('LifecycleNotificationManager: Error requesting notification permissions: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_initialized) return;

    if (state == AppLifecycleState.paused) {
      // Triggered when user switches to another app or goes to home screen
      _showNotification();
    } else if (state == AppLifecycleState.resumed) {
      // Triggered when app comes back to foreground
      if (widget.cleanOnResume) {
        _cancelNotification();
      }
    }
  }

  Future<void> _showNotification() async {
    String currentTitle = widget.title;
    String currentBody = widget.body;

    if (widget.enableDynamicContent) {
      if (widget.dynamicTitleBuilder != null) {
        currentTitle = widget.dynamicTitleBuilder!();
      }
      if (widget.dynamicBodyBuilder != null) {
        currentBody = widget.dynamicBodyBuilder!();
      }
    }

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'lifecycle_notification_channel',
      'App Lifecycle Notifications',
      channelDescription: 'Notifications shown when the app goes into the background',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const DarwinNotificationDetails darwinNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: 888, // Constant ID to avoid multiple duplicate notifications stacked up
        title: currentTitle,
        body: currentBody,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('LifecycleNotificationManager: Failed to show notification: $e');
    }
  }

  Future<void> _cancelNotification() async {
    try {
      await _notificationsPlugin.cancel(id: 888);
    } catch (e) {
      debugPrint('LifecycleNotificationManager: Failed to cancel notification: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
