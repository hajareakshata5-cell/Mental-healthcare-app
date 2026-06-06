import 'dart:async';
import 'dart:convert';
import 'package:video_player/video_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/friend_call_screens.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'config/constants.dart';
import 'models/user_model.dart';
import 'services/api_service.dart';
import 'services/clinical/clinical_engine_service.dart';
import 'services/clinical/doctor_recommendation_service.dart';
import 'services/clinical/emotion_detection_service.dart';
import 'services/clinical/llm_chatbot_service.dart';
import 'services/clinical/mood_prediction_service.dart';
import 'services/hydration_calculator_service.dart';
import 'services/session_service.dart';
import 'services/sound_therapy_service.dart';
import 'services/socket_service.dart';
import 'screens/mindcare_connect_screen.dart';

import 'services/firebase_realtime_service.dart';
import 'services/push_notification_service.dart';

const double _kBottomNavHeight = 80;
const double _kBottomNavOuterPadding = 12;
const double _kBottomNavDesignGap = 8;

double _bottomNavReserve(BuildContext context) {
  return MediaQuery.of(context).padding.bottom +
      _kBottomNavHeight +
      _kBottomNavOuterPadding +
      _kBottomNavDesignGap;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindCare',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          surface: const Color(0xFFF6FAF8),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF155E75),
          tertiary: const Color(0xFFF59E0B),
          surfaceTint: Colors.transparent,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withValues(alpha: 0.78),
          indicatorColor: const Color(0x1A0F766E),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF0F766E)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.82),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FBFA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.2),
          ),
        ),
      ),
      home: const MindCareBootstrap(),
    );
  }
}

class MindCareBootstrap extends StatefulWidget {
  const MindCareBootstrap({super.key});

  @override
  State<MindCareBootstrap> createState() => _MindCareBootstrapState();
}

class _MindCareBootstrapState extends State<MindCareBootstrap> {
  final SessionService _sessionService = SessionService();

  @override
  void initState() {
    super.initState();
    _sessionService.initialize();
  }

  @override
  void dispose() {
    _sessionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sessionService,
      builder: (context, _) {
        if (_sessionService.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!_sessionService.authenticated) {
          return MindCareAuthScreen(sessionService: _sessionService);
        }

        return MindCareShell(sessionService: _sessionService);
      },
    );
  }
}

class MindCareAuthScreen extends StatefulWidget {
  const MindCareAuthScreen({super.key, required this.sessionService});

  final SessionService sessionService;

  @override
  State<MindCareAuthScreen> createState() => _MindCareAuthScreenState();
}

class _MindCareAuthScreenState extends State<MindCareAuthScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  bool _otpMode = false;
  bool _forgotPasswordMode = false;
  bool _forgotPasswordOtpMode = false;
  String? _pendingVerificationEmail;
  String? _pendingForgotPasswordEmail;
  String? _successMessage;
  bool _registerMode = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    try {
      if (_registerMode) {
        final response = await widget.sessionService.register(
          _email.text,
          _password.text,
          username: _username.text,
        );

        setState(() {
          _otpMode = true;
          _pendingVerificationEmail =
              (response['email']?.toString().trim().isNotEmpty ?? false)
                  ? response['email'].toString()
                  : _email.text.trim();
          _successMessage = response['message']?.toString() ??
              'Verification OTP sent to your email.';
        });
      } else {
        await widget.sessionService.signInWithEmail(
          _email.text,
          _password.text,
        );
      }
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    final email = _pendingVerificationEmail ?? _email.text.trim();
    final otp = _otp.text.trim();

    if (email.isEmpty || otp.isEmpty) {
      setState(() => _error = 'Email and OTP are required.');
      return;
    }

    try {
      final response = await widget.sessionService.verifyEmailOtp(
        email: email,
        otp: otp,
      );

      setState(() {
        _otpMode = false;
        _registerMode = false;
        _otp.clear();
        _successMessage = response['message']?.toString() ??
            'Email verified successfully. Please sign in.';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    final email = _pendingVerificationEmail ?? _email.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Email is required to resend OTP.');
      return;
    }

    try {
      final response = await widget.sessionService.resendEmailOtp(
        email: email,
      );

      setState(() {
        _successMessage =
            response['message']?.toString() ?? 'Verification OTP sent again.';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _sendForgotPasswordOtp() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    final email = _email.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Email is required.');
      return;
    }

    try {
      final response = await widget.sessionService.forgotPasswordSendOtp(
        email: email,
      );

      setState(() {
        _forgotPasswordOtpMode = true;
        _pendingForgotPasswordEmail =
            (response['email']?.toString().trim().isNotEmpty ?? false)
                ? response['email'].toString()
                : email;
        _successMessage = response['message']?.toString() ??
            'Password login OTP sent to your email.';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _verifyForgotPasswordOtp() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    final email = _pendingForgotPasswordEmail ?? _email.text.trim();
    final otp = _otp.text.trim();

    if (email.isEmpty || otp.isEmpty) {
      setState(() => _error = 'Email and OTP are required.');
      return;
    }

    try {
      await widget.sessionService.forgotPasswordVerifyOtp(
        email: email,
        otp: otp,
      );
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.sessionService.busy;

    return Scaffold(
      body: Stack(
        children: [
          const _MindCareBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.spa,
                              size: 44, color: Color(0xFF0F766E)),
                          const SizedBox(height: 14),
                          const Text(
                            'MindCare',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in, register, or continue anonymously to keep your session, wellness data, and premium state in sync with the backend.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF475569)),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                  value: false, label: Text('Sign in')),
                              ButtonSegment(
                                  value: true, label: Text('Register')),
                            ],
                            selected: {_registerMode},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _registerMode = selection.first;
                                _otpMode = false;
                                _forgotPasswordMode = false;
                                _forgotPasswordOtpMode = false;
                                _pendingVerificationEmail = null;
                                _pendingForgotPasswordEmail = null;
                                _otp.clear();
                                _error = null;
                                _successMessage = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          if (_otpMode) ...[
                            Text(
                              'Enter the OTP sent to ${_pendingVerificationEmail ?? _email.text.trim()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _otp,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: const InputDecoration(
                                labelText: 'Verification OTP',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: busy ? null : _verifyOtp,
                              child: Text(
                                busy ? 'Verifying...' : 'Verify OTP',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: busy ? null : _resendOtp,
                              child: const Text('Resend OTP'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _otpMode = false;
                                        _otp.clear();
                                        _error = null;
                                        _successMessage = null;
                                      });
                                    },
                              child: const Text('Back to register'),
                            ),
                          ] else if (_forgotPasswordMode) ...[
                            Text(
                              _forgotPasswordOtpMode
                                  ? 'Enter the OTP sent to ${_pendingForgotPasswordEmail ?? _email.text.trim()}'
                                  : 'Enter your registered email to receive a login OTP.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _email,
                              enabled: !_forgotPasswordOtpMode,
                              keyboardType: TextInputType.emailAddress,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                            ),
                            if (_forgotPasswordOtpMode) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _otp,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                  labelText: 'OTP',
                                  counterText: '',
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : (_forgotPasswordOtpMode
                                      ? _verifyForgotPasswordOtp
                                      : _sendForgotPasswordOtp),
                              child: Text(
                                busy
                                    ? 'Please wait...'
                                    : (_forgotPasswordOtpMode
                                        ? 'Verify OTP & Sign in'
                                        : 'Send OTP'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _forgotPasswordMode = false;
                                        _forgotPasswordOtpMode = false;
                                        _pendingForgotPasswordEmail = null;
                                        _otp.clear();
                                        _error = null;
                                        _successMessage = null;
                                      });
                                    },
                              child: const Text('Back to sign in'),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            if (_registerMode) ...[
                              TextField(
                                controller: _username,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: _registerMode
                                    ? 'Create app password'
                                    : 'App password',
                                helperText: _registerMode
                                    ? 'Do not enter your email/Gmail password. Create a new password for MindCare.'
                                    : 'Use the password you created for MindCare.',
                              ),
                            ),
                            if (!_registerMode) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: busy
                                      ? null
                                      : () {
                                          setState(() {
                                            _forgotPasswordMode = true;
                                            _forgotPasswordOtpMode = false;
                                            _pendingForgotPasswordEmail = null;
                                            _otp.clear();
                                            _error = null;
                                            _successMessage = null;
                                          });
                                        },
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: busy ? null : _submit,
                              child: Text(
                                busy
                                    ? 'Please wait...'
                                    : (_registerMode
                                        ? 'Create account'
                                        : 'Sign in'),
                              ),
                            ),
                          ],
                          if (_successMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _successMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF047857),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MindCareShell extends StatefulWidget {
  const MindCareShell({super.key, required this.sessionService});

  final SessionService sessionService;

  @override
  State<MindCareShell> createState() => _MindCareShellState();
}

class _MindCareShellState extends State<MindCareShell>
    with WidgetsBindingObserver {
  late final ApiService _api;
  late final ClinicalEngineService _clinicalEngine;
  final DoctorRecommendationService _doctorRecommendationService =
      const DoctorRecommendationService();
  final LlmChatbotService _llmChatbotService = const LlmChatbotService();
  final MoodPredictionService _moodPredictionService =
      const MoodPredictionService();
  final EmotionDetectionService _emotionDetectionService =
      const EmotionDetectionService();
  final SoundTherapyService _soundTherapyService = SoundTherapyService();
  final SocketService _socketService = SocketService();
  final FirebaseRealtimeService _firebaseRealtimeService =
      FirebaseRealtimeService();
  final PushNotificationService _pushNotificationService =
      PushNotificationService();
  final ValueNotifier<TherapySignal> _therapySignal =
      ValueNotifier(const TherapySignal.unknown());
  bool _syncingClinicalTherapy = false;

  int _index = 1;
  bool _loadingDiagnostics = true;
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _version;
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _dailyPlan;
  Map<String, dynamic>? _moodHistory;
  String? _diagnosticError;
  SoundTherapyNotice? _activeNotice;
  Timer? _noticeTimer;
  StreamSubscription<SoundTherapyNotice>? _soundNoticeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.sessionService.apiService;
    _clinicalEngine = ClinicalEngineService();
    _soundTherapyService.initialize();
    _soundNoticeSubscription = _soundTherapyService.notices.listen((notice) {
      if (!mounted) return;
      setState(() => _activeNotice = notice);
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _activeNotice = null);
      });
    });
    _clinicalEngine.addListener(_syncTherapyFromClinicalEngine);
    _soundTherapyService.addListener(_syncClinicalSoundState);
    widget.sessionService.addListener(_syncSocketSession);
    _syncSocketSession();
    _pushNotificationService.initialize(
      context: context,
      apiService: _api,
    );
    _loadDiagnostics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.sessionService.removeListener(_syncSocketSession);
    _clinicalEngine.removeListener(_syncTherapyFromClinicalEngine);
    _soundTherapyService.removeListener(_syncClinicalSoundState);
    _noticeTimer?.cancel();
    _soundNoticeSubscription?.cancel();
    _soundTherapyService.dispose();
    _clinicalEngine.dispose();
    _socketService.dispose();
    _therapySignal.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSocketSession();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final user = widget.sessionService.user;
      if (user != null) {
        _firebaseRealtimeService.setOnlineStatus(
          userId: user.id,
          online: false,
        );
      }
      _socketService.disconnect();
    }
  }

  void _syncClinicalSoundState() {
    if (_syncingClinicalTherapy) return;
    _syncingClinicalTherapy = true;
    try {
      _clinicalEngine.syncSoundState(_soundTherapyService);
      _therapySignal.value = _clinicalEngine.toTherapySignal();
    } finally {
      _syncingClinicalTherapy = false;
    }
  }

  void _syncTherapyFromClinicalEngine() {
    if (_syncingClinicalTherapy) return;
    _syncingClinicalTherapy = true;
    try {
      final signal = _clinicalEngine.toTherapySignal();
      _therapySignal.value = signal;
      _soundTherapyService.updateSignal(signal);
    } finally {
      _syncingClinicalTherapy = false;
    }
  }

  void _syncSocketSession() {
    final user = widget.sessionService.user;
    final token = widget.sessionService.apiService.authToken;
    if (user == null || token == null || token.isEmpty) {
      _socketService.disconnect();
      return;
    }

    _firebaseRealtimeService.upsertUserPresence(
      userId: user.id,
      name: user.displayName ?? user.alias,
      online: true,
    );

    if (_socketService.isConnected) {
      return;
    }

    _socketService.connect(token, user.id, user.alias);
  }

  Future<void> _loadDiagnostics() async {
    setState(() {
      _loadingDiagnostics = true;
      _diagnosticError = null;
    });

    try {
      await widget.sessionService.refreshProfile();
      final results = await Future.wait([
        _api.getHealth(),
        _api.getDeploymentVersion(),
        _api.getSubscription(),
        _api.getDailyPlan(),
        _api.fetchMoodHistory(limit: 10),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _health = results[0];
        _version = results[1];
        _subscription = results[2];
        _dailyPlan = results[3];
        _moodHistory = results[4];
      });
      await _clinicalEngine.initialize(
        user: widget.sessionService.user,
        moodHistory: _moodHistory,
        dailyPlan: _dailyPlan,
        soundTherapyService: _soundTherapyService,
      );
      _therapySignal.value = _clinicalEngine.toTherapySignal();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _diagnosticError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDiagnostics = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const _MindCareBackdrop(),
          Padding(
            padding: EdgeInsets.only(bottom: _bottomNavReserve(context)),
            child: SafeArea(
              bottom: false,
              child: IndexedStack(
                index: _index,
                children: [
                  DashboardTab(
                    sessionUser: widget.sessionService.user,
                    clinicalEngine: _clinicalEngine,
                    health: _health,
                    version: _version,
                    subscription: _subscription,
                    dailyPlan: _dailyPlan,
                    moodHistory: _moodHistory,
                    loading: _loadingDiagnostics,
                    error: _diagnosticError,
                    doctorRecommendationService: _doctorRecommendationService,
                    llmChatbotService: _llmChatbotService,
                    moodPredictionService: _moodPredictionService,
                    emotionDetectionService: _emotionDetectionService,
                    onRefresh: _loadDiagnostics,
                  ),
                  MentalHealthAiTab(
                    sessionService: widget.sessionService,
                    apiService: _api,
                    clinicalEngine: _clinicalEngine,
                    doctorRecommendationService: _doctorRecommendationService,
                    onSignalUpdated: (signal) {
                      _therapySignal.value = signal;
                      _soundTherapyService.updateSignal(signal);
                    },
                  ),
                  ClinicalPlanningTab(
                    clinicalEngine: _clinicalEngine,
                    doctorRecommendationService: _doctorRecommendationService,
                    llmChatbotService: _llmChatbotService,
                    moodPredictionService: _moodPredictionService,
                    emotionDetectionService: _emotionDetectionService,
                  ),
                  SoundTherapyTab(
                    service: _soundTherapyService,
                    signalListenable: _therapySignal,
                  ),
                  SupportTab(
                    sessionService: widget.sessionService,
                    socketService: _socketService,
                    clinicalEngine: _clinicalEngine,
                  ),
                ],
              ),
            ),
          ),
          if (_activeNotice != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 12,
              child: _CornerNoticeCard(notice: _activeNotice!),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'AI',
              ),
              NavigationDestination(
                icon: Icon(Icons.self_improvement_outlined),
                selectedIcon: Icon(Icons.self_improvement),
                label: 'Meditation',
              ),
              NavigationDestination(
                icon: Icon(Icons.graphic_eq_outlined),
                selectedIcon: Icon(Icons.graphic_eq),
                label: 'Sound',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Support',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MindCareBackdrop extends StatelessWidget {
  const _MindCareBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4FBF8), Color(0xFFFDF7EF), Color(0xFFF9FCFD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -30,
            child: _GlowBlob(color: Color(0x330F766E), size: 180),
          ),
          Positioned(
            bottom: 120,
            left: -50,
            child: _GlowBlob(color: Color(0x33F59E0B), size: 200),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GridPainter(color: Color(0x140F766E)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 36.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

const List<String> kMotivationQuotes = [
  'Every small step counts.',
  'You are stronger than today\'s stress.',
  'Progress matters more than perfection.',
  'Take a deep breath and keep moving.',
  'A healthy mind creates a healthy life.',
  'One good habit can change your future.',
  'Focus on growth, not fear.',
  'Your consistency is your superpower.',
  'Today is a fresh chance to care for yourself.',
  'Small habits create strong days.',
];

String _quoteForToday() {
  return kMotivationQuotes[DateTime.now().day % kMotivationQuotes.length];
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.sessionUser,
    required this.clinicalEngine,
    required this.health,
    required this.version,
    required this.subscription,
    required this.dailyPlan,
    required this.moodHistory,
    required this.loading,
    required this.error,
    required this.doctorRecommendationService,
    required this.llmChatbotService,
    required this.moodPredictionService,
    required this.emotionDetectionService,
    required this.onRefresh,
  });

  final SessionUser? sessionUser;
  final ClinicalEngineService clinicalEngine;
  final Map<String, dynamic>? health;
  final Map<String, dynamic>? version;
  final Map<String, dynamic>? subscription;
  final Map<String, dynamic>? dailyPlan;
  final Map<String, dynamic>? moodHistory;
  final bool loading;
  final String? error;
  final DoctorRecommendationService doctorRecommendationService;
  final LlmChatbotService llmChatbotService;
  final MoodPredictionService moodPredictionService;
  final EmotionDetectionService emotionDetectionService;
  final Future<void> Function() onRefresh;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  final HydrationCalculatorService _hydrationCalculatorService =
      const HydrationCalculatorService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final quote = _quoteForToday();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Today\'s Motivation'),
          content: Text(quote),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Start Day'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionStatus =
        widget.subscription?['subscription'] ?? widget.subscription;
    final activePlan = subscriptionStatus is Map
        ? (subscriptionStatus['plan'] ?? subscriptionStatus['tier'] ?? 'free')
            .toString()
        : 'free';

    final healingLevel = widget.sessionUser?.healing?.healingLevel ?? 1;
    final wellnessXp = widget.sessionUser?.healing?.wellnessXp ?? 0;
    final hydrationGoal = widget.dailyPlan?['water']?['targetMl']?.toString() ??
        widget.dailyPlan?['waterTargetMl']?.toString() ??
        '2000';
    final moodCount = (widget.moodHistory?['items'] as List?)?.length ??
        (widget.moodHistory?['history'] as List?)?.length ??
        0;
    final todayQuote = _quoteForToday();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _HeroCard(
            title: 'MindCare',
            subtitle: widget.sessionUser == null
                ? 'Track your meditation, hydration, mood and daily wellness goals.'
                : 'Welcome back, ${widget.sessionUser!.displayName ?? widget.sessionUser!.alias} Stay consistent and build healthy habits every day.',
            chips: const [
              'Daily plan',
              'Hydration goal',
              'Meditation progress',
            ],
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Today\'s Motivation',
            body: todayQuote,
            icon: Icons.wb_sunny_outlined,
            accent: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatusCard(
                  label: 'Healing level',
                  value: '$healingLevel',
                  icon: Icons.auto_graph,
                  accent: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusCard(
                  label: 'Plan',
                  value: activePlan,
                  icon: Icons.workspace_premium_outlined,
                  accent: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatusCard(
                  label: 'Wellness XP',
                  value: '$wellnessXp',
                  icon: Icons.bolt,
                  accent: const Color(0xFF155E75),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusCard(
                  label: 'Mood logs',
                  value: '$moodCount',
                  icon: Icons.mood,
                  accent: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionHeader(
            title: 'Recommended intake',
            subtitle:
                'Calculate water needs from age, weight, gender and activity.',
          ),
          const SizedBox(height: 10),
          _HydrationCalculatorCard(
            hydrationCalculatorService: _hydrationCalculatorService,
            seedTargetMl: int.tryParse(hydrationGoal) ?? 2000,
          ),
          const SizedBox(height: 14),
          _SectionHeader(
            title: 'Daily wellness plan',
            subtitle: 'Simple tasks for a healthy body and calm mind.',
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Daily plan',
            body: widget.dailyPlan == null
                ? 'Hydrate well, complete one meditation session, log your mood, and take one short mindful break.'
                : _summarizeDailyPlan(widget.dailyPlan!),
            icon: Icons.event_note_outlined,
          ),
          const SizedBox(height: 10),
          const _TodayTaskCompletedCard(),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Mood history',
            body: _summarizeMoodHistory(widget.moodHistory),
            icon: Icons.timeline_outlined,
          ),
          const SizedBox(height: 14),
          _SectionHeader(
            title: 'Meditation progress',
            subtitle: 'Live signals update after chat, hydration and sound.',
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Current wellness signal',
            body:
                'Stress ${widget.clinicalEngine.stressScore} • mood ${widget.clinicalEngine.moodTrend} • emotion ${widget.clinicalEngine.emotion} • confidence ${(widget.clinicalEngine.confidence * 100).round()}%',
            icon: Icons.self_improvement_outlined,
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Live recommendations',
            body: widget.clinicalEngine.recommendations.isEmpty
                ? 'Send an AI message, log hydration, or complete a meditation to update recommendations.'
                : widget.clinicalEngine.recommendations.join('\n'),
            icon: Icons.auto_awesome,
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Calm practice',
            body:
                'Grounding: ${widget.clinicalEngine.groundingSuggestions.isEmpty ? 'Try 4-4-4 breathing for 3 minutes.' : widget.clinicalEngine.groundingSuggestions.join(' • ')}\n\nSleep: ${widget.clinicalEngine.sleepSuggestions.isEmpty ? 'Keep a consistent sleep time and reduce screen use before bed.' : widget.clinicalEngine.sleepSuggestions.join(' • ')}',
            icon: Icons.spa_outlined,
          ),
        ],
      ),
    );
  }
}

class _TodayTaskCompletedCard extends StatefulWidget {
  const _TodayTaskCompletedCard();

  @override
  State<_TodayTaskCompletedCard> createState() =>
      _TodayTaskCompletedCardState();
}

class _TodayTaskCompletedCardState extends State<_TodayTaskCompletedCard> {
  bool _completed = false;
  int _streak = 0;

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  void initState() {
    super.initState();
    _loadTaskState();
  }

  Future<void> _loadTaskState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCompletedDate =
        prefs.getString('mindcare_last_task_completed_date');
    final streak = prefs.getInt('mindcare_task_streak') ?? 0;

    if (!mounted) return;
    setState(() {
      _completed = lastCompletedDate == _todayKey;
      _streak = streak;
    });
  }

  Future<void> _completeTodayTask() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCompletedDate =
        prefs.getString('mindcare_last_task_completed_date');

    if (lastCompletedDate == _todayKey) {
      return;
    }

    final newStreak = (prefs.getInt('mindcare_task_streak') ?? 0) + 1;

    await prefs.setString('mindcare_last_task_completed_date', _todayKey);
    await prefs.setInt('mindcare_task_streak', newStreak);

    if (!mounted) return;
    setState(() {
      _completed = true;
      _streak = newStreak;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (_completed
                      ? const Color(0xFF0F766E)
                      : const Color(0xFFF59E0B))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _completed ? Icons.check_circle : Icons.radio_button_unchecked,
              color: _completed
                  ? const Color(0xFF0F766E)
                  : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _completed
                  ? 'Great job! Today’s task is completed. Current streak: $_streak day(s).'
                  : 'Complete water, meditation and mood check-in to grow your streak.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF334155),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _completed ? null : _completeTodayTask,
            child: Text(_completed ? 'Done' : 'Complete'),
          ),
        ],
      ),
    );
  }
}

