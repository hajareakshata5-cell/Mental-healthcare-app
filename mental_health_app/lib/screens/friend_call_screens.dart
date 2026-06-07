import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'agora_voice_call_screen.dart';

class FriendRingingScreen extends StatefulWidget {
  const FriendRingingScreen({
    super.key,
    required this.apiService,
    required this.targetUserId,
    required this.peerName,
  });

  final ApiService apiService;
  final String targetUserId;
  final String peerName;

  @override
  State<FriendRingingScreen> createState() => _FriendRingingScreenState();
}

class _FriendRingingScreenState extends State<FriendRingingScreen> {
  Timer? _timer;
  String? _callId;
  bool _loading = true;
  bool _unavailable = false;
  bool _busy = false;
  bool _ending = false;
  String? _error;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _startFriendCall();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startFriendCall() async {
    try {
      final response = await widget.apiService.requestFriendCall(
        targetUserId: widget.targetUserId,
        peerAlias: widget.peerName,
      );

      final status = response['status']?.toString() ??
          response['call']?['status']?.toString() ??
          '';

      if (status == 'busy') {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _unavailable = true;
          _busy = true;
          _error = null;
        });
        return;
      }

      final call = response['call'] as Map<String, dynamic>?;
      final callId = call?['id']?.toString();

      if (callId == null || callId.isEmpty) {
        throw Exception('Call id missing');
      }

      if (!mounted) return;

      setState(() {
        _callId = callId;
        _loading = false;
        _error = null;
      });

      _timer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pollStatus();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unavailable = true;
        _error = error.toString();
      });
    }
  }

  Future<void> _pollStatus() async {
    if (_ending || _callId == null) return;

    _elapsed += 2;

    if (_elapsed >= 45) {
      await _cancelCall(showUnavailable: true);
      return;
    }

    try {
      final response = await widget.apiService.getFriendCallStatus(
        callId: _callId!,
      );

      final status = response['status']?.toString() ??
          response['call']?['status']?.toString() ??
          '';

      final call = response['call'] as Map<String, dynamic>?;

      if (status == 'accepted' || status == 'connected') {
        _timer?.cancel();

        final callId = call?['id']?.toString() ?? _callId;
        final channelName = call?['channelName']?.toString() ?? '';
        final token = call?['agoraToken']?.toString() ?? '';
        final uid = int.tryParse(call?['agoraUid']?.toString() ?? '') ?? 0;
        final peerName = call?['peerName']?.toString() ?? widget.peerName;

        if (callId == null || callId.isEmpty || channelName.isEmpty) {
          throw Exception('Accepted call details missing');
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AgoraVoiceCallScreen(
              apiService: widget.apiService,
              callId: callId,
              channelName: channelName,
              token: token,
              uid: uid,
              peerName: peerName,
            ),
          ),
        );
        return;
      }

      if (status == 'rejected' ||
          status == 'missed' ||
          status == 'cancelled' ||
          status == 'blocked') {
        _timer?.cancel();
        if (!mounted) return;
        setState(() => _unavailable = true);
      }
    } catch (error) {
      debugPrint('FRIEND_CALL_STATUS_ERROR: $error');
    }
  }

  Future<void> _cancelCall({bool showUnavailable = false}) async {
    if (_ending) return;

    _ending = true;
    _timer?.cancel();

    final callId = _callId;
    if (callId != null && callId.isNotEmpty) {
      try {
        await widget.apiService.cancelFriendCall(callId: callId);
      } catch (_) {}
    }

    if (!mounted) return;

    if (showUnavailable) {
      setState(() {
        _unavailable = true;
        _ending = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _callAgain() {
    setState(() {
      _callId = null;
      _loading = true;
      _unavailable = false;
      _busy = false;
      _ending = false;
      _error = null;
      _elapsed = 0;
    });
    _startFriendCall();
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) {
      return _FriendUnavailableView(
        peerName: widget.peerName,
        title:
            _busy ? 'Your friend is busy currently' : 'Currently Unavailable',
        onCallAgain: _callAgain,
        onCancel: () => Navigator.pop(context),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 72,
                backgroundColor: const Color(0xFFFDE68A),
                child: Text(
                  widget.peerName.isNotEmpty
                      ? widget.peerName.characters.first.toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFACC15)),
                ),
                child: Text(
                  widget.peerName,
                  style: const TextStyle(
                    color: Color(0xFFE5E7EB),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your MindCare friend',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 42),
              Text(
                _loading ? 'Starting call...' : 'Ringing...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => _cancelCall(),
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'End',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IncomingFriendCallScreen extends StatefulWidget {
  const IncomingFriendCallScreen({
    super.key,
    required this.apiService,
    required this.call,
  });

  final ApiService apiService;
  final Map<String, dynamic> call;

  @override
  State<IncomingFriendCallScreen> createState() =>
      _IncomingFriendCallScreenState();
}

class _IncomingFriendCallScreenState extends State<IncomingFriendCallScreen> {
  bool _loading = false;

  String get _callId => widget.call['id']?.toString() ?? '';
  String get _callerName =>
      widget.call['callerName']?.toString() ?? 'MindCare friend';

  Future<void> _accept() async {
    if (_loading || _callId.isEmpty) return;

    setState(() => _loading = true);

    try {
      final response =
          await widget.apiService.acceptFriendCall(callId: _callId);
      final call = response['call'] as Map<String, dynamic>?;

      final callId = call?['id']?.toString() ?? _callId;
      final channelName = call?['channelName']?.toString() ?? '';
      final token = call?['agoraToken']?.toString() ?? '';
      final uid = int.tryParse(call?['agoraUid']?.toString() ?? '') ?? 0;
      final peerName = call?['peerName']?.toString() ?? _callerName;

      if (channelName.isEmpty) {
        throw Exception('Missing channel');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AgoraVoiceCallScreen(
            apiService: widget.apiService,
            callId: callId,
            channelName: channelName,
            token: token,
            uid: uid,
            peerName: peerName,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $error')),
      );
    }
  }

  Future<void> _reject() async {
    if (_callId.isNotEmpty) {
      try {
        await widget.apiService.rejectFriendCall(callId: _callId);
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 72,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  _callerName.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _callerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Incoming MindCare friend call',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              if (_loading)
                const CircularProgressIndicator(color: Color(0xFF22C55E))
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallCircleButton(
                      label: 'Reject',
                      icon: Icons.close,
                      color: const Color(0xFFEF4444),
                      onTap: _reject,
                    ),
                    _CallCircleButton(
                      label: 'Accept',
                      icon: Icons.call,
                      color: const Color(0xFF22C55E),
                      onTap: _accept,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendUnavailableView extends StatelessWidget {
  const _FriendUnavailableView({
    required this.peerName,
    required this.title,
    required this.onCallAgain,
    required this.onCancel,
  });

  final String peerName;
  final String title;
  final VoidCallback onCallAgain;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 72,
                backgroundColor: const Color(0xFFFDE68A),
                child: Text(
                  peerName.isNotEmpty
                      ? peerName.characters.first.toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Your MindCare Friend',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallCircleButton(
                    label: 'Call again',
                    icon: Icons.call,
                    color: const Color(0xFF333333),
                    onTap: onCallAgain,
                  ),
                  _CallCircleButton(
                    label: 'Cancel',
                    icon: Icons.close,
                    color: const Color(0xFF333333),
                    onTap: onCancel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallCircleButton extends StatelessWidget {
  const _CallCircleButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 42),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}
