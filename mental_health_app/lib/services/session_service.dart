// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user_model.dart';
import 'api_service.dart';

class SessionService extends ChangeNotifier {
  SessionService({ApiService? apiService, FlutterSecureStorage? storage})
      : _apiService = apiService ?? ApiService(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'mindcare_session_token';
  static const _refreshTokenKey = 'mindcare_session_refresh_token';
  static const _userKey = 'mindcare_session_user';
  static const _guestUserKey = 'mindcare_guest_user';

  final ApiService _apiService;
  final FlutterSecureStorage _storage;

  bool _loading = true;
  bool _authenticated = false;
  bool _busy = false;
  String? _error;
  SessionUser? _user;
  LoginResult? _loginResult;
  String? _refreshToken;

  bool get loading => _loading;
  bool get authenticated => _authenticated;
  bool get busy => _busy;
  String? get error => _error;
  SessionUser? get user => _user;
  LoginResult? get loginResult => _loginResult;
  ApiService get apiService => _apiService;

  Future<T> runWithSessionRetry<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (error) {
      final message = error.toString();
      final needsRefresh = message.contains('401:') ||
          message.contains('Missing bearer token') ||
          message.contains('Invalid or expired token') ||
          message.contains('Session expired. Please login again.');
      if (!needsRefresh || _refreshToken == null || _refreshToken!.isEmpty) {
        rethrow;
      }

      final refreshed = await _refreshSession(_refreshToken!);
      if (!refreshed) {
        rethrow;
      }

      return await request();
    }
  }