String _summarizeMoodHistory(Map<String, dynamic>? moodHistory) {
  if (moodHistory == null) {
    return 'No mood history loaded yet. Pull to refresh.';
  }

  final items = (moodHistory['items'] as List?) ??
      (moodHistory['history'] as List?) ??
      const [];
  if (items.isEmpty) {
    return 'No mood logs yet. Start a daily check-in to build your wellness graph.';
  }

  final first = items.first;
  if (first is Map<String, dynamic>) {
    final mood = first['mood'] ?? first['label'] ?? 'unknown';
    final createdAt = first['createdAt'] ?? first['date'] ?? '';
    return 'Latest mood: $mood${createdAt.toString().isEmpty ? '' : ' at $createdAt'}. ${items.length} log(s) available.';
  }

  return '${items.length} log(s) available.';
}

String _summarizeDailyPlan(Map<String, dynamic> plan) {
  final parts = <String>[];
  final focus = plan['focus'] ?? plan['dailyFocus'];
  final water = plan['water'];
  final meditation = plan['meditation'];
  final sleep = plan['sleep'];

  if (focus != null) parts.add('Focus: $focus');
  if (water is Map && water['targetMl'] != null) {
    parts.add('Water target: ${water['targetMl']} ml');
  }
  if (meditation is Map && meditation['durationMinutes'] != null) {
    parts.add('Meditation: ${meditation['durationMinutes']} min');
  }
  if (sleep is Map && sleep['targetHours'] != null) {
    parts.add('Sleep: ${sleep['targetHours']} h');
  }

  return parts.isEmpty
      ? 'Plan loaded, but no readable fields were returned.'
      : parts.join(' • ');
}

class _HydrationCalculatorCard extends StatefulWidget {
  const _HydrationCalculatorCard({
    required this.hydrationCalculatorService,
    required this.seedTargetMl,
  });

  final HydrationCalculatorService hydrationCalculatorService;
  final int seedTargetMl;

  @override
  State<_HydrationCalculatorCard> createState() =>
      _HydrationCalculatorCardState();
}

class _HydrationCalculatorCardState extends State<_HydrationCalculatorCard> {
  late final TextEditingController _age;
  late final TextEditingController _weight;
  String _gender = 'female';
  String _activity = 'moderate';
  HydrationProfile? _profile;

  @override
  void initState() {
    super.initState();
    _age = TextEditingController(text: '29');
    _weight = TextEditingController(text: '68');
    _recalculate();
  }

