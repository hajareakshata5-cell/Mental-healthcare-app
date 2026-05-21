import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

const String _defaultBackendUrl =
    'https://name-mentalhealth-backend.onrender.com';

class ApiClient {
  ApiClient._privateConstructor() {
    baseUrl = _envBase.isNotEmpty ? _envBase : _defaultBackendUrl;

    aiBaseUrl = _envAiBase.isNotEmpty ? _envAiBase : _defaultBackendUrl;
  }
  static ApiClient _shared = ApiClient._privateConstructor();
  static ApiClient get instance => _shared;
  // Replaceable for testing
  static void replaceInstanceForTesting(ApiClient c) {
    _shared = c;
  }

  // Configure at build time with --dart-define=API_BASE_URL=https://api.example.com
  // Defaults are chosen based on platform to support emulators and simulators
  final String _envBase =
      const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final String _envAiBase =
      const String.fromEnvironment('AI_BASE_URL', defaultValue: '');

  // Will be initialized in the private constructor to avoid using `this` in
  // field initializers.
  late String baseUrl;
  late String aiBaseUrl;
  String? _jwt;
  // Allow injecting a custom http client for tests
  http.Client httpClient = http.Client();

  // Helpful debug logging for requests/responses
  void _logRequest(String method, Uri uri, Map<String, String> headers,
      [Object? body]) {
    debugPrint('[ApiClient] Request: $method ${uri.toString()}');
    debugPrint('[ApiClient] Headers: ${headers.toString()}');
    if (body != null) debugPrint('[ApiClient] Body: ${body.toString()}');
  }

  void _logResponse(http.Response r) {
    debugPrint('[ApiClient] Response: ${r.statusCode} ${r.request?.url}');
    try {
      if (r.body.isNotEmpty) debugPrint('[ApiClient] Response body: ${r.body}');
    } catch (_) {}
  }

  void setBaseUrl(String url) => baseUrl = url;
  void setAiBaseUrl(String url) => aiBaseUrl = url;
  void setJwt(String token) => _jwt = token;
  void clearAuth() => _jwt = null;

