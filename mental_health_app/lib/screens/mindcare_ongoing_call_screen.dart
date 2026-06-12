import 'dart:async';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'mindcare_review_screen.dart';

class MindcareOngoingCallScreen extends StatefulWidget {
  const MindcareOngoingCallScreen({
    super.key,
    required this.apiService,
    required this.callId,
    required this.peerAlias,
  });

  final ApiService apiService;
  final String callId;
  final String peerAlias;

  @override
  State<MindcareOngoingCallScreen> createState() =>
      _MindcareOngoingCallScreenState();
}

class _MindcareOngoingCallScreenState extends State<MindcareOngoingCallScreen> {
  int _seconds = 0;
  Timer? _timer;

  bool muted = false;
  bool speaker = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get formattedTime {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _endCall() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "End MindCare Call?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "Leaving early may interrupt your co-learning session.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("End Call", style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Continue Call",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == true && mounted) {
      _timer?.cancel();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MindcareReviewScreen(
            apiService: widget.apiService,
            callId: widget.callId,
            callDurationSeconds: _seconds,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Center(
                child: Text(
                  "Ongoing MindCare Call",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 70),
            ),
            const SizedBox(height: 30),
            Text(
              widget.peerAlias,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              formattedTime,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 18,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _circleButton(
                    icon: muted ? Icons.mic_off : Icons.mic,
                    label: "Mute",
                    onTap: () => setState(() => muted = !muted),
                  ),
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  _circleButton(
                    icon: speaker ? Icons.volume_up : Icons.hearing,
                    label: "Speaker",
                    onTap: () => setState(() => speaker = !speaker),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 10),
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
      ],
    );
  }
}