  @override
  void dispose() {
    _age.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _recalculate() {
    final age = int.tryParse(_age.text) ?? 29;
    final weight = double.tryParse(_weight.text) ?? 68;
    setState(() {
      _profile = widget.hydrationCalculatorService.calculate(
        age: age,
        weightKg: weight,
        gender: _gender,
        activityLevel: _activity,
      );
    });
  }

  String _buildSmartDailyPlanText() {
    final age = int.tryParse(_age.text) ?? 20;
    final weight = double.tryParse(_weight.text) ?? 50;
    final waterMl = _profile?.targetMl ?? (weight * 35).round();

    final meditationMinutes = age < 25 ? 10 : 15;
    final walkMinutes = _activity == 'high'
        ? 20
        : _activity == 'low'
            ? 35
            : 30;
    final sleepHours = age < 25 ? 8 : 7;

    final genderNote = _gender == 'female'
        ? 'Include iron-rich food and avoid skipping meals.'
        : 'Keep protein, hydration and sleep consistent.';

    return 'Water: $waterMl ml\n'
        'Meditation: $meditationMinutes min\n'
        'Walk/Exercise: $walkMinutes min\n'
        'Sleep target: $sleepHours hours\n'
        'Mood check-in: 1 time today\n'
        '$genderNote';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final smartPlan = _buildSmartDailyPlanText();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.water_drop_outlined,
                    color: Color(0xFF0F766E)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dynamic hydration target',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calculated from age, weight, gender, and activity level.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age'),
                  onChanged: (_) => _recalculate(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Weight kg'),
                  onChanged: (_) => _recalculate(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ['female', 'male', 'other'])
                ChoiceChip(
                  label: Text(value[0].toUpperCase() + value.substring(1)),
                  selected: _gender == value,
                  onSelected: (_) {
                    setState(() => _gender = value);
                    _recalculate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ['low', 'moderate', 'high'])
                ChoiceChip(
                  label: Text(value[0].toUpperCase() + value.substring(1)),
                  selected: _activity == value,
                  onSelected: (_) {
                    setState(() => _activity = value);
                    _recalculate();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Recommended intake',
            body: profile == null
                ? 'Calculating...'
                : '${profile.targetMl} ml per day. ${profile.note}',
            icon: Icons.local_drink_outlined,
          ),
          const SizedBox(height: 10),
          _InfoCard(
            title: 'Smart Daily Plan',
            body: smartPlan,
            icon: Icons.checklist_rtl,
            accent: const Color(0xFF155E75),
          ),
          const SizedBox(height: 8),
          Text(
            'Backend daily plan target: ${widget.seedTargetMl} ml',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
        ],
      ),
    );
  }
}

enum _MentalHealthTopicAction { chat, call }

class _MentalHealthTopic {
  const _MentalHealthTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.mode,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final String mode;
}

String _detectMindCareReplyLanguage(String selectedLanguage, String message) {
  if (selectedLanguage != 'Auto') {
    return selectedLanguage;
  }

  final lower = message.toLowerCase();
  final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(message);
  if (hasDevanagari) {
    final hindiWords = ['है', 'हूँ', 'नहीं', 'क्या', 'आप', 'मुझे', 'क्यों'];
    if (hindiWords.any(message.contains)) {
      return 'Hindi';
    }
    return 'Marathi';
  }

  final marathiHints = [
    'mala',
    'majha',
    'maza',
    'vatat',
    'nahi',
    'kay',
    'ahe',
    'aahe',
    'sang',
    'karu',
    'zala',
    'khup',
    'ekta',
    'ekt'
  ];
  if (marathiHints.any((word) => lower.contains(word))) {
    return 'Marathi';
  }

  final hindiHints = ['mujhe', 'mera', 'kya', 'nahi', 'hai', 'akela'];
  if (hindiHints.any((word) => lower.contains(word))) {
    return 'Hindi';
  }

  return 'English';
}

String _cleanMindCareBackendReply(String rawReply) {
  return rawReply
      .replaceAll(RegExp(r'Context:.*', dotAll: true), '')
      .replaceAll(RegExp(r'You mentioned:.*', dotAll: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _buildNaturalMindCareReply({
  required String userMessage,
  required String rawReply,
  required String topic,
  required String selectedLanguage,
  required List<_TopicMessage> previousMessages,
}) {
  final language = _detectMindCareReplyLanguage(selectedLanguage, userMessage);
  final message = userMessage.trim();
  final lower = message.toLowerCase();
  final cleaned = _cleanMindCareBackendReply(rawReply);
  final isGreeting =
      RegExp(r'^(hi|hello|hey|hii|hiii|namaste|नमस्ते)$').hasMatch(lower);

  final isLonely = lower.contains('lonely') ||
      lower.contains('alone') ||
      lower.contains('no one') ||
      lower.contains('ekta') ||
      lower.contains('ekt') ||
      lower.contains('एकट') ||
      lower.contains('अकेला') ||
      lower.contains('akela');

  final isStress = lower.contains('stress') ||
      lower.contains('anxious') ||
      lower.contains('anxiety') ||
      lower.contains('panic') ||
      lower.contains('tension') ||
      lower.contains('overthinking') ||
      lower.contains('ताण') ||
      lower.contains('घाबर') ||
      lower.contains('चिंता');

  final isSad = lower.contains('sad') ||
      lower.contains('depress') ||
      lower.contains('cry') ||
      lower.contains('hurt') ||
      lower.contains('दुख') ||
      lower.contains('उदास') ||
      lower.contains('रड');

  final hasRecentChat = previousMessages
          .where((entry) => !entry.loading)
          .where((entry) => entry.text.trim().isNotEmpty)
          .length >
      2;

  if (language == 'Marathi') {
    if (isGreeting) {
      return 'Hi, मी इथे आहे. आज तुला कसं वाटतंय? तू आरामात, जसं मनात आहे तसं सांगू शकतेस.';
    }
    if (isLonely || topic == 'Loneliness') {
      return 'मला समजतंय. एकटं वाटणं खूप जड असू शकतं, पण तू आत्ता एकटी नाहीस. काय झालंय किंवा कोणत्या गोष्टीमुळे तुला असं वाटतंय ते थोडं सांगशील का?';
    }
    if (isStress || topic == 'Anxiety & Stress' || topic == 'Panic Support') {
      return 'हे ऐकून वाटतंय की तू खूप pressure मध्ये आहेस. आधी एक खोल श्वास घे. आता आपण एकच गोष्ट पकडूया — सध्या तुला सर्वात जास्त tension कशामुळे येतंय?';
    }
    if (isSad || topic == 'Depression & Sadness') {
      return 'हे खूप कठीण वाटत असेल. तुझे feelings valid आहेत. मला सांग, हे आज अचानक वाढलंय का की काही दिवसांपासून असंच चालू आहे?';
    }
    if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains('context:')) {
      return cleaned;
    }
    return hasRecentChat
        ? 'मी ऐकतेय. तू जे सांगितलं त्यावरून हे तुझ्यासाठी खरंच important आहे. अजून थोडं सांगशील का, म्हणजे मी तुला योग्य next step सुचवू शकेन?'
        : 'मी तुझ्यासोबत आहे. तू काय feel करतेयस ते थोडं सांग, आपण एकेक step घेऊ.';
  }

  if (language == 'Hindi') {
    if (isGreeting) {
      return 'Hi, मैं यहाँ हूँ. आज आप कैसा महसूस कर रहे हो? आराम से बताओ.';
    }
    if (isLonely || topic == 'Loneliness') {
      return 'मुझे समझ आ रहा है. अकेलापन बहुत भारी लग सकता है, लेकिन आप अभी अकेले नहीं हैं. क्या आप बता सकते हो कि किस वजह से ऐसा महसूस हो रहा है?';
    }
    if (isStress || topic == 'Anxiety & Stress' || topic == 'Panic Support') {
      return 'ऐसा लग रहा है कि आप बहुत pressure में हो. पहले एक गहरी सांस लें. अभी सबसे ज्यादा tension किस बात से हो रही है?';
    }
    if (isSad || topic == 'Depression & Sadness') {
      return 'यह सच में कठिन लग सकता है. आपकी feelings valid हैं. क्या यह आज ज्यादा महसूस हो रहा है या कुछ दिनों से चल रहा है?';
    }
    if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains('context:')) {
      return cleaned;
    }
    return 'मैं आपके साथ हूँ. आप धीरे-धीरे बताइए, हम एक-एक step लेकर समझेंगे.';
  }

  if (isGreeting) {
    return 'Hi, I’m here with you. How are you feeling right now?';
  }
  if (isLonely || topic == 'Loneliness') {
    return 'That sounds really heavy. Loneliness can feel painful, but you are not alone here. Would you like to tell me what has been making you feel this way?';
  }
  if (isStress || topic == 'Anxiety & Stress' || topic == 'Panic Support') {
    return 'It sounds like your mind and body are carrying a lot right now. Take one slow breath with me. What is the main thing creating this stress today?';
  }
  if (isSad || topic == 'Depression & Sadness') {
    return 'I’m sorry you’re feeling this way. That can be exhausting. Has something specific happened today, or has this feeling been building for a while?';
  }
  if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains('context:')) {
    return cleaned;
  }
  return hasRecentChat
      ? 'I’m listening. Based on what you shared, this matters to you. Tell me a little more so I can suggest a gentle next step.'
      : 'I’m here with you. Tell me a little more about what you are feeling, and we’ll take it one step at a time.';
}

class MentalHealthAiTab extends StatefulWidget {
  const MentalHealthAiTab({
    super.key,
    required this.sessionService,
    required this.apiService,
    required this.clinicalEngine,
    required this.doctorRecommendationService,
    this.onSignalUpdated,
  });

  final SessionService sessionService;
  final ApiService apiService;
  final ClinicalEngineService clinicalEngine;
  final DoctorRecommendationService doctorRecommendationService;
  final ValueChanged<TherapySignal>? onSignalUpdated;

  @override
  State<MentalHealthAiTab> createState() => _MentalHealthAiTabState();
}

class _MentalHealthAiTabState extends State<MentalHealthAiTab> {
  static const List<_MentalHealthTopic> _topics = [
    _MentalHealthTopic(
      title: 'Anxiety & Stress',
      subtitle: 'Grounding support for overwhelm, panic, and tension.',
      icon: Icons.bolt_outlined,
      colors: [Color(0xFF4F46E5), Color(0xFF0F766E)],
      mode: 'grounding',
    ),
    _MentalHealthTopic(
      title: 'Depression & Sadness',
      subtitle: 'Gentle encouragement and low-pressure next steps.',
      icon: Icons.favorite_border,
      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
      mode: 'support',
    ),
    _MentalHealthTopic(
      title: 'Self Confidence',
      subtitle: 'Support for self-talk, motivation, and identity.',
      icon: Icons.emoji_emotions_outlined,
      colors: [Color(0xFF0EA5E9), Color(0xFF14B8A6)],
      mode: 'support',
    ),
    _MentalHealthTopic(
      title: 'Sleep Problems',
      subtitle: 'Wind-down help, rest routines, and calming cues.',
      icon: Icons.nightlight_round,
      colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
      mode: 'sleep',
    ),
    _MentalHealthTopic(
      title: 'Mindfulness',
      subtitle: 'Present-moment attention and breathing practice.',
      icon: Icons.spa_outlined,
      colors: [Color(0xFF10B981), Color(0xFF14B8A6)],
      mode: 'grounding',
    ),
    _MentalHealthTopic(
      title: 'Anger Management',
      subtitle: 'Pause, name the trigger, and cool down safely.',
      icon: Icons.whatshot_outlined,
      colors: [Color(0xFFEA580C), Color(0xFFB91C1C)],
      mode: 'grounding',
    ),
    _MentalHealthTopic(
      title: 'Loneliness',
      subtitle: 'Connection, reassurance, and support ideas.',
      icon: Icons.groups_outlined,
      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      mode: 'support',
    ),
    _MentalHealthTopic(
      title: 'Panic Support',
      subtitle: 'Fast grounding for intense body sensations.',
      icon: Icons.shield_outlined,
      colors: [Color(0xFFB91C1C), Color(0xFF7C2D12)],
      mode: 'panic',
    ),
  ];

