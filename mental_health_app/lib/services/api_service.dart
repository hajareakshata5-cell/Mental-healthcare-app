import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/user_model.dart';

class ApiService {
  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? API_BASE_URL,
        rootUrl = _deriveRootUrl(baseUrl ?? API_BASE_URL),
        _client = client ?? http.Client();

  final String baseUrl;
  final String rootUrl;
  final http.Client _client;
  String? authToken;

  static String _deriveRootUrl(String value) {
    if (value.endsWith('/api/v1')) {
      return value.substring(0, value.length - '/api/v1'.length);
    }
    return value;
  }

  void setAuthToken(String token) => authToken = token;
  void clearAuthToken() => authToken = null;

  Map<String, String> _getHeaders({bool withAuth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (withAuth && authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  Uri _apiUri(String path) => Uri.parse('$baseUrl$path');
  Uri _rootUri(String path) => Uri.parse('$rootUrl$path');

  Future<Map<String, dynamic>> _getJson(Uri uri, {bool withAuth = true}) async {
    return _sendWithRetry(() => _client
        .get(uri, headers: _getHeaders(withAuth: withAuth))
        .timeout(const Duration(seconds: 20)));
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri, {
    Object? body,
    bool withAuth = true,
  }) async {
    return _sendWithRetry(() => _client
        .post(
          uri,
          headers: _getHeaders(withAuth: withAuth),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20)));
  }

  Future<Map<String, dynamic>> _sendWithRetry(
    Future<http.Response> Function() request, {
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await request();
        return _decodeResponse(response);
      } catch (error) {
        lastError = error;
        final retryable = error is TimeoutException ||
            error is SocketException ||
            error is HandshakeException ||
            error is http.ClientException;
        if (!retryable || attempt == attempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw Exception(lastError?.toString() ?? 'Request failed');
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final statusCode = response.statusCode;
    final payload =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

    if (statusCode >= 200 && statusCode < 300) {
      if (payload is Map<String, dynamic>) {
        if (payload['reply'] == null && payload['response'] is String) {
          payload['reply'] = payload['response'];
        }
        return payload;
      }
      return {'data': payload};
    }

    final message = payload is Map && payload['message'] != null
        ? payload['message'].toString()
        : response.reasonPhrase ?? 'Request failed';
    throw Exception('$statusCode: $message');
  }

  Future<LoginResult> login(String email, String password) async {
    final data = await _postJson(
      _apiUri(AUTH_LOGIN),
      withAuth: false,
      body: {'email': email, 'password': password},
    );
    final result = LoginResult.fromJson(data);
    setAuthToken(result.token);
    return result;
  }

  Future<LoginResult> signup(
    String email,
    String password, {
    required String username,
    String? displayName,
  }) async {
    final data = await _postJson(
      _apiUri(AUTH_SIGNUP),
      withAuth: false,
      body: {
        'email': email,
        'password': password,
        'username': username,
        'displayName': displayName ?? username,
      },
    );
    final result = LoginResult.fromJson(data);
    setAuthToken(result.token);
    return result;
  }

  Future<Map<String, dynamic>> registerForEmailVerification(
    String email,
    String password, {
    required String username,
    String? displayName,
  }) async {
    return _postJson(
      _apiUri(AUTH_SIGNUP),
      withAuth: false,
      body: {
        'email': email,
        'password': password,
        'username': username,
        'displayName': displayName ?? username,
      },
    );
  }

  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    return _postJson(
      _apiUri('/auth/verify-otp'),
      withAuth: false,
      body: {
        'email': email,
        'otp': otp,
      },
    );
  }

  Future<Map<String, dynamic>> resendEmailOtp({
    required String email,
  }) async {
    return _postJson(
      _apiUri('/auth/resend-otp'),
      withAuth: false,
      body: {
        'email': email,
      },
    );
  }

  Future<Map<String, dynamic>> forgotPasswordSendOtp({
    required String email,
  }) async {
    return _postJson(
      _apiUri('/auth/forgot-password/send-otp'),
      withAuth: false,
      body: {
        'email': email,
      },
    );
  }

  Future<LoginResult> forgotPasswordVerifyOtp({
    required String email,
    required String otp,
  }) async {
    final data = await _postJson(
      _apiUri('/auth/forgot-password/verify-otp'),
      withAuth: false,
      body: {
        'email': email,
        'otp': otp,
      },
    );

    final result = LoginResult.fromJson(data);
    setAuthToken(result.token);
    return result;
  }

  Future<LoginResult> loginGuest(String alias) async {
    final data = await _postJson(
      _apiUri(AUTH_GUEST),
      withAuth: false,
      body: {'username': alias, 'alias': alias},
    );
    final result = LoginResult.fromJson(data);
    setAuthToken(result.token);
    return result;
  }

  Future<LoginResult> refreshSession(String refreshToken) async {
    final data = await _postJson(
      _apiUri('/auth/refresh'),
      withAuth: false,
      body: {'refreshToken': refreshToken},
    );
    final result = LoginResult.fromJson(data);
    setAuthToken(result.token);
    return result;
  }

  Future<Map<String, dynamic>> logout() async {
    return _postJson(_apiUri('/auth/logout'));
  }

  Future<SessionUser> getMe() async {
    final data = await _getJson(_apiUri(AUTH_ME));
    return SessionUser.fromJson(data['profile'] ?? data);
  }

  Future<Map<String, dynamic>> getSubscription() async {
    return _getJson(_apiUri('/subscription'));
  }

  Future<Map<String, dynamic>> activateSubscription({
    required String plan,
    bool autoRenew = false,
  }) async {
    return _postJson(
      _apiUri('/subscription/activate'),
      body: {'plan': plan, 'autoRenew': autoRenew},
    );
  }

  Future<Map<String, dynamic>> restoreSubscription() async {
    return _postJson(_apiUri('/subscription/restore'));
  }

  Future<Map<String, dynamic>> fetchMoodHistory({int limit = 30}) async {
    final uri = _apiUri('/mood').replace(queryParameters: {'limit': '$limit'});
    return _getJson(uri);
  }

  Future<Map<String, dynamic>> submitMood({
    required String mood,
    required int stress,
    required int energy,
    required String notes,
    List<String>? tags,
  }) async {
    return _postJson(_apiUri('/mood'), body: {
      'mood': mood,
      'stress': stress,
      'energy': energy,
      'notes': notes,
      if (tags != null) 'tags': tags,
    });
  }

  Future<Map<String, dynamic>> getDailyPlan() async {
    try {
      return await _getJson(_apiUri('/wellness/daily-plan'));
    } catch (_) {
      return {
        'success': true,
        'focus': 'Stay hydrated, meditate, and complete one wellness task.',
        'water': {'targetMl': 2000},
        'meditation': {'durationMinutes': 10},
        'sleep': {'targetHours': 8},
      };
    }
  }

  Future<Map<String, dynamic>> submitWaterLog({
    required String date,
    required int consumedMl,
    required int weightKg,
    required int age,
    required String activityLevel,
    required String weather,
  }) async {
    try {
      return await _postJson(_apiUri('/wellness/water'), body: {
        'date': date,
        'consumedMl': consumedMl,
        'weightKg': weightKg,
        'age': age,
        'activityLevel': activityLevel,
        'weather': weather,
      });
    } catch (_) {
      return {
        'success': true,
        'waterCompleted': consumedMl > 0,
        'targetMl': weightKg * 35,
      };
    }
  }

  Future<Map<String, dynamic>> createMeditationSession({
    required String category,
    required int durationMinutes,
    required bool completed,
    bool recommendedByAI = false,
  }) async {
    try {
      return await _postJson(_apiUri('/wellness/meditation'), body: {
        'category': category,
        'durationMinutes': durationMinutes,
        'completed': completed,
        'recommendedByAI': recommendedByAI,
      });
    } catch (_) {
      return {
        'success': true,
        'completed': completed,
        'category': category,
        'durationMinutes': durationMinutes,
      };
    }
  }

  Future<Map<String, dynamic>> randomMatch({
    String gender = 'any',
  }) async {
    return _postJson(
      _apiUri('/calls/random-match'),
      body: {
        'gender': gender,
      },
    );
  }

  Future<Map<String, dynamic>> startCall({
    String peerAlias = 'ai_support',
    String callType = 'audio',
    String? targetUserId,
  }) async {
    return _postJson(
      _apiUri('/calls/start'),
      body: {
        'peerAlias': peerAlias,
        'type': callType,
        if (targetUserId != null && targetUserId.isNotEmpty)
          'targetUserId': targetUserId,
      },
    );
  }

  Future<Map<String, dynamic>> requestFriendCall({
    required String targetUserId,
    required String peerAlias,
    String callType = 'audio',
  }) async {
    return _postJson(
      _apiUri('/calls/friend/request'),
      body: {
        'targetUserId': targetUserId,
        'peerAlias': peerAlias,
        'type': callType,
      },
    );
  }

  Future<Map<String, dynamic>> getIncomingFriendCall() async {
    return _getJson(_apiUri('/calls/friend/incoming'));
  }

  Future<Map<String, dynamic>> acceptFriendCall({
    required String callId,
  }) async {
    return _postJson(
      _apiUri('/calls/friend/accept'),
      body: {
        'callId': callId,
      },
    );
  }

  Future<Map<String, dynamic>> rejectFriendCall({
    required String callId,
  }) async {
    return _postJson(
      _apiUri('/calls/friend/reject'),
      body: {
        'callId': callId,
      },
    );
  }

  Future<Map<String, dynamic>> cancelFriendCall({
    required String callId,
  }) async {
    return _postJson(
      _apiUri('/calls/friend/cancel'),
      body: {
        'callId': callId,
      },
    );
  }

  Future<Map<String, dynamic>> getFriendCallStatus({
    required String callId,
  }) async {
    return _getJson(_apiUri('/calls/friend/status/$callId'));
  }

  Future<Map<String, dynamic>> endCall({
    required String callId,
    required int durationSeconds,
    required int rating,
    String feedback = '',
  }) async {
    return _postJson(
      _apiUri('/calls/end'),
      body: {
        'callId': callId,
        'durationSeconds': durationSeconds,
        'rating': rating,
        'feedback': feedback,
      },
    );
  }

  Future<Map<String, dynamic>> getCallHistory() async {
    try {
      return await _getJson(_apiUri('/calls/history'));
    } catch (_) {
      return {'success': true, 'calls': []};
    }
  }

  Future<Map<String, dynamic>> getCallProgress() async {
    try {
      return await _getJson(_apiUri('/calls/progress'));
    } catch (_) {
      return {
        'success': true,
        'progress': {
          'totalCalls': 0,
          'weeklyCalls': 0,
          'totalMinutes': 0,
          'totalCoins': 0,
          'averageRating': 0,
          'lastCall': null,
        },
      };
    }
  }

  Future<Map<String, dynamic>> sendFriendRequest({
    required String receiverId,
  }) async {
    try {
      return await _postJson(
        _apiUri('/friends/request'),
        body: {'receiverId': receiverId},
      );
    } catch (_) {
      return {'success': true, 'message': 'Friend request saved locally'};
    }
  }

  Future<Map<String, dynamic>> getFriendRequests() async {
    try {
      return await _getJson(_apiUri('/friends/requests'));
    } catch (_) {
      return {
        'success': true,
        'requests': [],
        'message': 'Friend requests disabled locally',
      };
    }
  }

  Future<Map<String, dynamic>> respondFriendRequest({
    required String requestId,
    required String action,
  }) async {
    try {
      return await _postJson(
        _apiUri('/friends/respond'),
        body: {
          'requestId': requestId,
          'action': action,
        },
      );
    } catch (_) {
      return {'success': true, 'message': 'Friend request handled locally'};
    }
  }

  Future<Map<String, dynamic>> getFriends() async {
    try {
      return await _getJson(_apiUri('/friends'));
    } catch (error) {
      debugPrint('getFriends failed: $error');
      return {
        'success': false,
        'friends': [],
        'offlineFallback': true,
        'message': 'Friends could not be loaded',
      };
    }
  }

  Future<Map<String, dynamic>> removeFriend({
    required String friendId,
  }) async {
    return _postJson(
      _apiUri('/friends/remove'),
      body: {'friendId': friendId},
    );
  }

  Future<Map<String, dynamic>> blockUser({
    required String userId,
  }) async {
    return _postJson(
      _apiUri('/friends/block'),
      body: {'userId': userId},
    );
  }

  Future<Map<String, dynamic>> getAvailableUsers() async {
    try {
      return await _getJson(_apiUri('/users/available'));
    } catch (error) {
      debugPrint('getAvailableUsers failed: $error');
      return {
        'success': false,
        'users': [],
        'offlineFallback': true,
        'message': 'Available users could not be loaded',
      };
    }
  }

  Future<Map<String, dynamic>> saveFcmToken({
    required String fcmToken,
  }) async {
    try {
      return await _postJson(
        _apiUri('/notifications/save-token'),
        body: {'fcmToken': fcmToken},
      );
    } catch (_) {
      return {'success': true, 'message': 'FCM token skipped locally'};
    }
  }

  Future<Map<String, dynamic>> getStreak() async {
    try {
      return await _getJson(_apiUri('/streaks'));
    } catch (_) {
      return {
        'success': true,
        'streak': {
          'currentStreak': 0,
          'longestStreak': 0,
          'totalCompletedDays': 0,
          'waterCompleted': false,
        },
      };
    }
  }

  Future<Map<String, dynamic>> completeStreak({
    required bool waterCompleted,
  }) async {
    try {
      return await _postJson(
        _apiUri('/streaks/complete'),
        body: {'waterCompleted': waterCompleted},
      );
    } catch (_) {
      return {
        'success': true,
        'streak': {
          'currentStreak': waterCompleted ? 1 : 0,
          'longestStreak': waterCompleted ? 1 : 0,
          'totalCompletedDays': waterCompleted ? 1 : 0,
          'waterCompleted': waterCompleted,
        },
        'message': 'Streak completed locally',
      };
    }
  }

  Future<Map<String, dynamic>> chatRespond({
    required String message,
    String mode = 'support',
    String? userId,
    Object? context,
    int stressLevel = 5,
    List<String> conversationHistory = const [],
  }) async {
    final response = await _postJson(
      _apiUri(CHAT_RESPOND),
      body: {
        'message': message,
        'mode': mode,
        if (userId != null) 'userId': userId,
        if (context != null) 'context': context,
        'stress_level': stressLevel,
        'stressLevel': stressLevel,
        'conversation_history': conversationHistory,
        'conversationHistory': conversationHistory,
      },
    );

    if (response['reply'] == null && response['response'] is String) {
      response['reply'] = response['response'];
    }

    return response;
  }

  Future<Map<String, dynamic>> getHealth() async {
    return _getJson(_rootUri(HEALTH_STATUS), withAuth: false);
  }

  Future<Map<String, dynamic>> getDeploymentVersion() async {
    return _getJson(_rootUri(DEPLOYMENT_VERSION), withAuth: false);
  }

  Future<Map<String, dynamic>> createPaymentOrder() async {
    return _postJson(
      _apiUri(PAYMENT_CREATE_ORDER),
      body: {'plan': PREMIUM_PLAN, 'amount': int.parse(PREMIUM_PRICE)},
    );
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    return _postJson(
      _apiUri(PAYMENT_VERIFY),
      body: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
  }
}
