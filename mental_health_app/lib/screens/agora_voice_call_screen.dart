import 'dart:async';
import 'package:flutter/material.dart';
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
  });

  final ApiService? apiService;
  final String? callId;
  final String channelName;
  final String token;
  final int uid;
  final String peerName;
  @override
  State<AgoraVoiceCallScreen> createState() => _AgoraVoiceCallScreenState();
}

class _AgoraVoiceCallScreenState extends State<AgoraVoiceCallScreen> {
  final AgoraVoiceService _voiceService = AgoraVoiceService();

  bool _loading = true;
  bool _ending = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _remoteJoined = false;
  String? _error;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      await _voiceService.initialize();

      _voiceService.registerHandlers(
        onUserJoined: (_) {
          if (!mounted) return;
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

      await _voiceService.joinChannel(
        channelName: widget.channelName,
        token: widget.token,
        uid: widget.uid,
      );
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _ending) return;
        setState(() => _seconds++);
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

  Future<void> _endCall() async {
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

  @override
  void dispose() {
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
        backgroundColor: const Color(0xFF020617),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text(
                  _remoteJoined ? widget.peerName : 'Waiting for other user',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _remoteJoined
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF334155),
                  ),
                  child: Icon(
                    _ending ? Icons.call_end : Icons.person,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _formatDuration(_seconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallCircleButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Unmute' : 'Mute',
                      onTap: (_loading || _ending) ? null : _toggleMute,
                      color: const Color(0xFF334155),
                    ),
                    const SizedBox(width: 18),
                    _CallCircleButton(
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      label: _speakerOn ? 'Speaker On' : 'Speaker',
                      onTap: (_loading || _ending) ? null : _toggleSpeaker,
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 18),
                    _CallCircleButton(
                      icon: Icons.call_end,
                      label: _ending ? 'Ending' : 'End',
                      onTap: _ending ? null : _endCall,
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
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
      children: [
        InkWell(
          onTap: disabled ? null : () => unawaited(onTap!()),
          borderRadius: BorderRadius.circular(40),
          child: CircleAvatar(
            radius: 34,
            backgroundColor: disabled ? Colors.grey : color,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