  Future<void> _openTopicSheet(_MentalHealthTopic topic) async {
    final action = await showModalBottomSheet<_MentalHealthTopicAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    topic.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a method to practice for this topic.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(sheetContext)
                              .pop(_MentalHealthTopicAction.chat),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Chat'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(sheetContext)
                              .pop(_MentalHealthTopicAction.call),
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('Call'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }

    final route = action == _MentalHealthTopicAction.chat
        ? MaterialPageRoute<void>(
            builder: (_) => _TopicChatScreen(
              topic: topic,
              sessionService: widget.sessionService,
              apiService: widget.apiService,
              clinicalEngine: widget.clinicalEngine,
              doctorRecommendationService: widget.doctorRecommendationService,
              onSignalUpdated: widget.onSignalUpdated,
            ),
          )
        : MaterialPageRoute<void>(
            builder: (_) => _TopicCallScreen(
              topic: topic,
              sessionService: widget.sessionService,
              apiService: widget.apiService,
              clinicalEngine: widget.clinicalEngine,
              doctorRecommendationService: widget.doctorRecommendationService,
              onSignalUpdated: widget.onSignalUpdated,
            ),
          );

    await Navigator.of(context).push(route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050816), Color(0xFF0B1020), Color(0xFFF5F8FB)],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            _bottomNavReserve(context) + 24,
          ),
          children: [
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF14B8A6)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.smart_toy_outlined,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Chatbot',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF0F172A),
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose a mental-health topic, then switch to Chat or Call.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF475569),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _MiniBadge(
                          text: 'Chat first', icon: Icons.chat_bubble_outline),
                      _MiniBadge(
                          text: 'Call optional', icon: Icons.call_outlined),
                      _MiniBadge(
                          text: 'Voice off in chat',
                          icon: Icons.mic_off_outlined),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _topics.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (context, index) {
                final topic = _topics[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _openTopicSheet(topic),
                  child: _GlassCard(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            topic.colors.first.withValues(alpha: 0.95),
                            topic.colors.last.withValues(alpha: 0.82),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(topic.icon, color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            topic.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Text(
                              topic.subtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    height: 1.35,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap to choose Chat or Call',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicChatScreen extends StatefulWidget {
  const _TopicChatScreen({
    required this.topic,
    required this.sessionService,
    required this.apiService,
    required this.clinicalEngine,
    required this.doctorRecommendationService,
    this.onSignalUpdated,
  });

  final _MentalHealthTopic topic;
  final SessionService sessionService;
  final ApiService apiService;
  final ClinicalEngineService clinicalEngine;
  final DoctorRecommendationService doctorRecommendationService;
  final ValueChanged<TherapySignal>? onSignalUpdated;

  @override
  State<_TopicChatScreen> createState() => _TopicChatScreenState();
}

class _TopicChatScreenState extends State<_TopicChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_TopicMessage> _messages = [];
  bool _busy = false;
  String _replyLanguage = 'Auto';

  @override
  void initState() {
    super.initState();
    _messages.add(
      _TopicMessage.assistant(
        text:
            'I am here for ${widget.topic.title}. Tell me what is happening and we will take it one step at a time.',
        subtitle: widget.topic.subtitle,
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Don't leave just yet!"),
          content: const Text(
              'Chat a bit more and you will unlock feedback on this chat.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Continue'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _readReplyFromResponse(Map<String, dynamic> response) {
    final candidates = <Object?>[
      response['reply'],
      response['response'],
      response['message'],
      response['text'],
      response['answer'],
      if (response['data'] is Map) (response['data'] as Map)['reply'],
      if (response['data'] is Map) (response['data'] as Map)['response'],
      if (response['data'] is Map) (response['data'] as Map)['message'],
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return '';
  }

  String _buildAssistantText({
    required Map<String, dynamic> response,
    required String userMessage,
  }) {
    final rawReply = _readReplyFromResponse(response);

    final naturalReply = _buildNaturalMindCareReply(
      userMessage: userMessage,
      rawReply: rawReply,
      topic: widget.topic.title,
      selectedLanguage: _replyLanguage,
      previousMessages: _messages,
    ).trim();

    if (naturalReply.isNotEmpty) {
      return naturalReply;
    }

    if (rawReply.isNotEmpty) {
      return _cleanMindCareBackendReply(rawReply);
    }

    return 'I am listening. Tell me a little more about what you are feeling, and we will take it one step at a time.';
  }

  Future<void> _showAssistantTyping({
    required String text,
    required String emotion,
    required String riskLevel,
  }) async {
    if (!mounted) return;

    final safeText = text.trim().isEmpty
        ? 'I am here with you. Tell me a little more.'
        : text.trim();

    setState(() {
      _messages.removeWhere((entry) => entry.loading);
      _messages.add(
        _TopicMessage.assistant(
          text: '',
          emotion: emotion,
          riskLevel: riskLevel,
        ),
      );
    });
    _scrollToBottom();

    final buffer = StringBuffer();

    for (final rune in safeText.runes) {
      if (!mounted) return;

      buffer.write(String.fromCharCode(rune));

      setState(() {
        _messages[_messages.length - 1] = _TopicMessage.assistant(
          text: buffer.toString(),
          emotion: emotion,
          riskLevel: riskLevel,
        );
      });

      if (buffer.length % 8 == 0) {
        _scrollToBottom();
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;

    final userId = widget.sessionService.user?.id;
    final history = _messages
        .where((message) => !message.loading)
        .map((message) => '${message.isUser ? 'User' : 'AI'}: ${message.text}')
        .toList(growable: false);

    setState(() {
      _messages.add(_TopicMessage.user(text));
      _messages.add(
        _TopicMessage.assistant(
          text: 'MindCare is thinking...',
          loading: true,
        ),
      );
      _input.clear();
      _busy = true;
    });
    _scrollToBottom();

    try {
      final response = await widget.apiService.chatRespond(
        message: text,
        mode: widget.topic.mode,
        userId: userId,
        context: {
          'screen': 'mental_health_topic_chat',
          'topic': widget.topic.title,
          'flow': 'topic_chat',
          'replyLanguage': _replyLanguage,
        },
        stressLevel: _stressForTopic(widget.topic.title),
        conversationHistory: history,
      );

      final emotion = (response['emotion'] ?? 'supportive').toString();
      final riskLevel = (response['riskLevel'] ?? 'low').toString();

      final backendReply = _readReplyFromResponse(response).trim();

      final assistantText = backendReply.isNotEmpty
          ? _cleanMindCareBackendReply(backendReply)
          : _buildAssistantText(
              response: response,
              userMessage: text,
            );

      await _showAssistantTyping(
        text: assistantText,
        emotion: emotion,
        riskLevel: riskLevel,
      );

      widget.clinicalEngine.recordChatMessage(
        assistantText,
        fromUser: false,
        source: 'topic_chat',
        mode: widget.topic.mode,
      );
      widget.onSignalUpdated?.call(widget.clinicalEngine.toTherapySignal());
    } catch (error) {
      if (!mounted) return;

      await _showAssistantTyping(
        text:
            'I could not reach the backend just now. Please check your internet/backend, but I am still here with you. What is the main part of ${widget.topic.title.toLowerCase()} that you want help with?',
        emotion: 'supportive',
        riskLevel: 'low',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  int _stressForTopic(String title) {
    switch (title) {
      case 'Panic Support':
      case 'Anxiety & Stress':
        return 9;
      case 'Depression & Sadness':
      case 'Loneliness':
        return 7;
      case 'Sleep Problems':
        return 6;
      default:
        return 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFF08111F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF08111F),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(widget.topic.title),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Reply language',
              initialValue: _replyLanguage,
              color: const Color(0xFF111827),
              onSelected: (value) => setState(() => _replyLanguage = value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'Auto', child: Text('Auto language')),
                PopupMenuItem(value: 'English', child: Text('English')),
                PopupMenuItem(value: 'Marathi', child: Text('Marathi')),
                PopupMenuItem(value: 'Hindi', child: Text('Hindi')),
              ],
              child: Center(
                child: _MiniBadge(
                  text: _replyLanguage,
                  icon: Icons.translate,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _MiniBadge(
                  text: 'Voice off',
                  icon: Icons.mic_off_outlined,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF08111F), Color(0xFF0F172A), Color(0xFFF8FAFC)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: _GlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient:
                                LinearGradient(colors: widget.topic.colors),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(widget.topic.icon,
                              color: const Color(0xFF0F172A), size: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.topic.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.topic.subtitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF475569),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final entry = _messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TopicMessageBubble(entry: entry),
                      );
                    },
                  ),
                ),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: _GlassCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                              labelText: 'Type your message',
                              hintText: 'Share what is on your mind',
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    18 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Text(
                    'Voice stays off in chat mode. Use Call if you want spoken support.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFCBD5E1),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCallScreen extends StatefulWidget {
  const _TopicCallScreen({
    required this.topic,
    required this.sessionService,
    required this.apiService,
    required this.clinicalEngine,
    required this.doctorRecommendationService,
    this.onSignalUpdated,
  });

  final _MentalHealthTopic topic;
  final SessionService sessionService;
  final ApiService apiService;
  final ClinicalEngineService clinicalEngine;
  final DoctorRecommendationService doctorRecommendationService;
  final ValueChanged<TherapySignal>? onSignalUpdated;

  @override
  State<_TopicCallScreen> createState() => _TopicCallScreenState();
}

class _TopicCallScreenState extends State<_TopicCallScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scroll = ScrollController();
  final List<_TopicMessage> _transcript = [];
  bool _ready = false;
  bool _listening = false;
  bool _speaking = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _captions = true;
  bool _paused = false;
  String _replyLanguage = 'Auto';

  @override
  void initState() {
    super.initState();
    _transcript.add(
      _TopicMessage.assistant(
        text:
            'Voice session ready for ${widget.topic.title}. Tap talk when you want to speak.',
        subtitle: 'Listening is off until you start it.',
      ),
    );
    _prepareVoiceTools();
  }

  Future<void> _prepareVoiceTools() async {
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
        },
      );
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      if (!mounted) return;
      setState(() => _ready = ready);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Don't leave just yet!"),
          content: const Text(
              'Chat a bit more and you will unlock feedback on this call.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Continue'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _speakReply(String text) async {
    if (_muted || !_speakerOn || _paused || text.trim().isEmpty) return;
    setState(() => _speaking = true);
    try {
      final language = _detectMindCareReplyLanguage(_replyLanguage, text);
      if (language == 'Marathi') {
        await _tts.setLanguage('mr-IN');
      } else if (language == 'Hindi') {
        await _tts.setLanguage('hi-IN');
      } else {
        await _tts.setLanguage('en-US');
      }
      await _tts.speak(text);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _sendVoiceMessage(String text) async {
    final message = text.trim();
    if (message.isEmpty || _paused) return;

    final history = _transcript
        .map((entry) => '${entry.isUser ? 'User' : 'AI'}: ${entry.text}')
        .toList(growable: false);

    setState(() {
      _transcript.add(_TopicMessage.user(message));
      _transcript.add(_TopicMessage.assistant(loading: true));
    });
    _scrollToBottom();

    try {
      final response = await widget.apiService.chatRespond(
        message: message,
        mode: widget.topic.mode,
        userId: widget.sessionService.user?.id,
        context: {
          'screen': 'mental_health_topic_call',
          'topic': widget.topic.title,
          'flow': 'topic_call',
        },
        stressLevel: _stressForTopic(widget.topic.title),
        conversationHistory: history,
      );
      final rawReply =
          (response['reply'] ?? response['response'] ?? '').toString().trim();
      final assistantText = _buildNaturalMindCareReply(
        userMessage: message,
        rawReply: rawReply,
        topic: widget.topic.title,
        selectedLanguage: _replyLanguage,
        previousMessages: _transcript,
      );

      if (!mounted) return;
      setState(() {
        _transcript.removeWhere((entry) => entry.loading);
        _transcript.add(
          _TopicMessage.assistant(
            text: assistantText,
            emotion: (response['emotion'] ?? 'supportive').toString(),
            riskLevel: (response['riskLevel'] ?? 'low').toString(),
          ),
        );
      });

      widget.clinicalEngine.recordChatMessage(
        assistantText,
        fromUser: false,
        source: 'topic_call',
        mode: widget.topic.mode,
      );
      widget.onSignalUpdated?.call(widget.clinicalEngine.toTherapySignal());
      await _speakReply(assistantText);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transcript.removeWhere((entry) => entry.loading);
        _transcript.add(
          _TopicMessage.assistant(
            text: 'I cannot connect right now, but I am still here with you.',
            emotion: 'supportive',
            riskLevel: 'low',
          ),
        );
      });
    } finally {
      if (mounted) _scrollToBottom();
    }
  }

  int _stressForTopic(String title) {
    switch (title) {
      case 'Panic Support':
      case 'Anxiety & Stress':
        return 9;
      case 'Depression & Sadness':
      case 'Loneliness':
        return 7;
      case 'Sleep Problems':
        return 6;
      default:
        return 5;
    }
  }

  Future<void> _toggleListening() async {
    if (_paused) return;
    if (!_ready) {
      await _prepareVoiceTools();
      if (!_ready) return;
    }

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      listenMode: stt.ListenMode.confirmation,
      partialResults: true,
      onResult: (result) async {
        if (!mounted) return;
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          await _speech.stop();
          setState(() => _listening = false);
          await _sendVoiceMessage(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _togglePause() async {
    if (_paused) {
      setState(() => _paused = false);
      return;
    }
    await _speech.stop();
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _paused = true;
      _listening = false;
      _speaking = false;
    });
  }

  Future<void> _endCall() async {
    await _speech.stop();
    await _tts.stop();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        final shouldExit = await _confirmExit();
        if (shouldExit && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070B18),
        appBar: AppBar(
          backgroundColor: const Color(0xFF070B18),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(widget.topic.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: PopupMenuButton<String>(
                tooltip: 'Reply language',
                initialValue: _replyLanguage,
                color: const Color(0xFF111827),
                onSelected: (value) => setState(() => _replyLanguage = value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Auto', child: Text('Auto language')),
                  PopupMenuItem(value: 'English', child: Text('English')),
                  PopupMenuItem(value: 'Marathi', child: Text('Marathi')),
                  PopupMenuItem(value: 'Hindi', child: Text('Hindi')),
                ],
                child: _MiniBadge(
                  text: _replyLanguage,
                  icon: Icons.translate,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF070B18), Color(0xFF101A33), Color(0xFFF8FAFC)],
              stops: [0.0, 0.58, 1.0],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: _GlassCard(
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient:
                                LinearGradient(colors: widget.topic.colors),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.smart_toy_rounded,
                              color: Colors.white, size: 68),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _paused
                              ? 'Paused'
                              : _speaking
                                  ? 'Speaking...'
                                  : _listening
                                      ? 'Listening...'
                                      : 'Ready to talk',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'AI voice session for ${widget.topic.title}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF475569),
                                  ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _MiniBadge(
                              text: _muted ? 'Muted' : 'Mic live',
                              icon: _muted
                                  ? Icons.mic_off_outlined
                                  : Icons.mic_outlined,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                              foregroundColor: Colors.white,
                            ),
                            _MiniBadge(
                              text: _speakerOn ? 'Speaker on' : 'Speaker off',
                              icon: _speakerOn
                                  ? Icons.volume_up_outlined
                                  : Icons.volume_off_outlined,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                              foregroundColor: Colors.white,
                            ),
                            _MiniBadge(
                              text: _captions ? 'Captions on' : 'Captions off',
                              icon: Icons.closed_caption_outlined,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                              foregroundColor: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    itemCount: _transcript.length,
                    itemBuilder: (context, index) {
                      final entry = _transcript[index];
                      if (!_captions) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TopicMessageBubble(entry: entry),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _GlassCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _paused ? null : _toggleListening,
                            icon: Icon(_listening
                                ? Icons.hearing_disabled_outlined
                                : Icons.mic_outlined),
                            label: Text(
                                _listening ? 'Listening...' : 'Tap to talk'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: () => setState(() => _muted = !_muted),
                          icon: Icon(_muted
                              ? Icons.mic_off_outlined
                              : Icons.mic_none_outlined),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () =>
                              setState(() => _speakerOn = !_speakerOn),
                          icon: Icon(_speakerOn
                              ? Icons.volume_up_outlined
                              : Icons.volume_off_outlined),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () =>
                              setState(() => _captions = !_captions),
                          icon: Icon(_captions
                              ? Icons.closed_caption_outlined
                              : Icons.closed_caption_disabled_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          label: Text(_paused ? 'Continue' : 'Pause'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _endCall,
                          icon: const Icon(Icons.call_end),
                          label: const Text('End'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicMessage {
  const _TopicMessage._({
    required this.isUser,
    required this.text,
    required this.loading,
    required this.emotion,
    required this.riskLevel,
    required this.subtitle,
  });

  const _TopicMessage.user(String text)
      : this._(
          isUser: true,
          text: text,
          loading: false,
          emotion: null,
          riskLevel: null,
          subtitle: null,
        );

  const _TopicMessage.assistant({
    String text = '',
    String? emotion,
    String? riskLevel,
    String? subtitle,
    bool loading = false,
  }) : this._(
          isUser: false,
          text: text,
          loading: loading,
          emotion: emotion,
          riskLevel: riskLevel,
          subtitle: subtitle,
        );

  final bool isUser;
  final String text;
  final bool loading;
  final String? emotion;
  final String? riskLevel;
  final String? subtitle;
}

class _TopicMessageBubble extends StatelessWidget {
  const _TopicMessageBubble({required this.entry});

  final _TopicMessage entry;

  @override
  Widget build(BuildContext context) {
    final alignment =
        entry.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        entry.isUser ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC);
    final textColor = entry.isUser ? Colors.white : const Color(0xFF0F172A);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: entry.loading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('MindCare is typing...'),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.isUser ? 'You' : 'AI',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: entry.isUser
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : const Color(0xFF0F766E),
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      if (entry.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          entry.subtitle!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: entry.isUser
                                        ? Colors.white.withValues(alpha: 0.82)
                                        : const Color(0xFF475569),
                                  ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        entry.text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: textColor,
                              height: 1.4,
                            ),
                      ),
                      if (!entry.isUser &&
                          (entry.emotion != null ||
                              entry.riskLevel != null)) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (entry.emotion != null)
                              _MiniBadge(
                                text: 'Emotion: ${entry.emotion}',
                                icon: Icons.auto_awesome,
                                backgroundColor: const Color(0xFFDCFCE7),
                                foregroundColor: const Color(0xFF166534),
                              ),
                            if (entry.riskLevel != null)
                              _MiniBadge(
                                text: 'Risk: ${entry.riskLevel}',
                                icon: Icons.shield_outlined,
                                backgroundColor: const Color(0xFFFEE2E2),
                                foregroundColor: const Color(0xFFB91C1C),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class AiChatTab extends StatefulWidget {
  const AiChatTab({
    super.key,
    required this.sessionService,
    required this.apiService,
    required this.clinicalEngine,
    required this.doctorRecommendationService,
    this.onSignalUpdated,
  });

  final SessionService sessionService;
  final ApiService apiService;
  final ClinicalEngineService clinicalEngine;
  final DoctorRecommendationService doctorRecommendationService;
  final ValueChanged<TherapySignal>? onSignalUpdated;

  @override
  State<AiChatTab> createState() => _AiChatTabState();
}

class _AiChatTabState extends State<AiChatTab> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final List<_ChatEntry> _messages = [
    const _ChatEntry.assistant(
      text: 'I am here with you. Share what is on your mind.',
      emotion: 'supportive',
      riskLevel: 'low',
      suggestions: <String>[
        'You can start with one sentence.',
      ],
    ),
  ];

  String _mode = 'support';
  bool _busy = false;
  bool _voiceReady = false;
  bool _listening = false;
  bool _aiMuted = false;
  String? _voiceError;
  String? _lastAssistantReply;
  String? _sendErrorText;
  String? _lastFailedMessage;
  String? _lastFailedMode;

  @override
  void initState() {
    super.initState();
    _prepareVoiceTools();
  }

  Future<void> _prepareVoiceTools() async {
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _voiceError = error.errorMsg;
            _listening = false;
          });
        },
      );
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.47);
      await _tts.setPitch(1.0);
      if (!mounted) return;
      setState(() {
        _voiceReady = ready;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _voiceError = error.toString();
        _voiceReady = false;
      });
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) {
      return;
    }

    debugPrint('SEND_TAPPED');
    debugPrint('MESSAGE_TEXT:$text');

    final effectiveMode = widget.clinicalEngine.resolveChatMode(
      preferredMode: _mode,
      text: text,
    );

    setState(() {
      _messages.add(_ChatEntry.user(text));
      _input.clear();
      _busy = true;
      _sendErrorText = null;
      _lastFailedMessage = null;
      _lastFailedMode = null;
    });
    _scrollToBottom();
    widget.clinicalEngine.recordChatMessage(
      text,
      fromUser: true,
      source: 'chat',
      mode: effectiveMode,
    );
    widget.onSignalUpdated?.call(widget.clinicalEngine.toTherapySignal());

    final authToken = widget.apiService.authToken;
    debugPrint(
        'CHAT_API_START tokenAttached=${authToken != null && authToken.isNotEmpty}');
    const fallbackReply =
        "I'm having trouble connecting right now, but I'm still here with you.";

    try {
      final response = await widget.sessionService.runWithSessionRetry(() {
        return widget.apiService.chatRespond(
          message: text,
          mode: effectiveMode,
          userId: 'guest',
          context: {
            'screen': 'mindcare_chat',
            'mode': effectiveMode,
            'apiBase': API_BASE_URL,
            'clinicalTone': widget.clinicalEngine.chatbotTone,
            'clinicalSeverity': widget.clinicalEngine.severityLevel,
          },
          stressLevel: widget.clinicalEngine.stressScore,
          conversationHistory: _messages
              .map((entry) => '${entry.roleLabel}: ${entry.text}')
              .toList(growable: false),
        );
      });

      debugPrint('CHAT_API_RESPONSE:${response.keys.join(',')}');

      final reply =
          (response['reply'] ?? response['response'] ?? '').toString().trim();
      final emotion = (response['emotion'] ?? 'supportive').toString();
      final riskLevel = (response['riskLevel'] ?? 'low').toString();
      final suggestions = (response['suggestions'] as List?)
              ?.map((entry) => entry.toString())
              .where((entry) => entry.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      final doctorSuggestion =
          (response['doctorSuggestion'] ?? '').toString().trim();
      final meditationSuggestion =
          (response['meditationSuggestion'] ?? '').toString().trim();
      final responseSuggestions = [
        ...suggestions,
        if (doctorSuggestion.isNotEmpty) doctorSuggestion,
        if (meditationSuggestion.isNotEmpty) meditationSuggestion,
      ];
      final assistantText = reply.isEmpty ? fallbackReply : reply;
      final needsRetry = reply.isEmpty;

      debugPrint('CHAT_API_SUCCESS');

      if (!mounted) {
        return;
      }
      setState(() {
        _lastAssistantReply = assistantText;
        _messages.add(
          _ChatEntry.assistant(
            text: assistantText,
            emotion: emotion,
            riskLevel: riskLevel,
            suggestions: responseSuggestions,
          ),
        );
        if (needsRetry) {
          _sendErrorText = 'AI reply failed. Tap to retry.';
          _lastFailedMessage = text;
          _lastFailedMode = effectiveMode;
        }
      });
      debugPrint('ASSISTANT_REPLY_ADDED');
      widget.clinicalEngine.recordChatMessage(
        assistantText,
        fromUser: false,
        source: 'chat',
        mode: effectiveMode,
      );
      widget.onSignalUpdated?.call(
        widget.clinicalEngine.toTherapySignal(),
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('CHAT_API_ERROR:$e');
      if (!mounted) {
        return;
      }
      setState(() {
        _sendErrorText = 'AI reply failed. Tap to retry.';
        _lastFailedMessage = text;
        _lastFailedMode = effectiveMode;
        _messages.add(
          _ChatEntry.assistant(
            text: fallbackReply,
            emotion: widget.clinicalEngine.emotion,
            riskLevel: 'low',
            suggestions: const [
              'Retry once the connection is stable.',
              'Stay with the conversation and keep it short.',
            ],
          ),
        );
      });
      widget.clinicalEngine.recordChatMessage(
        fallbackReply,
        fromUser: false,
        source: 'chat-fallback',
      );
      widget.onSignalUpdated?.call(
        widget.clinicalEngine.toTherapySignal(),
      );
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _retryLastFailedSend() async {
    final failedMessage = _lastFailedMessage;
    if (failedMessage == null || failedMessage.trim().isEmpty || _busy) {
      return;
    }

    setState(() {
      _input.text = failedMessage;
      if (_lastFailedMode != null) {
        _mode = _lastFailedMode!;
      }
      _sendErrorText = null;
    });
    await _send();
  }

  void _setMode(String mode) {
    setState(() => _mode = mode);
  }

  Future<void> _speakLastReply() async {
    if (_aiMuted) {
      return;
    }
    final text = _lastAssistantReply;
    if (text == null || text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
  }

  Future<void> _toggleListening() async {
    if (!_voiceReady) {
      await _prepareVoiceTools();
      if (!_voiceReady) return;
    }

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _voiceError = null;
      _listening = true;
    });

    await _speech.listen(
      listenMode: stt.ListenMode.confirmation,
      partialResults: true,
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _input.text = result.recognizedWords;
          _input.selection = TextSelection.fromPosition(
            TextPosition(offset: _input.text.length),
          );
        });
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _speech.stop();
          _send();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final composerInset = bottomInset > 0 ? bottomInset : safeBottom;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFB91C1C),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'CHAT PIPELINE DEBUG BUILD',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: _ChatHeader(
            isBusy: _busy,
            mode: _mode,
            onModeChanged: _setMode,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final entry = _messages[index];
              return _ChatBubble(entry: entry);
            },
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFA),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x1A0F766E)),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('MindCare is typing...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_sendErrorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _retryLastFailedSend,
                icon: const Icon(Icons.refresh),
                label: Text(_sendErrorText!),
              ),
            ),
          ),
        AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: composerInset),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ComposerPanel(
              controller: _input,
              busy: _busy,
              onSend: _send,
              onVoicePressed: _toggleListening,
              listening: _listening,
              voiceReady: _voiceReady,
              aiMuted: _aiMuted,
              mode: _mode,
              voiceError: _voiceError,
              lastAssistantReply: _lastAssistantReply,
              onSpeakLastReply: _speakLastReply,
              onStopSpeaking: _stopSpeaking,
              onAiMutedChanged: (value) => setState(() {
                _aiMuted = value;
              }),
              doctorRecommendationService: widget.doctorRecommendationService,
            ),
          ),
        ),
      ],
    );
  }
}

class ClinicalPlanningTab extends StatelessWidget {
  const ClinicalPlanningTab({
    super.key,
    required this.clinicalEngine,
    required this.doctorRecommendationService,
    required this.llmChatbotService,
    required this.moodPredictionService,
    required this.emotionDetectionService,
  });

  final ClinicalEngineService clinicalEngine;
  final DoctorRecommendationService doctorRecommendationService;
  final LlmChatbotService llmChatbotService;
  final MoodPredictionService moodPredictionService;
  final EmotionDetectionService emotionDetectionService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: clinicalEngine,
      builder: (context, _) {
        final recommendations = clinicalEngine.recommendations;
        final grounding = clinicalEngine.groundingSuggestions;
        final sleep = clinicalEngine.sleepSuggestions;
        final hydration = clinicalEngine.hydrationReminders;
        final therapy = clinicalEngine.therapyRecommendations;
        final events = clinicalEngine.events;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeroCard(
              title: 'Meditation Hub',
              subtitle:
                  'Live scoring from chat, support, sound therapy, hydration, and persisted memory. The tab changes as the conversation changes.',
              chips: [
                'Severity ${clinicalEngine.severityLevel}',
                'Stress ${clinicalEngine.stressScore}/100',
                'Tone ${clinicalEngine.chatbotTone}',
              ],
            ),
            const SizedBox(height: 14),
            const _MeditationVideoCard(),
            const SizedBox(height: 14),
            _SectionHeader(
              title: 'Live signal',
              subtitle:
                  'The engine recalculates after each message and check-in.',
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Meditation Progress',
              body:
                  'Emotion ${clinicalEngine.emotion} • trend ${clinicalEngine.moodTrend} • confidence ${(clinicalEngine.confidence * 100).round()}% • hydration streak ${clinicalEngine.hydrationStreakDays} day(s) • sound sessions ${clinicalEngine.soundUsageSessions}',
              icon: Icons.favorite_border,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Severity recommendation',
              body: doctorRecommendationService.buildRecommendation(
                clinicalEngine.severityLevel == 'critical'
                    ? 'high'
                    : clinicalEngine.severityLevel == 'high'
                        ? 'high'
                        : clinicalEngine.severityLevel == 'moderate'
                            ? 'moderate'
                            : 'low',
              ),
              icon: Icons.warning_amber_rounded,
              accent: clinicalEngine.severityLevel == 'critical' ||
                      clinicalEngine.severityLevel == 'high'
                  ? const Color(0xFFB45309)
                  : const Color(0xFF0F766E),
            ),
            const SizedBox(height: 14),
            _SectionHeader(
              title: 'Adaptive recommendations',
              subtitle:
                  'These update after chat, hydration, support, and sound usage.',
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Recommendations',
              body: recommendations.isEmpty
                  ? 'No active recommendation yet.'
                  : recommendations.join('\n'),
              icon: Icons.auto_awesome,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Grounding suggestions',
              body: grounding.isEmpty
                  ? 'No grounding suggestion yet.'
                  : grounding.join('\n'),
              icon: Icons.anchor_outlined,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Sleep suggestions',
              body:
                  sleep.isEmpty ? 'No sleep suggestion yet.' : sleep.join('\n'),
              icon: Icons.nights_stay_outlined,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Hydration reminders',
              body: hydration.isEmpty
                  ? 'No hydration reminder yet.'
                  : hydration.join('\n'),
              icon: Icons.water_drop_outlined,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Meditation Recommendations',
              body: therapy.isEmpty
                  ? 'No therapy recommendation yet.'
                  : therapy.join('\n'),
              icon: Icons.spa_outlined,
            ),
            const SizedBox(height: 14),
            _SectionHeader(
              title: 'Meditation Actions',
              subtitle: 'Use these to drive real updates into the engine.',
            ),
            const SizedBox(height: 10),
            _GlassCard(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.water_drop_outlined, size: 18),
                    label: const Text('Log water 250 ml'),
                    onPressed: () =>
                        clinicalEngine.recordHydration(consumedMl: 250),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.local_drink_outlined, size: 18),
                    label: const Text('Log water 500 ml'),
                    onPressed: () =>
                        clinicalEngine.recordHydration(consumedMl: 500),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.favorite_border, size: 18),
                    label: const Text('Calm check-in'),
                    onPressed: () => clinicalEngine.recordMoodCheckin(
                      mood: 'calm',
                      stress: 10,
                      energy: 8,
                      notes: 'Manual calm check-in',
                      tags: const ['calm'],
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Stress spike'),
                    onPressed: () => clinicalEngine.recordMoodCheckin(
                      mood: 'stressed',
                      stress: 82,
                      energy: 3,
                      notes: 'Manual stress spike check-in',
                      tags: const ['stress', 'panic'],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionHeader(
              title: 'Memory',
              subtitle:
                  'Persisted locally and refreshed from backend mood history.',
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Counter state',
              body:
                  'Mood logs ${clinicalEngine.moodHistoryCount} • support interactions ${clinicalEngine.supportInteractionCount} • sound sessions ${clinicalEngine.soundUsageSessions} • hydration consumed ${clinicalEngine.hydrationConsumedMl} ml of ${clinicalEngine.hydrationGoalMl} ml',
              icon: Icons.history,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Recent signals',
              body: clinicalEngine.recentSignals.isEmpty
                  ? 'No live signals yet.'
                  : clinicalEngine.recentSignals.join(' • '),
              icon: Icons.timeline,
            ),
            const SizedBox(height: 10),
            _InfoCard(
              title: 'Recent events',
              body: events.isEmpty
                  ? 'No meditation activity yet.'
                  : events
                      .take(4)
                      .map((event) => '${event.kind}: ${event.text}')
                      .join('\n\n'),
              icon: Icons.notes,
            ),
          ],
        );
      },
    );
  }
}

class SoundTherapyTab extends StatelessWidget {
  const SoundTherapyTab({
    super.key,
    required this.service,
    required this.signalListenable,
  });

  final SoundTherapyService service;
  final ValueListenable<TherapySignal> signalListenable;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        return ValueListenableBuilder<TherapySignal>(
          valueListenable: signalListenable,
          builder: (context, signal, __) {
            final recommendedTracks = service
                .recommendedTrackIdsForSignal(signal)
                .map(service.trackById)
                .whereType<SoundTherapyTrack>()
                .toList(growable: false);
            final activeTrack = service.currentTrack;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _HeroCard(
                  title: 'Sound therapy',
                  subtitle: '',
                  trailing: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0x0F0F766E),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      service.isPlaying ? Icons.graphic_eq : Icons.headphones,
                      color: const Color(0xFF0F766E),
                    ),
                  ),
                  chips: [
                    'Sound streak: Day ${service.soundStreakDays}',
                  ],
                  children: [
                    const SizedBox(height: 14),
                    _InfoCard(
                      title: 'Sound Streak',
                      body:
                          'Day ${service.soundStreakDays}. Keep your mental health healthy and maintain your streak.',
                      icon: Icons.local_fire_department_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionHeader(
                  title: 'Recommended for you',
                  subtitle:
                      'Auto-mapped from mood, risk, and current app context.',
                ),
                const SizedBox(height: 10),
                ...recommendedTracks.map(
                  (track) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SoundTrackCard(
                      service: service,
                      track: track,
                      highlighted: activeTrack?.id == track.id,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _SectionHeader(
                  title: 'All sounds',
                  subtitle:
                      'Sleep, rain, ocean, forest, white noise, breathing, anxiety relief, and focus.',
                ),
                const SizedBox(height: 10),
                ...service.tracks.map(
                  (track) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SoundTrackCard(
                      service: service,
                      track: track,
                      highlighted: activeTrack?.id == track.id,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _SectionHeader(
                  title: 'Now playing',
                  subtitle:
                      'Timer, play/pause, completion, and premium unlock.',
                ),
                const SizedBox(height: 10),
                _NowPlayingCard(
                  service: service,
                  track: activeTrack,
                ),
                const SizedBox(height: 14),
                _SectionHeader(
                  title: 'Sound history',
                  subtitle: 'Recently completed and previewed sessions.',
                ),
                const SizedBox(height: 10),
                if (service.history.isEmpty)
                  const _InfoCard(
                    title: 'No sound sessions yet',
                    body: 'Play a sound to begin your history and streak.',
                    icon: Icons.history,
                  )
                else
                  ...service.history.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _HistoryTile(entry: entry),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  String _soundRecommendationText(TherapySignal signal) {
    final mood = signal.moodHint.toLowerCase();
    final risk = signal.riskLevel.toLowerCase();
    if (risk == 'high' || mood.contains('anx')) {
      return 'Recommended: calming breathing and rain for nervous system downshifting.';
    }
    if (mood.contains('sleep')) {
      return 'Recommended: sleep sounds or white noise for a smoother wind-down.';
    }
    if (mood.contains('focus')) {
      return 'Recommended: focus ambience to support attention and reduce distractions.';
    }
    if (mood.contains('stress')) {
      return 'Recommended: ocean waves or forest sounds for steady relaxation.';
    }
    return 'Recommended: breathing audio or rain for a calm reset.';
  }
}

class SupportTab extends StatefulWidget {
  const SupportTab({
    super.key,
    required this.sessionService,
    required this.socketService,
    required this.clinicalEngine,
  });

  final SessionService sessionService;
  final SocketService socketService;
  final ClinicalEngineService clinicalEngine;

  @override
  State<SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<SupportTab> {
  int _tab = 0;
  int _friendsSubTab = 0;
  int _genderIndex = 2;
  bool _online = true;
  bool _loadingSupport = false;
  String? _supportError;
  Map<String, dynamic>? _streakData;
  bool _waterCompletedToday = false;
  bool _streakLoading = false;
  String? _streakMessage;

  Timer? _incomingFriendCallTimer;
  bool _incomingFriendCallVisible = false;
  String? _lastIncomingFriendCallId;

  int _practiceCalls = 0;
  int _weeklyCalls = 0;
  int _totalMinutes = 0;
  int _totalCoins = 0;
  double _rating = 0;

  final List<_SupportPerson> _practiceUsers = [];
  final List<_SupportPerson> _friends = [];
  final List<_SupportRequest> _requests = [];
  final List<_SupportWeekBar> _bars = [
    _SupportWeekBar('SAT', 0, 0),
    _SupportWeekBar('SUN', 0, 0),
    _SupportWeekBar('MON', 0, 0),
    _SupportWeekBar('TUE', 0, 0),
    _SupportWeekBar('WED', 0, 0),
    _SupportWeekBar('THU', 0, 0),
    _SupportWeekBar('FRI', 0, 0),
  ];

  String get _displayName =>
      widget.sessionService.user?.displayName ??
      widget.sessionService.user?.alias ??
      'You';

  String? get _token => widget.sessionService.apiService.authToken;
  ApiService get _api => widget.sessionService.apiService;

  @override
  void initState() {
    super.initState();
    _loadSupportData();
    _loadStreak();
    _startIncomingFriendCallPolling();
  }

  @override
  void dispose() {
    _incomingFriendCallTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSupportData() async {
    if (_token == null || _token!.isEmpty) return;
    setState(() {
      _loadingSupport = true;
      _supportError = null;
    });

    try {
      final results = await Future.wait<Map<String, dynamic>>([
        _api.getCallHistory(),
        _api.getCallProgress(),
        _api.getAvailableUsers(),
        _api.getFriendRequests(),
        _api.getFriends(),
      ]);

      final history = results[0]['calls'];
      final progress = results[1]['progress'];
      final availableUsers = results[2]['users'];
      final requests = results[3];
      final friends = results[4]['friends'];

      final calls = history is List ? history : const [];
      final users = availableUsers is List ? availableUsers : const [];
      final friendList = friends is List ? friends : const [];

      _rebuildWeeklyBars(calls);
      _applyAvailableUsers(users, calls, friendList, requests);
      _applyFriends(friendList);
      _applyRequests(requests);

      if (progress is Map<String, dynamic>) {
        _practiceCalls = _asInt(progress['totalCalls']);
        _weeklyCalls = _asInt(progress['weeklyCalls']);
        _totalMinutes = _asInt(progress['totalMinutes']);
        _totalCoins = _asInt(progress['totalCoins']);
        _rating = _asDouble(progress['averageRating']);
      }
    } catch (error) {
      _supportError = error.toString();
    } finally {
      if (mounted) setState(() => _loadingSupport = false);
    }
  }

  Future<void> _loadStreak() async {
    try {
      final data = await _api.getStreak();
      if (!mounted) return;
      setState(() {
        _streakData = data['streak'] as Map<String, dynamic>?;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _streakMessage = 'Streak could not be loaded.';
      });
    }
  }

  Future<void> _saveWaterCompletedToday(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    await prefs.setString('practice_water_date', today);
    await prefs.setBool('practice_water_completed', value);
  }

  Future<void> _completeStreak() async {
    setState(() {
      _streakLoading = true;
      _streakMessage = null;
    });

    try {
      final data = await _api.completeStreak(
        waterCompleted: _waterCompletedToday,
      );

      if (!mounted) return;

      setState(() {
        _streakData = data['streak'] as Map<String, dynamic>?;
        _streakMessage = data['completed'] == true
            ? 'Day ${_streakData?['currentStreak'] ?? 1} streak completed!'
            : data['reason']?.toString() ??
                'Complete 10 min call + water task to unlock streak.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _streakMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _streakLoading = false;
        });
      }
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _userIdFrom(dynamic raw) {
    if (raw is Map) {
      return (raw['_id'] ?? raw['id'] ?? '').toString();
    }
    return '';
  }

  String _userNameFrom(dynamic raw) {
    if (raw is Map) {
      final value = raw['displayName'] ??
          raw['alias'] ??
          raw['username'] ??
          raw['email'] ??
          raw['_id'] ??
          raw['id'];
      return _cleanPeerName(value?.toString() ?? 'Co-learner');
    }
    return 'Co-learner';
  }

  Set<String> _friendIdsFrom(List<dynamic> friends) {
    return friends.map(_userIdFrom).where((id) => id.isNotEmpty).toSet();
  }

  Set<String> _outgoingReceiverIds(Map<String, dynamic> requests) {
    final outgoing = requests['outgoing'];
    if (outgoing is! List) return <String>{};
    return outgoing
        .map((request) =>
            request is Map ? _userIdFrom(request['receiverId']) : '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Set<String> _incomingSenderIds(Map<String, dynamic> requests) {
    final incoming = requests['incoming'];
    if (incoming is! List) return <String>{};
    return incoming
        .map(
            (request) => request is Map ? _userIdFrom(request['senderId']) : '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  int _lastDurationForUser(String name, List<dynamic> calls) {
    final normalized =
        name.toLowerCase().replaceAll(RegExp(r'\\s+'), ' ').trim();
    var latestSeconds = 0;
    DateTime? latestDate;

    for (final raw in calls) {
      if (raw is! Map) continue;
      final peer = _cleanPeerName((raw['peerAlias'] ?? '').toString())
          .toLowerCase()
          .replaceAll(RegExp(r'\\s+'), ' ')
          .trim();
      if (peer != normalized) continue;
      final createdAt = DateTime.tryParse((raw['createdAt'] ?? '').toString());
      if (latestDate == null ||
          (createdAt != null && createdAt.isAfter(latestDate))) {
        latestDate = createdAt;
        latestSeconds = _asInt(raw['durationSeconds']);
      }
    }
    return latestSeconds;
  }

  void _applyAvailableUsers(
    List<dynamic> users,
    List<dynamic> calls,
    List<dynamic> friends,
    Map<String, dynamic> requests,
  ) {
    final friendIds = _friendIdsFrom(friends);
    final outgoingIds = _outgoingReceiverIds(requests);
    final incomingIds = _incomingSenderIds(requests);

    _practiceUsers.clear();
    for (final raw in users) {
      final id = _userIdFrom(raw);
      if (id.isEmpty) continue;
      final name = _userNameFrom(raw);
      final duration = _lastDurationForUser(name, calls);
      final relation = friendIds.contains(id)
          ? _SupportRelation.friend
          : incomingIds.contains(id)
              ? _SupportRelation.incoming
              : outgoingIds.contains(id)
                  ? _SupportRelation.sent
                  : _SupportRelation.none;
      _practiceUsers.add(
        _SupportPerson(
          id,
          name,
          duration > 0
              ? 'Last call ${_formatDuration(duration)}'
              : 'Available co-learner',
          relation,
          _colorForName(name),
          true,
          duration,
        ),
      );
    }
  }

  void _applyFriends(List<dynamic> friends) {
    _friends.clear();
    for (final raw in friends) {
      final id = _userIdFrom(raw);
      if (id.isEmpty) continue;
      final name = _userNameFrom(raw);
      _friends.add(
        _SupportPerson(
          id,
          name,
          'Friend',
          _SupportRelation.friend,
          _colorForName(name),
          true,
          0,
        ),
      );
    }
  }

  void _applyRequests(Map<String, dynamic> requests) {
    _requests.clear();
    final incoming = requests['incoming'];
    if (incoming is! List) return;
    for (final raw in incoming) {
      if (raw is! Map) continue;
      final requestId = (raw['_id'] ?? raw['id'] ?? '').toString();
      final sender = raw['senderId'];
      final name = _userNameFrom(sender);
      final createdAt =
          DateTime.tryParse((raw['createdAt'] ?? '').toString())?.toLocal();
      final date = createdAt == null
          ? ''
          : '${createdAt.day}/${createdAt.month}/${createdAt.year}';
      if (requestId.isEmpty) continue;
      _requests
          .add(_SupportRequest(requestId, name, date, _colorForName(name)));
    }
  }

  void _rebuildWeeklyBars(List<dynamic> calls) {
    for (final bar in _bars) {
      bar.lastWeek = 0;
      bar.thisWeek = 0;
    }

    final now = DateTime.now();
    for (final raw in calls) {
      if (raw is! Map) continue;
      final seconds = _asInt(raw['durationSeconds']);
      final minutes = (seconds / 60).ceil();
      final createdAt =
          DateTime.tryParse((raw['createdAt'] ?? '').toString())?.toLocal();
      if (createdAt == null) continue;

      final diff = now.difference(createdAt).inDays;
      final index = createdAt.weekday % _bars.length;
      if (diff <= 6) {
        _bars[index].thisWeek += minutes;
      } else if (diff <= 13) {
        _bars[index].lastWeek += minutes;
      }
    }
  }

  Color _colorForName(String name) {
    const colors = [
      Color(0xFF4F46E5),
      Color(0xFF14B8A6),
      Color(0xFF6366F1),
      Color(0xFFF59E0B),
      Color(0xFF0F766E),
      Color(0xFF22C55E),
    ];
    final index =
        name.codeUnits.fold<int>(0, (sum, item) => sum + item) % colors.length;
    return colors[index];
  }

  String _cleanPeerName(String value) {
    final cleaned =
        value.replaceAll('_', ' ').replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Co-learner';
    return cleaned
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins <= 0) return '${secs}s';
    if (secs == 0) return '${mins}min';
    return '${mins}min ${secs}s';
  }

  _SupportPerson _nextCandidate() {
    if (_practiceUsers.isEmpty) {
      return const _SupportPerson(
        'co_learner',
        'Co-learner',
        'Available co-learner',
        _SupportRelation.none,
        Color(0xFF6366F1),
        true,
        0,
      );
    }
    final index =
        (_practiceCalls + _practiceUsers.length) % _practiceUsers.length;
    return _practiceUsers[index];
  }

  Future<void> _sendFriendRequest(_SupportPerson person) async {
    if (person.lastDurationSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request unlocks only after a completed call.'),
        ),
      );
      return;
    }

    try {
      await _api.sendFriendRequest(receiverId: person.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${person.name}.')),
      );
      await _loadSupportData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request failed: $error')),
      );
    }
  }

  Future<void> _acceptPracticeRequest(_SupportPerson person) async {
    setState(() => _friendsSubTab = 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Open Request tab to accept this request.')),
    );
  }

  Future<void> _acceptRequest(_SupportRequest request) async {
    try {
      await _api.respondFriendRequest(requestId: request.id, action: 'accept');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${request.name} is now your friend.')),
      );
      await _loadSupportData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $error')),
      );
    }
  }

  Future<void> _deleteRequest(_SupportRequest request) async {
    try {
      await _api.respondFriendRequest(requestId: request.id, action: 'reject');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${request.name} request deleted.')),
      );
      await _loadSupportData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $error')),
      );
    }
  }

  Future<bool> _ensureCallToken() async {
    var currentToken = widget.sessionService.apiService.authToken;

    if (currentToken != null && currentToken.isNotEmpty) {
      return true;
    }

    try {
      final alias = widget.sessionService.user?.alias ??
          widget.sessionService.user?.displayName ??
          _displayName;

      await widget.sessionService.continueAsGuest(alias: alias);

      currentToken = widget.sessionService.apiService.authToken;

      if (currentToken != null && currentToken.isNotEmpty) {
        return true;
      }
    } catch (error) {
      debugPrint('CALL_AUTH_REFRESH_FAILED:$error');
    }

    if (!mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please sign in again before starting a call.'),
      ),
    );

    return false;
  }

  void _startIncomingFriendCallPolling() {
    _incomingFriendCallTimer?.cancel();

    _incomingFriendCallTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkIncomingFriendCall(),
    );

    _checkIncomingFriendCall();
  }

  Future<void> _checkIncomingFriendCall() async {
    if (_incomingFriendCallVisible) return;

    final token = widget.sessionService.apiService.authToken;
    if (token == null || token.isEmpty) return;

    try {
      final response =
          await widget.sessionService.apiService.getIncomingFriendCall();

      final hasIncoming = response['hasIncomingCall'] == true;
      final call = response['call'];

      if (!hasIncoming || call is! Map<String, dynamic>) return;

      final callId = call['id']?.toString() ?? '';
      if (callId.isEmpty) return;

      if (_lastIncomingFriendCallId == callId) return;

      if (!mounted) return;

      _incomingFriendCallVisible = true;
      _lastIncomingFriendCallId = callId;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IncomingFriendCallScreen(
            apiService: widget.sessionService.apiService,
            call: call,
          ),
        ),
      );

      _incomingFriendCallVisible = false;

      if (mounted) {
        await _loadSupportData();
        await _loadStreak();
      }
    } catch (error) {
      debugPrint('INCOMING_FRIEND_CALL_POLL_ERROR: $error');
    }
  }

  Future<void> _startRandomCoLearnerCall() async {
    if (!await _ensureCallToken()) return;
    final gender = _genderIndex == 0
        ? 'male'
        : _genderIndex == 1
            ? 'female'
            : 'any';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MindcareConnectScreen(
          apiService: widget.sessionService.apiService,
          gender: gender,
        ),
      ),
    );

    if (mounted) {
      await _loadSupportData();
      await _loadStreak();
    }
  }

  Future<void> _startCall(_SupportPerson person) async {
    if (!await _ensureCallToken()) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendRingingScreen(
          apiService: widget.sessionService.apiService,
          targetUserId: person.id,
          peerName: person.name,
        ),
      ),
    );

    if (mounted) {
      await _loadSupportData();
      await _loadStreak();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildPracticePage(),
      _buildFriendsPage(),
      _buildProgressPage(),
    ];

    return Container(
      color: const Color(0xFF0B0B0C),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SupportProfileHeader(displayName: _displayName),
            _SupportMainTabs(
              selected: _tab,
              onChanged: (value) => setState(() => _tab = value),
            ),
            if (_supportError != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Support sync issue: $_supportError',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Expanded(
              child: _loadingSupport
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF22C55E)),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSupportData,
                      child: pages[_tab],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticePage() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(30, 22, 30, _bottomNavReserve(context) + 24),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _loadSupportData,
            icon: const Icon(Icons.sync, color: Color(0xFF9CA3AF)),
            label: const Text(
              'Refresh',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 18,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF374151)),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.people_alt_outlined,
                size: 60,
                color: Color(0xFF22C55E),
              ),
              SizedBox(height: 12),
              Text(
                'Connect with an online co-learner',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'We will automatically connect you with a suitable online user.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        _ConnectPanel(
          selectedIndex: _genderIndex,
          onGenderChanged: (index) => setState(() => _genderIndex = index),
          onConnect: _startRandomCoLearnerCall,
        ),
        const SizedBox(height: 28),
        Row(
          children: const [
            Expanded(
              child: Text(
                'Recent practice partners',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_practiceUsers.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(
              child: Text(
                'Complete a call to see recent users here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 18,
                ),
              ),
            ),
          )
        else
          for (final person in _practiceUsers) ...[
            if (person.lastDurationSeconds > 0) ...[
              _PracticeUserTile(
                person: person,
                onAdd: () => _sendFriendRequest(person),
                onAccept: () => _acceptPracticeRequest(person),
                onCall: () => _startCall(person),
              ),
              const SizedBox(height: 20),
            ],
          ],
      ],
    );
  }

  Widget _buildFriendsPage() {
    final showRequests = _friendsSubTab == 1;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(30, 28, 30, _bottomNavReserve(context) + 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _FriendSubTab(
                label: 'Friends',
                icon: Icons.group_outlined,
                active: !showRequests,
                onTap: () => setState(() => _friendsSubTab = 0),
              ),
            ),
            Expanded(
              child: _FriendSubTab(
                label: 'Request',
                icon: Icons.group_add_outlined,
                active: showRequests,
                onTap: () => setState(() => _friendsSubTab = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        if (!showRequests) ...[
          Row(
            children: [
              _SupportAvatar(
                  name: _displayName, color: const Color(0xFF0F766E)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'You\n${_online ? 'Online' : 'Offline'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: _online,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF16A34A),
                onChanged: (value) => setState(() => _online = value),
              ),
            ],
          ),
          const SizedBox(height: 34),
          Row(
            children: [
              Text(
                'Online Friends (${_friends.length})',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22C55E),
                  side: const BorderSide(color: Color(0xFF166534)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _loadSupportData,
                icon: const Icon(Icons.sync),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_friends.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(
                child: Text(
                  'No friends yet. Send a request after a completed call.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 18),
                ),
              ),
            ),
          for (final friend in _friends) ...[
            _OnlineFriendTile(person: friend, onCall: () => _startCall(friend)),
            const SizedBox(height: 24),
          ],
        ] else ...[
          if (_requests.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text(
                  'No pending friend requests.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 18),
                ),
              ),
            ),
          for (final request in _requests) ...[
            _RequestTile(
              request: request,
              onAccept: () => _acceptRequest(request),
              onDelete: () => _deleteRequest(request),
            ),
            const SizedBox(height: 26),
          ],
        ],
      ],
    );
  }

  Widget _buildStreakCard() {
    final streak = _streakData;
    final current = _asInt(streak?['currentStreak']);
    final longest = _asInt(streak?['longestStreak']);
    final totalDays = _asInt(streak?['totalCompletedDays']);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3F4654)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🔥',
                style: TextStyle(fontSize: 34),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Day $current Streak',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: _loadStreak,
                icon: const Icon(Icons.sync, color: Color(0xFFCBD5E1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Longest: $longest days • Total completed: $totalDays days',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _waterCompletedToday,
            onChanged: (value) {
              setState(() {
                _waterCompletedToday = value;
              });
              _saveWaterCompletedToday(value);
            },
            title: const Text(
              'Water intake task completed today',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Streak unlocks after 10 minutes of completed calls + water task.',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            activeThumbColor: Color(0xFF22C55E),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _streakLoading ? null : _completeStreak,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _streakLoading ? 'Checking...' : 'Check & Complete Streak',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          if (_streakMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _streakMessage!,
              style: const TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressPage() {
    final lastWeekTotal =
        _bars.fold<int>(0, (sum, item) => sum + item.lastWeek);
    final thisWeekTotal =
        _bars.fold<int>(0, (sum, item) => sum + item.thisWeek);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(30, 56, 30, _bottomNavReserve(context) + 24),
      children: [
        _buildStreakCard(),
        const SizedBox(height: 24),
        Row(
          children: const [
            Expanded(
              child: Text(
                'Your Weekly Call Activity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              'Real data',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 22,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF3F4654)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ProgressMetric(
                      emoji: '📞',
                      value: '$_practiceCalls',
                      label: 'Practice Calls\n(All saved calls)',
                    ),
                  ),
                  Container(
                      width: 2, height: 74, color: const Color(0xFF3F4654)),
                  Expanded(
                    child: _ProgressMetric(
                      emoji: '⭐',
                      value: _rating <= 0 ? '-' : _rating.toStringAsFixed(1),
                      label: 'Call Rating',
                    ),
                  ),
                ],
              ),
              const Divider(height: 34, color: Color(0xFF3F4654)),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Total min : ',
                        style: const TextStyle(
                            color: Color(0xFFB8B8C3), fontSize: 20),
                        children: [
                          TextSpan(
                            text: '$_totalMinutes',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'This week : ',
                        style: const TextStyle(
                            color: Color(0xFFB8B8C3), fontSize: 20),
                        children: [
                          TextSpan(
                            text: '$_weeklyCalls calls',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Coins earned: $_totalCoins',
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              _WeeklyChart(records: _bars),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _ChartLegend(
                    color: const Color(0xFFFACC15),
                    label: 'Last week:${_formatMinutes(lastWeekTotal)}',
                  ),
                  _ChartLegend(
                    color: const Color(0xFF6366F1),
                    label: 'This week:${_formatMinutes(thisWeekTotal)}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          padding: const EdgeInsets.all(24),
          child: const Text(
            'Progress is now calculated from completed call history, not static demo data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              height: 1.5,
              fontSize: 21,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }
}

class _SupportFeedback {
  const _SupportFeedback(this.rating, this.feedback);

  final int rating;
  final String feedback;
}

enum _SupportRelation { none, sent, incoming, friend }

class _SupportPerson {
  const _SupportPerson(
    this.id,
    this.name,
    this.callSummary,
    this.relation,
    this.color,
    this.online,
    this.lastDurationSeconds,
  );

  final String id;
  final String name;
  final String callSummary;
  final _SupportRelation relation;
  final Color color;
  final bool online;
  final int lastDurationSeconds;

  _SupportPerson copyWith({
    _SupportRelation? relation,
    bool? online,
    int? lastDurationSeconds,
  }) {
    return _SupportPerson(
      id,
      name,
      callSummary,
      relation ?? this.relation,
      color,
      online ?? this.online,
      lastDurationSeconds ?? this.lastDurationSeconds,
    );
  }
}

class _SupportRequest {
  const _SupportRequest(this.id, this.name, this.date, this.color);

  final String id;
  final String name;
  final String date;
  final Color color;
}

class _SupportWeekBar {
  _SupportWeekBar(this.day, this.lastWeek, this.thisWeek);

  final String day;
  int lastWeek;
  int thisWeek;
}

class _SupportProfileHeader extends StatelessWidget {
  const _SupportProfileHeader({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1C1F2E),
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SupportAvatar(name: displayName, color: const Color(0xFF0F766E)),
              Positioned(
                right: -3,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFF1C1F2E), width: 2),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFF78350F),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          _SupportTopPill(
            icon: Icons.leaderboard_outlined,
            label: '1',
            color: const Color(0xFF6366F1),
          ),
          const SizedBox(width: 12),
          _SupportTopPill(
            icon: Icons.local_fire_department,
            label: '2',
            color: const Color(0xFFF97316),
          ),
        ],
      ),
    );
  }
}

class _SupportMainTabs extends StatelessWidget {
  const _SupportMainTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Practice', 'Friends', 'Progress'];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Color(0xFF333845))),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: selected == index
                        ? const Color(0xFF20233F)
                        : const Color(0xFF111827),
                    border: Border(
                      bottom: BorderSide(
                        color: selected == index
                            ? const Color(0xFF6366F1)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected == index
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF8B8B93),
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupportAvatar extends StatelessWidget {
  const _SupportAvatar({
    required this.name,
    required this.color,
    this.size = 68,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.65), color.withValues(alpha: 0.9)],
        ),
        border: Border.all(color: const Color(0xFF6366F1), width: 3),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SupportTopPill extends StatelessWidget {
  const _SupportTopPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFF414756)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeUserTile extends StatelessWidget {
  const _PracticeUserTile({
    required this.person,
    required this.onAdd,
    required this.onAccept,
    required this.onCall,
  });

  final _SupportPerson person;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    Widget action;
    switch (person.relation) {
      case _SupportRelation.friend:
        action = TextButton(
          onPressed: onCall,
          child: const Text(
            'Friend',
            style: TextStyle(color: Color(0xFF6366F1), fontSize: 18),
          ),
        );
        break;
      case _SupportRelation.incoming:
        action = FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
          ),
          child: const Text('Respond'),
        );
        break;
      case _SupportRelation.sent:
        action = const Text(
          'Request Sent',
          style: TextStyle(color: Color(0xFF8B8B93), fontSize: 16),
        );
        break;
      case _SupportRelation.none:
        action = FilledButton(
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Friend'),
        );
        break;
    }

    return Row(
      children: [
        _SupportAvatar(name: person.name, color: person.color),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            '${person.name}\n${person.callSummary}',
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
              fontSize: 21,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        action,
      ],
    );
  }
}

class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({
    required this.selectedIndex,
    required this.onGenderChanged,
    required this.onConnect,
  });

  final int selectedIndex;
  final ValueChanged<int> onGenderChanged;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Male', 'Female', 'Any'];
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFB7952D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Unlimited calls with co-learner and friends',
            style: TextStyle(
              color: Color(0xFFD6BA4C),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Select Co-learner’s gender',
            style: TextStyle(color: Colors.white, fontSize: 19),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onGenderChanged(i),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: selectedIndex == i
                          ? const Color(0xFF303269)
                          : Colors.transparent,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF3F4654)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child:
                        Text(labels[i], style: const TextStyle(fontSize: 18)),
                  ),
                ),
                if (i != labels.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onConnect,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            icon: const Icon(Icons.phone_in_talk_outlined),
            label: const Text(
              'Connect with your Co-learners',
              style: TextStyle(fontSize: 19),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendSubTab extends StatelessWidget {
  const _FriendSubTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF6366F1) : const Color(0xFF8B8B93);
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontSize: 22)),
        ],
      ),
    );
  }
}

