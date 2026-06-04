import 'agora_voice_call_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'mindcare_ongoing_call_screen.dart';

class MindcareConnectScreen extends StatefulWidget {
  const MindcareConnectScreen({
    super.key,
    required this.apiService,
    this.peerAlias = "co_learner",
    this.targetUserId,
    this.gender = "any",
  });

  final ApiService apiService;
  final String peerAlias;
  final String? targetUserId;
  final String gender;

  @override
  State<MindcareConnectScreen> createState() => _MindcareConnectScreenState();
}

class _MindcareConnectScreenState extends State<MindcareConnectScreen> {
  int _seconds = 0;
  bool _engineInitialized = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startFlow();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startFlow() async {
    final targetUserId = widget.targetUserId;

    if (targetUserId != null && targetUserId.trim().isNotEmpty) {
      try {
        setState(() {
          _engineInitialized = true;
          _error = null;
        });

        final callResponse = await widget.apiService.startCall(
          peerAlias: widget.peerAlias,
          callType: "audio",
          targetUserId: targetUserId,
        );

        final callId = callResponse["call"]?["id"]?.toString();
        final channelName = callResponse["call"]?["channelName"]?.toString();
        final agoraToken =
            callResponse["call"]?["agoraToken"]?.toString() ?? "";
        final agoraUid = int.tryParse(
              callResponse["call"]?["agoraUid"]?.toString() ?? "",
            ) ??
            0;

        if (callId == null || callId.isEmpty) {
          throw Exception("Call ID missing");
        }

        if (channelName == null || channelName.isEmpty) {
          throw Exception("Missing channel");
        }

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AgoraVoiceCallScreen(
              apiService: widget.apiService,
              callId: callId,
              channelName: channelName,
              token: agoraToken,
              uid: agoraUid,
              peerName: widget.peerAlias,
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _error = error.toString();
          _engineInitialized = false;
        });
      }

      return;
    }

    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        if (!mounted) return;

        setState(() => _seconds += 3);

        if (_seconds >= 120) {
          timer.cancel();

          setState(() {
            _error = "Sorry, co-learner is not available right now";
          });

          return;
        }

        try {
          final response =
              await widget.apiService.randomMatch(gender: widget.gender);

          final peer = response["peer"];

          if (peer == null || peer["id"] == null) {
            return;
          }

          timer.cancel();

          final callResponse = await widget.apiService.startCall(
            peerAlias: peer["name"]?.toString() ?? "Co-learner",
            callType: "audio",
            targetUserId: peer["id"].toString(),
          );

          final callId = callResponse["call"]?["id"]?.toString();
          final channelName = callResponse["call"]?["channelName"]?.toString();
          final agoraToken =
              callResponse["call"]?["agoraToken"]?.toString() ?? "";
          final agoraUid = int.tryParse(
                callResponse["call"]?["agoraUid"]?.toString() ?? "",
              ) ??
              0;

          if (callId == null || callId.isEmpty) {
            throw Exception("Call ID missing");
          }

          if (channelName == null || channelName.isEmpty) {
            throw Exception("Missing channel");
          }

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AgoraVoiceCallScreen(
                apiService: widget.apiService,
                callId: callId,
                channelName: channelName,
                token: agoraToken,
                uid: agoraUid,
                peerName: peer["name"]?.toString() ?? "Co-learner",
              ),
            ),
          );
        } catch (error) {
          final message = error.toString();

          if (message.contains('404') ||
              message.toLowerCase().contains('no online')) {
            return;
          }

          timer.cancel();

          if (!mounted) return;

          setState(() {
            _error = message;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const CircularProgressIndicator(
                  color: Color(0xFF22C55E),
                  strokeWidth: 5,
                ),
                const SizedBox(height: 40),
                Text(
                  _engineInitialized
                      ? "Initializing Engine..."
                      : "Finding your co-learner...",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text(
                  _engineInitialized
                      ? "Starting backend call session"
                      : "Please wait while we connect you",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.redAccent, fontSize: 18),
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