  Map<String, String> _defaultHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_jwt != null) headers['Authorization'] = 'Bearer $_jwt';
    return headers;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');
  Uri _aiUri(String path) => Uri.parse('$aiBaseUrl$path');

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? qs}) async {
    final uri = _uri(path);
    final headers = _defaultHeaders();
    _logRequest('GET', uri.replace(queryParameters: qs), headers);
    final r = await httpClient.get(uri.replace(queryParameters: qs),
        headers: headers);
    _logResponse(r);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final uri = _uri(path);
    final headers = _defaultHeaders();
    final bodyEncoded = body == null ? null : jsonEncode(body);
    _logRequest('POST', uri, headers, body);
    final r = await httpClient.post(uri, headers: headers, body: bodyEncoded);
    _logResponse(r);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> put(String path, {Object? body}) async {
    final uri = _uri(path);
    final headers = _defaultHeaders();
    final bodyEncoded = body == null ? null : jsonEncode(body);
    _logRequest('PUT', uri, headers, body);
    final r = await httpClient.put(uri, headers: headers, body: bodyEncoded);
    _logResponse(r);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> delete(String path, {Object? body}) async {
    final uri = _uri(path);
    final headers = _defaultHeaders();
    final bodyEncoded = body == null ? null : jsonEncode(body);
    _logRequest('DELETE', uri, headers, body);
    final r = await httpClient.delete(uri, headers: headers, body: bodyEncoded);
    _logResponse(r);
    return _handleResponse(r);
  }

  Future<Map<String, dynamic>> postAi(String path, {Object? body}) async {
    final uri = _aiUri(path);
    final headers = _defaultHeaders();
    final bodyEncoded = body == null ? null : jsonEncode(body);
    _logRequest('POST', uri, headers, body);
    final r = await httpClient.post(uri, headers: headers, body: bodyEncoded);
    _logResponse(r);
    return _handleResponse(r);
  }

  Map<String, dynamic> _handleResponse(http.Response r) {
    final status = r.statusCode;
    if (r.body.isEmpty) return {'status': status};
    final decoded = jsonDecode(r.body);
    if (status >= 200 && status < 300) return decoded as Map<String, dynamic>;
    // Try to provide helpful error shape
    final message = decoded is Map && decoded['message'] != null
        ? decoded['message']
        : r.reasonPhrase;
    throw ApiException(status, message?.toString() ?? 'Request failed');
  }

  // High-level helper API methods used by the app

  Future<String> registerGuest(String alias) async {
    final res = await post('/api/v1/auth/guest', body: {'username': alias});
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Guest login did not return a token');
    }
    setJwt(token);
    return token;
  }

  Future<String> loginEmail(String email, String password) async {
    final res = await post('/api/v1/auth/login',
        body: {'email': email, 'password': password});
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Login did not return a token');
    }
    setJwt(token);
    return token;
  }

  Future<String> registerEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    final res = await post('/api/v1/auth/register', body: {
      'email': email,
      'password': password,
      'username': username,
    });
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Registration did not return a token');
    }
    setJwt(token);
    return token;
  }

  Future<String> exchangeFirebaseToken(String idToken) async {
    final res = await post('/api/v1/auth/firebase', body: {'idToken': idToken});
    final token = res['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(500, 'Firebase sign-in did not return a token');
    }
    setJwt(token);
    return token;
  }

  Future<Map<String, dynamic>> fetchProfile() async {
    return await get('/api/v1/profile/me');
  }

  Future<Map<String, dynamic>> fetchMoodHistory({int limit = 30}) async {
    return await get('/api/v1/mood', qs: {'limit': '$limit'});
  }

  Future<Map<String, dynamic>> submitMood({
    required String mood,
    required int stress,
    required int energy,
    required String notes,
    List<String>? tags,
  }) async {
    return await post('/api/v1/mood', body: {
      'mood': mood,
      'stress': stress,
      'energy': energy,
      'notes': notes,
      if (tags != null) 'tags': tags,
    });
  }

  Future<Map<String, dynamic>> analyzeMoodText(String text) async {
    return await postAi('/api/v1/mood/analyze', body: {'text': text});
  }

  Future<Map<String, dynamic>> chatWithAi(
    String message, {
    int stressLevel = 5,
    String mode = 'support',
    String? userId,
    Object? context,
    List<String> conversationHistory = const [],
  }) async {
    final response = await postAi('/api/v1/chat/respond', body: {
      'message': message,
      'mode': mode,
      if (userId != null) 'userId': userId,
      if (context != null) 'context': context,
      'stress_level': stressLevel,
      'conversation_history': conversationHistory,
    });
    if (response['reply'] is String &&
        response['reply'].toString().isNotEmpty) {
      return response;
    }

    if (response['response'] is String &&
        response['response'].toString().isNotEmpty) {
      response['reply'] = response['response'];
    }

    return response;
  }

  Future<Map<String, dynamic>> voiceWithAi(
    String message, {
    String voiceMode = 'support',
    int stressLevel = 5,
    List<String> conversationHistory = const [],
  }) async {
    return await postAi('/api/v1/voice/respond', body: {
      'message': message,
      'voice_mode': voiceMode,
      'stress_level': stressLevel,
      'conversation_history': conversationHistory,
    });
  }

  Future<Map<String, dynamic>> getSubscription() async {
    return await get('/api/v1/subscription');
  }

  Future<Map<String, dynamic>> activateSubscription({
    required String plan,
    bool autoRenew = false,
  }) async {
    return await post('/api/v1/subscription/activate', body: {
      'plan': plan,
      'autoRenew': autoRenew,
    });
  }

  Future<Map<String, dynamic>> createPaymentOrder() async {
    return await post('/api/v1/payment/create-order', body: {});
  }

  Future<Map<String, dynamic>> createPaymentOrderForPlan(
      {required String plan}) async {
    return await post('/api/v1/payment/create-order', body: {'plan': plan});
  }

  Future<Map<String, dynamic>> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    return await post('/api/v1/payment/verify', body: {
      'razorpay_order_id': orderId,
      'razorpay_payment_id': paymentId,
      'razorpay_signature': signature,
    });
  }

  Future<Map<String, dynamic>> getPaymentHistory() async {
    return await get('/api/v1/payment/history');
  }

  Future<Map<String, dynamic>> getPaymentInvoice(String paymentId) async {
    return await get('/api/v1/payment/invoice/$paymentId');
  }

  Future<Map<String, dynamic>> startCall({
    required String peerAlias,
    String type = 'audio',
  }) async {
    return await post('/api/v1/calls/start', body: {
      'peerAlias': peerAlias,
      'type': type,
    });
  }

  Future<Map<String, dynamic>> submitWaterLog({
    required String date,
    required int consumedMl,
    required int weightKg,
    required int age,
    required String activityLevel,
    required String weather,
  }) async {
    return await post('/api/v1/wellness/water', body: {
      'date': date,
      'consumedMl': consumedMl,
      'weightKg': weightKg,
      'age': age,
      'activityLevel': activityLevel,
      'weather': weather,
    });
  }

  Future<Map<String, dynamic>> createMeditationSession({
    required String category,
    required int durationMinutes,
    required bool completed,
    bool recommendedByAI = false,
  }) async {
    return await post('/api/v1/wellness/meditation', body: {
      'category': category,
      'durationMinutes': durationMinutes,
      'completed': completed,
      'recommendedByAI': recommendedByAI,
    });
  }

  Future<Map<String, dynamic>> getDailyPlan() async {
    return await get('/api/v1/wellness/daily-plan');
  }

  Future<Map<String, dynamic>> getEmergencyToolkit() async {
    return await get('/api/v1/emergency/toolkit');
  }

  Future<Map<String, dynamic>> getAiWellnessPlan({
    required String mood,
    required int stressLevel,
    required double sleepHours,
    required double hydrationScore,
  }) async {
    return await postAi('/api/v1/wellness/plan', body: {
      'mood': mood,
      'stress_level': stressLevel,
      'sleep_hours': sleepHours,
      'hydration_score': hydrationScore,
    });
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}