class _OnlineFriendTile extends StatelessWidget {
  const _OnlineFriendTile({required this.person, required this.onCall});

  final _SupportPerson person;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SupportAvatar(name: person.name, color: person.color),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            person.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: onCall,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF22C55E),
            side: const BorderSide(color: Color(0xFF166534)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 16),
          ),
          child: const Icon(Icons.call),
        ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onAccept,
    required this.onDelete,
  });

  final _SupportRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SupportAvatar(name: request.name, color: request.color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                request.date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8B8B93),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: onDelete,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF333333),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupportCallDialog extends StatefulWidget {
  const _SupportCallDialog({required this.person, required this.onEnd});

  final _SupportPerson person;
  final VoidCallback onEnd;

  @override
  State<_SupportCallDialog> createState() => _SupportCallDialogState();
}

class _SupportCallDialogState extends State<_SupportCallDialog> {
  int _seconds = 0;
  Timer? _timer;
  bool _muted = false;
  bool _speaker = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _duration {
    final mins = _seconds ~/ 60;
    final secs = _seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF070B18),
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF070B18), Color(0xFF101A33), Color(0xFF06080F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onEnd,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      widget.person.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    ),
                  ),
                  const Icon(Icons.settings, color: Colors.white),
                ],
              ),
              const Spacer(),
              _SupportAvatar(
                name: widget.person.name,
                color: widget.person.color,
                size: 150,
              ),
              const SizedBox(height: 24),
              Text(
                'Connected with ${widget.person.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _duration,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 22),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallControlButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: _muted ? 'Muted' : 'Mute',
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  _CallControlButton(
                    icon: _speaker ? Icons.volume_up : Icons.volume_off,
                    label: 'Speaker',
                    onTap: () => setState(() => _speaker = !_speaker),
                  ),
                  _CallControlButton(
                    icon: Icons.call_end,
                    label: 'End',
                    danger: true,
                    onTap: widget.onEnd,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFEF4444) : const Color(0xFF111827);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: CircleAvatar(
            radius: 34,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.emoji,
    required this.value,
    required this.label,
  });

  final String emoji;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 36)),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB8B8C3),
                fontSize: 17,
                height: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.records});

  final List<_SupportWeekBar> records;

  @override
  Widget build(BuildContext context) {
    const maxMinutes = 220.0;
    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('3hr 44m', style: TextStyle(color: Color(0xFFB8B8C3))),
                Text('2hr 48m', style: TextStyle(color: Color(0xFFB8B8C3))),
                Text('1hr 52m', style: TextStyle(color: Color(0xFFB8B8C3))),
                Text('56m', style: TextStyle(color: Color(0xFFB8B8C3))),
                Text('0m', style: TextStyle(color: Color(0xFFB8B8C3))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final item in records)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Positioned.fill(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: List.generate(
                                    4,
                                    (_) => Container(
                                      height: 1,
                                      color: const Color(0xFF3F4654),
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _SingleBar(
                                    color: const Color(0xFFFACC15),
                                    height: (item.lastWeek / maxMinutes) * 150,
                                  ),
                                  const SizedBox(width: 6),
                                  _SingleBar(
                                    color: const Color(0xFF6366F1),
                                    height: (item.thisWeek / maxMinutes) * 150,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.day,
                          style: TextStyle(
                            color: item.day == 'MON'
                                ? const Color(0xFF6366F1)
                                : const Color(0xFFB8B8C3),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleBar extends StatelessWidget {
  const _SingleBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: height.clamp(2, 150),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 9, backgroundColor: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ],
    );
  }
}

class _SoundTrackCard extends StatelessWidget {
  const _SoundTrackCard({
    required this.service,
    required this.track,
    required this.highlighted,
  });

  final SoundTherapyService service;
  final SoundTherapyTrack track;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isCurrent = service.currentTrackId == track.id;
    final locked = track.premiumOnly && !service.isPremiumUnlocked;
    final playing = isCurrent && service.isPlaying;
    final timerMinutes =
        service.timerTarget?.inMinutes ?? track.defaultTimerMinutes;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: track.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(track.icon, color: track.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        if (locked)
                          _MiniBadge(text: track.lockedBadge, icon: Icons.lock),
                        if (highlighted && !locked) ...[
                          const SizedBox(width: 8),
                          _MiniBadge(
                              text: playing ? 'Playing' : 'Queued',
                              icon: Icons.graphic_eq),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF334155),
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: track.moods
                          .take(3)
                          .map((mood) =>
                              _MiniBadge(text: mood.replaceAll('_', ' ')))
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  if (playing) {
                    await service.pause();
                    return;
                  }
                  await service.setTimerMinutes(timerMinutes);
                  await service.playTrack(track.id);
                },
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                label: Text(playing
                    ? 'Pause'
                    : locked
                        ? 'Preview'
                        : 'Play'),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: () => service.toggleFavorite(track.id),
                icon: Icon(
                  service.isFavorite(track.id)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: service.isFavorite(track.id)
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  locked
                      ? 'Preview available. Unlock premium for full access.'
                      : 'Timer ready: ${timerMinutes} min',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.service, required this.track});

  final SoundTherapyService service;
  final SoundTherapyTrack? track;

  @override
  Widget build(BuildContext context) {
    if (track == null) {
      return const _InfoCard(
        title: 'Nothing playing',
        body: 'Choose a sound category to start the session.',
        icon: Icons.graphic_eq,
      );
    }

    final minutesRemaining =
        service.timerTarget?.inMinutes ?? track!.defaultTimerMinutes;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: track!.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(track!.icon, color: track!.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track!.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      service.isPlaying
                          ? 'Playing with timer'
                          : 'Ready to play',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                    ),
                  ],
                ),
              ),
              _MiniBadge(
                text: '${minutesRemaining} min',
                icon: Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in [5, 10, 15, 20, 30])
                ActionChip(
                  label: Text('${minutes}m'),
                  avatar: const Icon(Icons.timer_outlined, size: 18),
                  onPressed: () => service.setTimerMinutes(minutes),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: service.isPlaying
                    ? service.pause
                    : () => service.playTrack(track!.id),
                icon: Icon(service.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(service.isPlaying ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => service.completeCurrentSession(),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Complete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final SoundTherapyHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final completedLabel = entry.completed ? 'Completed' : 'Stopped';
    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0x0F0F766E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.history, color: Color(0xFF0F766E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.trackTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$completedLabel • ${entry.durationMinutes} min • ${_formatHistoryTime(entry.completedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
              ],
            ),
          ),
          _MiniBadge(
            text: completedLabel,
            icon: entry.completed
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
          ),
        ],
      ),
    );
  }

  String _formatHistoryTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day} $hour:$minute $period';
  }
}

