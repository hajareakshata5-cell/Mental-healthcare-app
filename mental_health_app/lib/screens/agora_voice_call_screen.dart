// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'mindcare_review_screen.dart';

import '../services/agora_voice_service.dart';

class AgoraVoiceCallScreen extends StatefulWidget {
  const AgoraVoiceCallScreen({
    super.key,
    required this.channelName,
    required this.token,
    required this.uid,
    this.apiService,
    this.callId,
    this.peerName = 'Co-learner',
    this.maxCallSeconds,
    this.showPremiumPromptOnLimit = false,
  });

  final ApiService? apiService;
  final String? callId;
  final String channelName;
  final String token;
  final int uid;
  final String peerName;
  final int? maxCallSeconds;
  final bool showPremiumPromptOnLimit;
  @override
  State<AgoraVoiceCallScreen> createState() => _AgoraVoiceCallScreenState();
}

class _AgoraVoiceCallScreenState extends State<AgoraVoiceCallScreen> {
  static const MethodChannel _callServiceChannel =
      MethodChannel('mindcare/call_service');

  Future<void> _startAndroidCallService() async {
    try {
      await _callServiceChannel.invokeMethod('startCallService');
    } catch (_) {}
  }

  Future<void> _stopAndroidCallService() async {
    try {
      await _callServiceChannel.invokeMethod('stopCallService');
    } catch (_) {}
  }

  final AgoraVoiceService _voiceService = AgoraVoiceService();

  bool _loading = true;
  bool _ending = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _remoteJoined = false;
  String? _error;
  int _seconds = 0;
  Timer? _timer;
  int? _effectiveMaxCallSeconds;
  bool _showPremiumPromptOnLimit = false;
  bool _autoEndingByLimit = false;
  String? _limitMessage;

  @override
  void initState() {
    super.initState();
    _effectiveMaxCallSeconds = widget.maxCallSeconds;
    _showPremiumPromptOnLimit = widget.showPremiumPromptOnLimit;
    _startAndroidCallService();
    _startCall();
  }

  Future<void> _loadCallDurationPolicy() async {
    final apiService = widget.apiService;
    if (apiService == null) return;

    try {
      final response = await apiService.getSubscription();
      final policy = response['callDurationPolicy'];

      if (policy is! Map) return;

      final maxSeconds =
          int.tryParse(policy['maxCallSeconds']?.toString() ?? '');
      final requiresPremium = policy['requiresPremiumForMoreCalls'] == true;
      final isPremium = policy['isPremium'] == true;
      final message = policy['message']?.toString();

      if (!mounted) return;

      setState(() {
        _effectiveMaxCallSeconds =
            maxSeconds != null && maxSeconds > 0 ? maxSeconds : 1;
        _showPremiumPromptOnLimit = requiresPremium || !isPremium;
        _limitMessage = message;
      });
    } catch (error) {
      debugPrint('CALL_DURATION_POLICY_LOAD_FAILED: $error');
    }
  }

