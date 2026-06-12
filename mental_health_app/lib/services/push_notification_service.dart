// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../screens/agora_voice_call_screen.dart';
import 'api_service.dart';
import 'incoming_call_service.dart';
import 'mindcare_callkit_service.dart';

class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _callkitListenerAttached = false;
  String? _lastAcceptedCallkitCallId;
  String? _lastRejectedCallkitCallId;
  final FlutterSecureStorage _callkitSecureStorage =
      const FlutterSecureStorage();
  static const String _pendingCallkitCallKey = 'mindcare_pending_callkit_call';
  AppLifecycleListener? _callLifecycleListener;

  Future<void> initialize({
    BuildContext? context,
    ApiService? apiService,
  }) async {
    if (_initialized) return;
    _initialized = true;

    await _initializeLocalNotifications();

    await MindCareCallkitService.requestCallkitPermissionsIfPossible();

    _attachCallkitEventListener(apiService: apiService);
    await _handlePendingCallkitCalls(apiService: apiService);
    await _handleStoredPendingCallkitCall(apiService: apiService);

    _callLifecycleListener ??= AppLifecycleListener(
      onResume: () {
        _handlePendingCallkitCalls(apiService: apiService);
        _handleStoredPendingCallkitCall(apiService: apiService);
      },
    );

    await _ensureIncomingCallChannel();

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
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
        apiService: apiService,
        source: 'foreground',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleIncomingMessage(
        message,
        apiService: apiService,
        source: 'opened_app',
      );
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 700), () {
        _handleIncomingMessage(
          initialMessage,
          apiService: apiService,
          source: 'initial_message',
        );
      });
    }
  }

  void _handleIncomingMessage(
    RemoteMessage message, {
    required ApiService? apiService,
    required String source,
  }) {
    final data = message.data;
    final type = data['type']?.toString();

    debugPrint('FCM MESSAGE source=$source type=$type data=$data');

    if (type != 'incoming_call') {
      debugPrint('FCM ignored: unsupported type=$type');
      return;
    }

    final navContext = mindCareNavigatorKey.currentContext;
    if (navContext == null) {
      debugPrint('FCM incoming call ignored: navigator context missing');
      return;
    }

    MindCareCallkitService.showIncomingCallFromData(data).catchError((error) {
      debugPrint('CALLKIT foreground/opened incoming failed: $error');
    });

    debugPrint('CALLKIT foreground/opened incoming');

    IncomingCallService.showIncomingCall(
      context: navContext,
      apiService: apiService,
      callId: data['callId']?.toString(),
      callerName: data['callerName']?.toString() ?? 'MindCare user',
      channelName: data['channelName']?.toString() ?? '',
      token: data['agoraToken']?.toString() ?? '',
      uid: int.tryParse(data['agoraUid']?.toString() ?? '') ?? 0,
    );
  }

  Future<String?> getToken() async {
    return _messaging.getToken();
  }

  void _attachCallkitEventListener({required ApiService? apiService}) {
    if (_callkitListenerAttached) return;
    _callkitListenerAttached = true;

    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      debugPrint('CALLKIT_EVENT: $event');

      if (event is CallEventActionCallAccept) {
        await _acceptCallkitIncomingCall(
          callId: event.id,
          apiService: apiService,
        );
        return;
      }

      if (event is CallEventActionCallDecline) {
        await _rejectCallkitIncomingCall(
          callId: event.id,
          apiService: apiService,
          reason: 'decline',
        );
        return;
      }

      if (event is CallEventActionCallTimeout) {
        await _rejectCallkitIncomingCall(
          callId: event.id,
          apiService: apiService,
          reason: 'timeout',
        );
        return;
      }
    });
  }

  Future<void> _handleStoredPendingCallkitCall({
    required ApiService? apiService,
  }) async {
    try {
      final raw = await _callkitSecureStorage.read(key: _pendingCallkitCallKey);
      debugPrint(
          'CALLKIT_STORED_PENDING_RAW: ${raw == null ? 'null' : 'present'}');

      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _callkitSecureStorage.delete(key: _pendingCallkitCallKey);
        return;
      }

      final data = Map<String, dynamic>.from(decoded);
      final type = data['type']?.toString() ?? '';
      final callId = data['callId']?.toString() ?? '';

      if (type != 'incoming_call' || callId.isEmpty) {
        await _callkitSecureStorage.delete(key: _pendingCallkitCallKey);
        return;
      }

      debugPrint('CALLKIT_STORED_PENDING_ACCEPT_TRY callId=$callId');
      await _acceptCallkitIncomingCall(
        callId: callId,
        apiService: apiService,
      );
    } catch (error) {
      debugPrint('CALLKIT_STORED_PENDING_FAILED: $error');
    }
  }

  Future<void> _handlePendingCallkitCalls({
    required ApiService? apiService,
  }) async {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      debugPrint('CALLKIT_PENDING_ACTIVE_CALLS: $activeCalls');

      if (activeCalls.isEmpty) {
        return;
      }

      for (final item in activeCalls) {
        final id = item.id.toString();
        final extraRaw = item.extra;

        final extra = extraRaw ?? <String, dynamic>{};

        final type = extra['type']?.toString() ?? '';
        final callId = extra['callId']?.toString() ?? id;

        if (callId.isEmpty) continue;

        if (type == 'incoming_call' || id.isNotEmpty) {
          debugPrint('CALLKIT_PENDING_ACCEPT_TRY callId=$callId type=$type');
          await _acceptCallkitIncomingCall(
            callId: callId,
            apiService: apiService,
          );
          return;
        }
      }
    } catch (error) {
      debugPrint('CALLKIT_PENDING_CHECK_FAILED: $error');
    }
  }

  Future<bool> _restoreCallkitAuthToken(ApiService apiService) async {
    final existingToken = apiService.authToken;
    if (existingToken != null && existingToken.isNotEmpty) {
      return true;
    }

    final storedToken =
        await _callkitSecureStorage.read(key: 'mindcare_session_token');

    if (storedToken == null || storedToken.isEmpty) {
      debugPrint('CALLKIT_AUTH_MISSING: no saved session token');
      return false;
    }

    apiService.setAuthToken(storedToken);
    debugPrint('CALLKIT_AUTH_RESTORED');
    return true;
  }

  Future<void> _acceptCallkitIncomingCall({
    required String callId,
    required ApiService? apiService,
  }) async {
    final safeCallId = callId.trim();
    if (safeCallId.isEmpty) return;

    if (_lastAcceptedCallkitCallId == safeCallId) {
      debugPrint('CALLKIT_ACCEPT skipped duplicate callId=$safeCallId');
      return;
    }
    _lastAcceptedCallkitCallId = safeCallId;

    if (apiService == null) {
      debugPrint('CALLKIT_ACCEPT failed: apiService missing');
      return;
    }

    try {
      final hasAuth = await _restoreCallkitAuthToken(apiService);
      debugPrint('CALLKIT_ACCEPT_AUTH_RESTORED_CHECK: $hasAuth');
      if (!hasAuth) return;

      final response = await apiService.acceptFriendCall(callId: safeCallId);
      await _callkitSecureStorage.delete(key: _pendingCallkitCallKey);
      debugPrint('CALLKIT_PENDING_CLEARED_AFTER_ACCEPT callId=$safeCallId');

      try {
        await FlutterCallkitIncoming.endCall(safeCallId);
      } catch (endNativeError) {
        debugPrint('CALLKIT_NATIVE_END_AFTER_ACCEPT_FAILED: $endNativeError');
      }
      final call = response['call'] as Map<String, dynamic>?;

      final freshCallId = call?['id']?.toString() ?? safeCallId;
      final freshChannelName = call?['channelName']?.toString() ?? '';
      final freshToken = call?['agoraToken']?.toString() ?? '';
      final freshUid = int.tryParse(call?['agoraUid']?.toString() ?? '') ?? 0;
      final peerName = call?['peerName']?.toString() ?? 'MindCare user';

      if (freshChannelName.trim().isEmpty) {
        throw Exception('Missing channel');
      }

      if (freshToken.trim().isEmpty) {
        throw Exception('Missing Agora token');
      }

      if (freshUid <= 0) {
        throw Exception('Invalid Agora uid');
      }

      final navContext = mindCareNavigatorKey.currentContext;
      if (navContext == null) {
        debugPrint('CALLKIT_ACCEPT delayed: navigator context missing');
        return;
      }

      Navigator.of(navContext).push(
        MaterialPageRoute(
          builder: (_) => AgoraVoiceCallScreen(
            apiService: apiService,
            callId: freshCallId,
            channelName: freshChannelName,
            token: freshToken,
            uid: freshUid,
            peerName: peerName,
          ),
        ),
      );

      debugPrint('CALLKIT_ACCEPT_OK callId=$freshCallId');
    } catch (error) {
      _lastAcceptedCallkitCallId = null;
      debugPrint('CALLKIT_ACCEPT_FAILED: $error');
    }
  }

  Future<void> _rejectCallkitIncomingCall({
    required String callId,
    required ApiService? apiService,
    required String reason,
  }) async {
    final safeCallId = callId.trim();
    if (safeCallId.isEmpty) return;

    if (_lastRejectedCallkitCallId == safeCallId) {
      debugPrint('CALLKIT_REJECT skipped duplicate callId=$safeCallId');
      return;
    }
    _lastRejectedCallkitCallId = safeCallId;

    if (apiService == null) {
      debugPrint('CALLKIT_REJECT failed: apiService missing reason=$reason');
      return;
    }

    try {
      final hasAuth = await _restoreCallkitAuthToken(apiService);
      debugPrint('CALLKIT_REJECT_AUTH_RESTORED_CHECK: $hasAuth');
      if (!hasAuth) return;

      await apiService.rejectFriendCall(callId: safeCallId);
      debugPrint('CALLKIT_REJECT_OK callId=$safeCallId reason=$reason');
    } catch (error) {
      debugPrint('CALLKIT_REJECT_FAILED: $error');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(settings: settings);
  }

  Future<void> _ensureIncomingCallChannel() async {
    const channel = AndroidNotificationChannel(
      'incoming_calls',
      'Incoming MindCare Calls',
      description: 'Notifications for incoming MindCare friend calls',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
  }
}
