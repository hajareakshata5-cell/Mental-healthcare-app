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

    if (token != null && token.isNotEmpty && apiService != null) {
      try {
        await apiService.saveFcmToken(fcmToken: token);
        debugPrint('FCM token saved to backend');
      } catch (error) {
        debugPrint('FCM token save failed: $error');
      }
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('FCM TOKEN REFRESHED: $newToken');

      if (newToken.isNotEmpty && apiService != null) {
        try {
          await apiService.saveFcmToken(fcmToken: newToken);
          debugPrint('Refreshed FCM token saved to backend');
        } catch (error) {
          debugPrint('Refreshed FCM token save failed: $error');
        }
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleIncomingMessage(
        message,
        context: context,
        apiService: apiService,
        source: 'foreground',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleIncomingMessage(
        message,
        context: context,
        apiService: apiService,
        source: 'opened_app',
      );
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleIncomingMessage(
        initialMessage,
        context: context,
        apiService: apiService,
        source: 'initial_message',
      );
    }
  }

  void _handleIncomingMessage(
    RemoteMessage message, {
    required BuildContext? context,
    required ApiService? apiService,
    required String source,
  }) {
    final data = message.data;
    final type = data['type']?.toString();

    debugPrint('FCM MESSAGE source=$source type=$type data=$data');

    if (type == 'incoming_call' && context != null) {
      IncomingCallService.showIncomingCall(
        context: context,
        apiService: apiService,
        callId: data['callId']?.toString(),
        callerName: data['callerName']?.toString() ?? 'MindCare user',
        channelName: data['channelName']?.toString() ?? '',
        token: data['agoraToken']?.toString() ?? '',
        uid: int.tryParse(data['agoraUid']?.toString() ?? '') ?? 0,
      );
      return;
    }

    debugPrint(
        'Notification ignored or context missing: ${message.notification?.title}');
  }

  Future<String?> getToken() async {
    return _messaging.getToken();
  }
}
