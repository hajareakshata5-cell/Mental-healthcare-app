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
        var loading = false;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> rejectCall() async {
              if (loading) return;

              Navigator.of(dialogContext).pop();

              final safeCallId = callId?.trim() ?? '';
              if (apiService != null && safeCallId.isNotEmpty) {
                try {
                  await apiService.rejectFriendCall(callId: safeCallId);
                } catch (error) {
                  debugPrint('Incoming call reject failed: $error');
                }
              }
            }

            Future<void> acceptCall() async {
              if (loading) return;

              final safeCallId = callId?.trim() ?? '';

              if (apiService == null || safeCallId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cannot accept call. Call details missing.'),
                  ),
                );
                return;
              }

              setDialogState(() => loading = true);

              try {
                final response =
                    await apiService.acceptFriendCall(callId: safeCallId);

                final call = response['call'] as Map<String, dynamic>?;

                final freshCallId = call?['id']?.toString() ?? safeCallId;
                final freshChannelName =
                    call?['channelName']?.toString() ?? channelName;
                final freshToken = call?['agoraToken']?.toString() ?? token;
                final freshUid = int.tryParse(
                      call?['agoraUid']?.toString() ?? uid.toString(),
                    ) ??
                    uid;
                final peerName = call?['peerName']?.toString() ?? callerName;

                if (freshChannelName.trim().isEmpty) {
                  throw Exception('Missing channel');
                }

                if (freshToken.trim().isEmpty) {
                  throw Exception('Missing Agora token');
                }

                if (freshUid <= 0) {
                  throw Exception('Invalid Agora uid');
                }

                if (!dialogContext.mounted || !context.mounted) return;

                Navigator.of(dialogContext).pop();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AgoraVoiceCallScreen(
                      apiService: apiService,
                      callId: freshCallId,
                      channelName: freshChannelName,
                      token: freshToken,
                      uid: freshUid,
                      peerName: peerName,
                    ),
                  ),
                );
              } catch (error) {
                debugPrint('Incoming call accept failed: $error');

                if (!dialogContext.mounted || !context.mounted) return;

                setDialogState(() => loading = false);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Accept failed: $error')),
                );
              }
            }

            return AlertDialog(
              title: const Text('Incoming call'),
              content: Text('$callerName is calling you'),
              actions: [
                TextButton(
                  onPressed: loading ? null : rejectCall,
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: loading ? null : acceptCall,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
