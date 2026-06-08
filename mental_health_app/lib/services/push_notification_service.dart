import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'api_service.dart';

import 'incoming_call_service.dart';

class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize({
    BuildContext? context,
    ApiService? apiService,
  }) async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();

    debugPrint('FCM TOKEN: $token');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final type = data['type']?.toString();

      if (type == 'incoming_call' && context != null) {
        IncomingCallService.showIncomingCall(
          context: context,
          apiService: apiService,
          callId: data['callId']?.toString(),
          callerName: data['callerName']?.toString() ?? 'MindCare user',
          channelName: data['channelName']?.toString() ?? 'mindcare-call',
          token: data['agoraToken']?.toString() ?? '',
          uid: int.tryParse(data['agoraUid']?.toString() ?? '') ?? 0,
        );
      } else {
        debugPrint('Foreground notification: ${message.notification?.title}');
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification clicked');
    });
  }

  Future<String?> getToken() async {
    return _messaging.getToken();
  }
}
