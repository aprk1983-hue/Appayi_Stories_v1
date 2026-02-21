import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static const String topicNewStories = 'new_stories';

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<bool> requestPermissionIfNeeded() async {
    // iOS + Android 13+ need runtime permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> enableNewStoryNotifications() async {
    final ok = await requestPermissionIfNeeded();
    if (!ok) return;

    await _fcm.subscribeToTopic(topicNewStories);
  }

  Future<void> disableNewStoryNotifications() async {
    await _fcm.unsubscribeFromTopic(topicNewStories);
  }

  /// Call once at app start if you want to handle tap actions later.
  Future<void> initForegroundHandlers() async {
    // Optional: handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // You can show an in-app banner/snackbar if desired.
    });
  }
}