class _CornerNoticeCard extends StatelessWidget {
  const _CornerNoticeCard({required this.notice});

  final SoundTherapyNotice notice;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: notice.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(notice.icon, color: notice.accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notice.message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF334155),
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.isBusy,
    required this.mode,
    required this.onModeChanged,
  });

  final bool isBusy;
  final String mode;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final quickModes = <String, IconData>{
      'support': Icons.favorite_border,
      'grounding': Icons.anchor_outlined,
      'panic': Icons.shield_outlined,
      'sleep': Icons.nights_stay_outlined,
    };
    return _HeroCard(
      title: 'AI companion',
      subtitle:
          'A calm, streaming therapeutic conversation with safe escalation and gentle guidance.',
      trailing: isBusy
          ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.auto_awesome, color: Color(0xFF0F766E)),
      children: [
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickModes.entries
              .map(
                (entry) => ChoiceChip(
                  avatar: Icon(entry.value, size: 18),
                  label:
                      Text(entry.key[0].toUpperCase() + entry.key.substring(1)),
                  selected: mode == entry.key,
                  onSelected: (_) => onModeChanged(entry.key),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ComposerPanel extends StatelessWidget {
  const _ComposerPanel({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onVoicePressed,
    required this.listening,
    required this.voiceReady,
    required this.aiMuted,
    required this.mode,
    required this.voiceError,
    required this.lastAssistantReply,
    required this.onSpeakLastReply,
    required this.onStopSpeaking,
    required this.onAiMutedChanged,
    required this.doctorRecommendationService,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onVoicePressed;
  final bool listening;
  final bool voiceReady;
  final bool aiMuted;
  final String mode;
  final String? voiceError;
  final String? lastAssistantReply;
  final VoidCallback onSpeakLastReply;
  final VoidCallback onStopSpeaking;
  final ValueChanged<bool> onAiMutedChanged;
  final DoctorRecommendationService doctorRecommendationService;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 390;
    final sendWidth = isNarrow ? 48.0 : 96.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x140F766E)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFA),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x1A0F766E)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filledTonal(
                    onPressed: busy ? null : onVoicePressed,
                    tooltip: listening
                        ? 'Stop voice input'
                        : voiceReady
                            ? 'Start voice input'
                            : 'Voice unavailable',
                    icon: Icon(listening ? Icons.mic : Icons.mic_none),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Share what you are feeling...',
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  width: sendWidth,
                  child: FilledButton(
                    onPressed: busy ? null : onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isNarrow
                        ? const Icon(Icons.send)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.send, size: 18),
                              SizedBox(width: 6),
                              Text('Send'),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filledTonal(
                    onPressed: () => _showVoiceSheet(context),
                    tooltip: 'Voice options',
                    icon: const Icon(Icons.expand_less_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVoiceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice controls',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Text stays primary. Voice playback only starts when you tap it.',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                ),
                const SizedBox(height: 12),
                if (lastAssistantReply != null &&
                    lastAssistantReply!.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.play_arrow),
                    title: const Text('Play reply'),
                    subtitle: const Text('Speak the latest AI response'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onSpeakLastReply();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.stop_circle_outlined),
                  title: const Text('Stop speaking'),
                  subtitle: const Text('Immediately stop any playback'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onStopSpeaking();
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(aiMuted
                      ? Icons.volume_off_outlined
                      : Icons.record_voice_over_outlined),
                  title: const Text('AI voice on'),
                  subtitle: const Text(
                      'Manual playback remains available either way'),
                  value: !aiMuted,
                  onChanged: (value) {
                    onAiMutedChanged(!value);
                    Navigator.of(sheetContext).pop();
                  },
                ),
                if (voiceError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    voiceError!,
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFB91C1C),
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.entry});

  final _ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final isUser = entry.role == _ChatRole.user;
    final bg = isUser
        ? const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF155E75)])
        : const LinearGradient(
            colors: [Color(0xCCFFFFFF), Color(0xCCF8FBFA)],
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          gradient: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person : Icons.auto_awesome,
                  size: 14,
                  color: isUser ? Colors.white70 : const Color(0xFF0F766E),
                ),
                const SizedBox(width: 6),
                Text(
                  entry.roleLabel,
                  style: TextStyle(
                    color: isUser ? Colors.white70 : const Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.text,
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF0F172A),
                height: 1.4,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
                children: [
                  _RiskBadge(label: 'Emotion: ${entry.emotion}'),
                  _RiskBadge(label: 'Risk: ${entry.riskLevel}'),
                ],
              ),
            ],
            if (entry.suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
                children: entry.suggestions
                    .map((suggestion) => _SuggestionChip(text: suggestion))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.children,
    this.chips = const [],
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget>? children;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Pill(label: 'MindCare', icon: Icons.favorite),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF475569),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map((chip) => _MiniBadge(text: chip))
                  .toList(growable: false),
            ),
          ],
          if (children != null) ...children!,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.92),
            Colors.white.withValues(alpha: 0.68),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x1A0F766E)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.icon,
    this.accent = const Color(0xFF0F766E),
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF334155),
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _MiniBadge(text: label, icon: icon);
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.text,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String text;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0x0F0F766E);
    final fg = foregroundColor ?? const Color(0xFF0F766E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ).copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x220F766E)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F766E),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1F0F766E)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 12.5,
          height: 1.25,
        ),
      ),
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatEntry {
  const _ChatEntry._({
    required this.role,
    required this.text,
    required this.emotion,
    required this.riskLevel,
    required this.suggestions,
  });

  const _ChatEntry.user(String text)
      : this._(
          role: _ChatRole.user,
          text: text,
          emotion: 'self',
          riskLevel: 'low',
          suggestions: const [],
        );

  const _ChatEntry.assistant({
    required String text,
    required String emotion,
    required String riskLevel,
    required List<String> suggestions,
  }) : this._(
          role: _ChatRole.assistant,
          text: text,
          emotion: emotion,
          riskLevel: riskLevel,
          suggestions: suggestions,
        );

  final _ChatRole role;
  final String text;
  final String emotion;
  final String riskLevel;
  final List<String> suggestions;

  String get roleLabel {
    switch (role) {
      case _ChatRole.user:
        return 'You';
      case _ChatRole.assistant:
        return 'MindCare';
    }
  }
}

class _MeditationVideoCard extends StatefulWidget {
  const _MeditationVideoCard();

  @override
  State<_MeditationVideoCard> createState() => _MeditationVideoCardState();
}

class _MeditationVideoCardState extends State<_MeditationVideoCard> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.asset('assets/videos/meditation_video.mp4')
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() => _ready = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Guided Meditation Video',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (!_ready)
            const Center(child: CircularProgressIndicator())
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !_ready
                ? null
                : () {
                    setState(() {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    });
                  },
            icon: Icon(
              _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            label: Text(_controller.value.isPlaying ? 'Pause' : 'Play'),
          ),
        ],
      ),
    );
  }
}