  Future<void> _startCall() async {
    try {
      await _loadCallDurationPolicy();
      await _voiceService.initialize();

      _voiceService.registerHandlers(
        onUserJoined: (_) {
          if (!mounted) return;
          unawaited(_voiceService.restoreAudioPath(
            localMuted: _muted,
            speakerEnabled: _speakerOn,
          ));
          setState(() => _remoteJoined = true);
        },
        onUserLeft: (_) {
          if (!mounted || _ending) return;

          setState(() {
            _remoteJoined = false;
            _error = 'Other user ended the call.';
          });

          unawaited(_endCall());
        },
        onError: (message) {
          if (!mounted) return;
          setState(() => _error = message);
        },
      );

      debugPrint(
        'AGORA_SCREEN_JOIN '
        'channel=${widget.channelName} '
        'tokenEmpty=${widget.token.isEmpty} '
        'tokenLength=${widget.token.length} '
        'uid=${widget.uid}',
      );

      if (widget.channelName.trim().isEmpty) {
        throw Exception('Agora channel missing');
      }

      if (widget.token.trim().isEmpty) {
        throw Exception(
          'Agora token missing. Render backend is not sending token.',
        );
      }

      if (widget.token.trim().length < 50) {
        throw Exception(
          'Agora token invalid length: ${widget.token.length}',
        );
      }

      if (widget.uid <= 0) {
        throw Exception(
          'Agora uid invalid: ${widget.uid}',
        );
      }

      await _voiceService.joinChannel(
        channelName: widget.channelName,
        token: widget.token,
        uid: widget.uid,
      );
      await _voiceService.restoreAudioPath(
        localMuted: _muted,
        speakerEnabled: _speakerOn,
      );
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _ending) return;
        setState(() => _seconds++);

        final maxSeconds = _effectiveMaxCallSeconds;
        if (maxSeconds != null && maxSeconds > 0 && _seconds >= maxSeconds) {
          unawaited(_handleCallDurationLimitReached());
          return;
        }

        if (_seconds > 0 && _seconds % 8 == 0) {
          unawaited(_voiceService.restoreAudioPath(
            localMuted: _muted,
            speakerEnabled: _speakerOn,
          ));
        }
      });

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      unawaited(_markCallFailedToConnect(e));
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _handleCallDurationLimitReached() async {
    if (_ending || _autoEndingByLimit) return;

    _autoEndingByLimit = true;

    final premiumPrompt = _showPremiumPromptOnLimit;
    final message = premiumPrompt
        ? (_limitMessage ??
            'Your daily 30 minutes trial call limit is completed. Take Premium for more calls.')
        : 'This call reached the 1 hour maximum limit. You can start another call anytime.';

    if (mounted) {
      setState(() => _error = message);
    }

    await _endCall(
      feedback: message,
      showLimitDialog: true,
      showPremiumPrompt: premiumPrompt,
    );
  }

  Future<void> _toggleMute() async {
    if (_ending) return;

    final next = !_muted;

    try {
      await _voiceService.mute(next);
      if (!mounted) return;
      setState(() => _muted = next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Mute failed: $e');
    }
  }

  Future<void> _markCallFailedToConnect(Object error) async {
    final apiService = widget.apiService;
    final callId = widget.callId;

    if (apiService == null || callId == null || callId.isEmpty) return;

    try {
      await apiService.endCall(
        callId: callId,
        durationSeconds: _seconds,
        rating: 0,
        feedback: 'Call failed to connect: $error',
      );
    } catch (cleanupError) {
      debugPrint('Failed call cleanup error: $cleanupError');
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_ending) return;

    final next = !_speakerOn;

    try {
      await _voiceService.speaker(next);
      if (!mounted) return;
      setState(() => _speakerOn = next);
    } catch (e) {
      if (!mounted) return;
      debugPrint('Speaker toggle failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Speaker could not be changed on this device.')),
      );
    }
  }

  Future<void> _endCall({
    String feedback = 'Call ended by user',
    bool showLimitDialog = false,
    bool showPremiumPrompt = false,
  }) async {
    if (_ending) return;

    setState(() {
      _ending = true;
      _loading = true;
      _error = null;
    });

    _timer?.cancel();

    try {
      await _voiceService.leave();
      await _voiceService.dispose();
    } catch (e) {
      debugPrint('End call cleanup error: $e');
    }

    if (!mounted) return;

    final apiService = widget.apiService;
    final callId = widget.callId;

    if (apiService != null && callId != null && callId.isNotEmpty) {
      try {
        await apiService.endCall(
          callId: callId,
          durationSeconds: _seconds,
          rating: 0,
          feedback: feedback,
        );
        debugPrint('VOICE_CALL_END_POSTED callId=$callId duration=$_seconds');
      } catch (endApiError) {
        debugPrint('VOICE_CALL_END_POST_FAILED: $endApiError');
      }

      if (showLimitDialog) {
        await _showCallLimitDialog(
          showPremiumPrompt: showPremiumPrompt,
          message: feedback,
        );

        if (!mounted) return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MindcareReviewScreen(
            apiService: apiService,
            callId: callId,
            callDurationSeconds: _seconds,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop(_seconds);
    }
  }

  Future<void> _showCallLimitDialog({
    required bool showPremiumPrompt,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            showPremiumPrompt
                ? 'Premium needed for more calls'
                : 'Call limit reached',
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(showPremiumPrompt ? 'View Premium in app' : 'OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _stopAndroidCallService();
    _timer?.cancel();
    unawaited(_voiceService.dispose());
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;

    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _ending
        ? 'Ending call...'
        : _loading
            ? 'Connecting voice call...'
            : _remoteJoined
                ? 'Connected'
                : 'Waiting for other user...';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFEFFCF9),
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFEFFCF9),
                    Color(0xFFF8FFFD),
                    Color(0xFFE7F7F5),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -70,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFBFEFE7).withOpacity(0.22),
                ),
              ),
            ),
            Positioned(
              bottom: -95,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB7E6DD).withOpacity(0.26),
                ),
              ),
            ),
            Positioned(
              top: 96,
              left: 28,
              child: Icon(
                Icons.eco_rounded,
                color: const Color(0xFF6BC7BA).withOpacity(0.28),
                size: 44,
              ),
            ),
            Positioned(
              top: 150,
              right: 42,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: const Color(0xFF38B2AC).withOpacity(0.35),
                size: 22,
              ),
            ),
            Positioned(
              top: 370,
              right: 24,
              child: Icon(
                Icons.favorite_border_rounded,
                color: const Color(0xFF58C7BE).withOpacity(0.42),
                size: 30,
              ),
            ),
            Positioned(
              bottom: 190,
              left: 30,
              child: Icon(
                Icons.self_improvement_rounded,
                color: const Color(0xFF4DB6AC).withOpacity(0.30),
                size: 44,
              ),
            ),
            Positioned(
              bottom: 120,
              right: 24,
              child: Icon(
                Icons.local_florist_rounded,
                color: const Color(0xFF7CCDBF).withOpacity(0.32),
                size: 48,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.70),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F766E).withOpacity(0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.spa_rounded,
                        color: Color(0xFF0F766E),
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _remoteJoined
                          ? widget.peerName
                          : 'Waiting for other user',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF063F3B),
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _remoteJoined
                            ? const Color(0xFF4B918B)
                            : const Color(0xFF64748B),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Container(
                      width: 178,
                      height: 178,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.72),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F766E).withOpacity(0.16),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _remoteJoined
                                ? const [
                                    Color(0xFFB8F2D8),
                                    Color(0xFF38BDB6),
                                  ]
                                : const [
                                    Color(0xFFE2E8F0),
                                    Color(0xFF94A3B8),
                                  ],
                          ),
                        ),
                        child: Icon(
                          _ending
                              ? Icons.call_end_rounded
                              : Icons.person_rounded,
                          color: Colors.white,
                          size: 86,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _formatDuration(_seconds),
                      style: const TextStyle(
                        color: Color(0xFF073F3A),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Breathe easy â€¢ You are connected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF0F766E).withOpacity(0.58),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFFCA5A5).withOpacity(0.55),
                          ),
                        ),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CallCircleButton(
                          icon: _muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: _muted ? 'Unmute' : 'Mute',
                          onTap: (_loading || _ending) ? null : _toggleMute,
                          color: const Color(0xFF4DB6AC),
                        ),
                        const SizedBox(width: 20),
                        _CallCircleButton(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.volume_down_rounded,
                          label: _speakerOn ? 'Speaker On' : 'Speaker',
                          onTap: (_loading || _ending) ? null : _toggleSpeaker,
                          color: const Color(0xFF7C83FF),
                        ),
                        const SizedBox(width: 20),
                        _CallCircleButton(
                          icon: Icons.call_end_rounded,
                          label: _ending ? 'Ending' : 'End',
                          onTap: _ending ? null : _endCall,
                          color: const Color(0xFFFF5A52),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallCircleButton extends StatelessWidget {
  const _CallCircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : () => unawaited(onTap!()),
            borderRadius: BorderRadius.circular(44),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: disabled ? const Color(0xFFCBD5E1) : color,
                border: Border.all(
                  color: Colors.white.withOpacity(0.80),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (disabled ? Colors.black : color).withOpacity(0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: disabled ? const Color(0xFF94A3B8) : const Color(0xFF073F3A),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