  Future<void> initialize() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _storage.read(key: _tokenKey);
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      final userJson = await _storage.read(key: _userKey);
      final guestJson = await _storage.read(key: _guestUserKey);
      if (token != null && token.isNotEmpty) {
        _apiService.setAuthToken(token);
        _refreshToken = refreshToken;
        _authenticated = true;
        if (userJson != null && userJson.isNotEmpty) {
          _user = SessionUser.fromJson(
            jsonDecode(userJson) as Map<String, dynamic>,
          );
        }
        try {
          final me = await _apiService.getMe();
          _user = me;
          _authenticated = true;
          await _storage.write(key: _userKey, value: jsonEncode(me.toJson()));
        } catch (_) {
          if (refreshToken != null && refreshToken.isNotEmpty) {
            final refreshed = await _refreshSession(refreshToken);
            if (refreshed) {
              return;
            }
          }
          _error ??=
              'Session restored from local token, profile sync unavailable.';
        }
      } else if (guestJson != null && guestJson.isNotEmpty) {
        await _storage.delete(key: _guestUserKey);
        await _storage.delete(key: _userKey);
        _apiService.clearAuthToken();
        _authenticated = false;
        _user = null;
        _loginResult = null;
        _refreshToken = null;
      }
    } catch (error) {
      _error = error.toString();
      _authenticated = false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _performAuth(
      () => _apiService.login(email.trim(), password),
    );
  }

  Future<Map<String, dynamic>> register(
    String email,
    String password, {
    required String username,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _apiService.registerForEmailVerification(
        email.trim(),
        password,
        username: username.trim(),
        displayName: username.trim(),
      );

      _authenticated = false;
      _user = null;
      _loginResult = null;
      _refreshToken = null;
      _apiService.clearAuthToken();

      return result;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      return await _apiService.verifyEmailOtp(
        email: email.trim(),
        otp: otp.trim(),
      );
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> resendEmailOtp({
    required String email,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      return await _apiService.resendEmailOtp(email: email.trim());
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> forgotPasswordSendOtp({
    required String email,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      return await _apiService.forgotPasswordSendOtp(email: email.trim());
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> forgotPasswordVerifyOtp({
    required String email,
    required String otp,
  }) async {
    await _performAuth(
      () => _apiService.forgotPasswordVerifyOtp(
        email: email.trim(),
        otp: otp.trim(),
      ),
    );
  }

  Future<void> continueAsGuest({String? alias}) async {
    final normalizedAlias = _normalizeGuestAlias(alias);

    await _performAuth(() => _apiService.loginGuest(normalizedAlias));

    await _storage.write(
      key: _guestUserKey,
      value: jsonEncode(_user?.toJson() ?? const {}),
    );

    final token = _apiService.authToken;
    if (token == null || token.isEmpty) {
      await clearSession();
      throw Exception('Guest session token missing. Please sign in again.');
    }
  }

  Future<void> _performAuth(Future<LoginResult> Function() request) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final result = await request();
      _loginResult = result;
      _user = result.user;
      _authenticated = true;
      _apiService.setAuthToken(result.token);
      _refreshToken = result.refreshToken;
      await _storage.write(key: _tokenKey, value: result.token);
      if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: result.refreshToken);
      }
      await _storage.write(
          key: _userKey, value: jsonEncode(result.user.toJson()));
      debugPrint('AUTH_OK');
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _guestUserKey);
    _apiService.clearAuthToken();
    _refreshToken = null;
    _authenticated = false;
    _user = null;
    _loginResult = null;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (!_authenticated) return;
    try {
      final me = await _apiService.getMe();
      _user = me;
      await _storage.write(key: _userKey, value: jsonEncode(me.toJson()));
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      if (_refreshToken != null && _refreshToken!.isNotEmpty) {
        final refreshed = await _refreshSession(_refreshToken!);
        if (refreshed) return;
      }
      notifyListeners();
      return;
    }
  }

  Future<bool> _refreshSession(String refreshToken) async {
    try {
      final result = await _apiService.refreshSession(refreshToken);
      _loginResult = result;
      _user = result.user;
      _authenticated = true;
      _apiService.setAuthToken(result.token);
      _refreshToken = result.refreshToken;
      await _storage.write(key: _tokenKey, value: result.token);
      if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: result.refreshToken);
      }
      await _storage.write(
          key: _userKey, value: jsonEncode(result.user.toJson()));
      debugPrint('AUTH_OK');
      notifyListeners();
      return true;
    } catch (error) {
      _error = error.toString();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (_) {}
    await clearSession();
  }

  String _normalizeGuestAlias(String? alias) {
    final trimmed = alias?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    return 'guest_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  }

  void _restoreLocalGuestSession(String guestJson) {
    final decoded = jsonDecode(guestJson);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    _user = SessionUser.fromJson(decoded);
    _loginResult = LoginResult(
      success: true,
      token: '',
      refreshToken: null,
      user: _user!,
    );
    _authenticated = true;
    _refreshToken = null;
    _apiService.clearAuthToken();
    debugPrint('GUEST_LOCAL_OK');
  }

  Future<void> _activateOfflineGuestSession(String alias) async {
    final user = SessionUser(
      id: 'local_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      email: null,
      username: alias,
      displayName: alias,
      alias: alias,
      authProvider: 'guest-local',
      freeCallsRemaining: 0,
      isSubscribed: false,
      healing: HealingStats(
        wellnessXp: 0,
        healingLevel: 1,
        meditationStreak: 0,
        moodStreak: 0,
        hydrationStreak: 0,
        achievements: [],
      ),
      privacy: PrivacySettings(
        shareMoodAnalytics: false,
        allowAnonymousMatching: true,
      ),
    );

    _user = user;
    _loginResult = LoginResult(
      success: true,
      token: '',
      refreshToken: null,
      user: user,
    );
    _authenticated = true;
    _busy = false;
    _error = null;
    _refreshToken = null;
    _apiService.clearAuthToken();
    await _storage.write(key: _guestUserKey, value: jsonEncode(user.toJson()));
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    debugPrint('GUEST_LOCAL_OK');
    notifyListeners();
  }

  Future<void> _syncLocalGuestSessionIfPossible() async {
    final user = _user;
    if (user == null || user.authProvider != 'guest-local') {
      return;
    }
    try {
      final result = await _apiService.loginGuest(user.alias);
      _loginResult = result;
      _user = result.user;
      _authenticated = true;
      _apiService.setAuthToken(result.token);
      _refreshToken = result.refreshToken;
      await _storage.write(key: _tokenKey, value: result.token);
      if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
        await _storage.write(key: _refreshTokenKey, value: result.refreshToken);
      }
      await _storage.write(
          key: _userKey, value: jsonEncode(result.user.toJson()));
      await _storage.write(
          key: _guestUserKey, value: jsonEncode(result.user.toJson()));
      debugPrint('GUEST_SYNC_OK');
      notifyListeners();
    } catch (_) {
      // Keep the local guest session active until the backend becomes available.
    }
  }
}
