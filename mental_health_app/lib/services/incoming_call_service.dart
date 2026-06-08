import 'package:flutter/material.dart';

import '../screens/agora_voice_call_screen.dart';

import 'api_service.dart';

class IncomingCallService {
  static void showIncomingCall({
    required BuildContext context,
    required String callerName,
    required String channelName,
    required String token,
    required int uid,
    ApiService? apiService,
    String? callId,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Incoming call'),
          content: Text('$callerName is calling you'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AgoraVoiceCallScreen(
                      apiService: apiService,
                      callId: callId,
                      channelName: channelName,
                      token: token,
                      uid: uid,
                      peerName: callerName,
                    ),
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }
}
