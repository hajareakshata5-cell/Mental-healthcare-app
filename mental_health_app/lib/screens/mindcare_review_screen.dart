// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class MindcareReviewScreen extends StatefulWidget {
  final ApiService apiService;
  final String callId;
  final int callDurationSeconds;

  const MindcareReviewScreen({
    super.key,
    required this.apiService,
    required this.callId,
    required this.callDurationSeconds,
  });

  @override
  State<MindcareReviewScreen> createState() => _MindcareReviewScreenState();
}

class _MindcareReviewScreenState extends State<MindcareReviewScreen> {
  int selectedStars = 0;
  bool _submitting = false;
  String? _error;

  final TextEditingController feedbackController = TextEditingController();

  @override
  void dispose() {
    feedbackController.dispose();
    super.dispose();
  }

  String get durationText {
    final minutes = widget.callDurationSeconds ~/ 60;
    final seconds = widget.callDurationSeconds % 60;
    return "$minutes min $seconds sec";
  }

  String get reviewQuestion {
    switch (selectedStars) {
      case 1:
        return "What went wrong?";
      case 2:
        return "What could be improved?";
      case 3:
        return "How can we improve your experience?";
      case 4:
        return "What did you enjoy most?";
      case 5:
        return "Amazing! What made this session great?";
      default:
        return "How was your MindCare session?";
    }
  }

  void _openRewardScreen() {
    final completedMinutes = widget.callDurationSeconds ~/ 60;
    final earnedStars = completedMinutes * 2;
    final earnedCoins = completedMinutes ~/ 2;

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StarsEarnedScreen(
          apiService: widget.apiService,
          earnedStars: earnedStars,
          earnedCoins: earnedCoins,
          durationSeconds: widget.callDurationSeconds,
        ),
      ),
    );
  }

  Future<void> _submitReview({bool skipped = false}) async {
    if (skipped) {
      if (!mounted) return;
      setState(() {
        _submitting = true;
        _error = null;
      });

      _openRewardScreen();
      return;
    }

    if (selectedStars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a rating before submitting."),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.apiService.endCall(
        callId: widget.callId,
        durationSeconds: widget.callDurationSeconds,
        rating: selectedStars,
        feedback: feedbackController.text.trim(),
      );

      _openRewardScreen();
      return;
    } catch (e) {
      debugPrint('REVIEW_SUBMIT_FAILED: $e');

      if (!mounted) return;

      final message = e.toString().toLowerCase();
      final isRateLimit = message.contains('429') ||
          message.contains('rate limit') ||
          message.contains('too many') ||
          message.contains('call service is busy');

      if (isRateLimit) {
        _openRewardScreen();
        return;
      }

      setState(() {
        _error = 'Could not submit feedback right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSkip = widget.callDurationSeconds < 180;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                "Call Ended",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Duration: $durationText",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                "Rate Your Experience",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return IconButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() => selectedStars = star),
                    icon: Icon(
                      Icons.star,
                      color:
                          selectedStars >= star ? Colors.amber : Colors.white24,
                      size: 40,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  reviewQuestion,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: feedbackController,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Write your feedback here...",
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (canSkip)
                TextButton(
                  onPressed:
                      _submitting ? null : () => _submitReview(skipped: true),
                  child: const Text("Skip",
                      style: TextStyle(color: Colors.white70)),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submitReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _submitting ? "Submitting..." : "Submit Feedback",
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class StarsEarnedScreen extends StatelessWidget {
  final int earnedStars;
  final int earnedCoins;
  final int durationSeconds;
  final ApiService apiService;

  const StarsEarnedScreen({
    super.key,
    required this.earnedStars,
    required this.earnedCoins,
    required this.durationSeconds,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return _RewardStageScaffold(
      title: "✨ Congratulations! ✨",
      icon: Icons.star,
      iconColor: const Color(0xFFFACC15),
      value: "$earnedStars",
      label: "Stars earned",
      buttonText: "Continue",
      onPressed: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ClaimRewardScreen(
              apiService: apiService,
              earnedCoins: earnedCoins,
              durationSeconds: durationSeconds,
            ),
          ),
        );
      },
    );
  }
}

class ClaimRewardScreen extends StatelessWidget {
  final int earnedCoins;
  final int durationSeconds;
  final ApiService apiService;

  const ClaimRewardScreen({
    super.key,
    required this.earnedCoins,
    required this.durationSeconds,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return _RewardStageScaffold(
      title: "",
      icon: Icons.card_giftcard,
      iconColor: const Color(0xFFFF2D6F),
      value: "",
      label: "Claim your reward",
      buttonText: "Claim Reward",
      onPressed: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CoinsEarnedScreen(
              apiService: apiService,
              earnedCoins: earnedCoins,
              durationSeconds: durationSeconds,
            ),
          ),
        );
      },
    );
  }
}

class CoinsEarnedScreen extends StatelessWidget {
  final int earnedCoins;
  final int durationSeconds;
  final ApiService apiService;

  const CoinsEarnedScreen({
    super.key,
    required this.earnedCoins,
    required this.durationSeconds,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return _RewardStageScaffold(
      title: "✨ Congratulations! ✨",
      icon: Icons.monetization_on,
      iconColor: const Color(0xFFFACC15),
      value: "$earnedCoins",
      label: "Coins earned",
      buttonText: "Continue",
      onPressed: () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LeagueRankScreen(
              apiService: apiService,
              earnedCoins: earnedCoins,
              durationSeconds: durationSeconds,
            ),
          ),
        );
      },
    );
  }
}

class LeagueRankScreen extends StatefulWidget {
  final ApiService apiService;
  final int earnedCoins;
  final int durationSeconds;

  const LeagueRankScreen({
    super.key,
    required this.apiService,
    required this.earnedCoins,
    required this.durationSeconds,
  });

  @override
  State<LeagueRankScreen> createState() => _LeagueRankScreenState();
}

class _LeagueRankScreenState extends State<LeagueRankScreen> {
  bool _loading = true;
  int _todayMinutes = 0;
  int _todayCoins = 0;
  int _rank = 7;
  String _currentUserName = 'You';
  List<_LeagueUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _loadLeague();
  }

  Future<void> _loadLeague() async {
    final fallbackMinutes = widget.durationSeconds ~/ 60;

    var todayMinutes = fallbackMinutes;
    var currentUserName = 'You';

    try {
      final me = await widget.apiService.getMe();
      final displayName = (me.displayName ?? '').trim();
      final username = me.username.trim();
      final alias = me.alias.trim();

      if (displayName.isNotEmpty) {
        currentUserName = displayName;
      } else if (username.isNotEmpty) {
        currentUserName = username;
      } else if (alias.isNotEmpty) {
        currentUserName = alias;
      }
    } catch (_) {
      currentUserName = 'You';
    }

    try {
      final historyResponse = await widget.apiService.getCallHistory();
      final rawCalls = historyResponse['calls'];
      final calls = rawCalls is List ? rawCalls : const [];

      final now = DateTime.now();
      var todaySeconds = 0;

      for (final raw in calls) {
        if (raw is! Map) continue;

        final createdAt =
            DateTime.tryParse((raw['createdAt'] ?? '').toString())?.toLocal();

        if (createdAt == null) continue;

        final sameDay = createdAt.year == now.year &&
            createdAt.month == now.month &&
            createdAt.day == now.day;

        if (!sameDay) continue;

        todaySeconds += _asInt(raw['durationSeconds']);
      }

      final historyMinutes = todaySeconds ~/ 60;

      if (historyMinutes > todayMinutes) {
        todayMinutes = historyMinutes;
      }
    } catch (_) {
      todayMinutes = fallbackMinutes;
    }

    final todayCoins = todayMinutes ~/ 2;
    final rank = _rankForMinutes(todayMinutes);
    final users = _buildLeagueUsers(
      currentUserName: currentUserName,
      currentRank: rank,
      currentCoins: todayCoins,
    );

    if (!mounted) return;

    setState(() {
      _todayMinutes = todayMinutes;
      _todayCoins = todayCoins;
      _rank = rank;
      _currentUserName = currentUserName;
      _users = users;
      _loading = false;
    });
  }

  int _rankForMinutes(int minutes) {
    if (minutes >= 85) return 1;
    if (minutes >= 70) return 2;
    if (minutes >= 60) return 3;
    if (minutes >= 30) return 4;
    if (minutes >= 20) return 5;
    if (minutes >= 10) return 6;
    return 7;
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<_LeagueUser> _buildLeagueUsers({
    required String currentUserName,
    required int currentRank,
    required int currentCoins,
  }) {
    final names = _rotatingNames();

    final users = <_LeagueUser>[];

    for (var rank = 1; rank <= 7; rank++) {
      if (rank == currentRank) {
        users.add(_LeagueUser(currentUserName, currentCoins, true));
      } else {
        final name = names[(rank - 1) % names.length];
        final coins = _fakeCoinsForRank(
          rank: rank,
          currentRank: currentRank,
          currentCoins: currentCoins,
        );

        users.add(_LeagueUser(name, coins, false));
      }
    }

    return users;
  }

  List<String> _rotatingNames() {
    const pool = [
      'Sumeet',
      'Priya Chaudhary',
      'Aditya Kumar',
      'Shiva',
      'Jeyakanth',
      'Surya',
      'Libin',
      'Raghu',
      'Aarav',
      'Harsh',
      'Venky',
      'Kumar',
      'Dev',
      'Sathish',
      'Rajbir',
      'Abhi',
      'Shankar',
      'Amresh',
    ];

    final start = DateTime.now().millisecondsSinceEpoch % pool.length;

    return [
      for (var i = 0; i < pool.length; i++) pool[(start + i) % pool.length],
    ];
  }

  int _fakeCoinsForRank({
    required int rank,
    required int currentRank,
    required int currentCoins,
  }) {
    if (rank < currentRank) {
      return currentCoins + ((currentRank - rank) * 8) + 6;
    }

    if (rank > currentRank) {
      final lower = currentCoins - ((rank - currentRank) * 5);
      return lower < 0 ? 0 : lower;
    }

    return currentCoins;
  }

  String get _practiceTodayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  bool _isPracticeYesterday(String? dateKey) {
    if (dateKey == null || dateKey.isEmpty) return false;

    final parts = dateKey.split('-');
    if (parts.length != 3) return false;

    final savedDate = DateTime.tryParse(
      '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}',
    );

    if (savedDate == null) return false;

    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));

    return savedDate.year == yesterday.year &&
        savedDate.month == yesterday.month &&
        savedDate.day == yesterday.day;
  }

  Future<int> _completePracticeStreakLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCompletedDate =
        prefs.getString('mindcare_practice_last_completed_date');

    if (lastCompletedDate == _practiceTodayKey) {
      return prefs.getInt('mindcare_practice_streak') ?? 1;
    }

    final currentStreak = prefs.getInt('mindcare_practice_streak') ?? 0;
    final newStreak =
        _isPracticeYesterday(lastCompletedDate) ? currentStreak + 1 : 1;

    await prefs.setString(
      'mindcare_practice_last_completed_date',
      _practiceTodayKey,
    );
    await prefs.setInt('mindcare_practice_streak', newStreak);

    return newStreak;
  }

  Future<void> _handleContinue() async {
    const requiredCallSeconds = 20 * 60;

    if (widget.durationSeconds < requiredCallSeconds) {
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }

    final currentStreak = await _completePracticeStreakLocal();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StreakCelebrationScreen(
          currentStreak: currentStreak,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _loading
        ? "Calculating your league rank..."
        : "You've moved up to Rank $_rank in the\nGrand Master League";

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              const Icon(
                Icons.workspace_premium,
                color: Color(0xFFFACC15),
                size: 110,
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!_loading) ...[
                const SizedBox(height: 10),
                Text(
                  "Today: $_todayMinutes min • $_todayCoins coins",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF6366F1),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF374151)),
                        ),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            color: Color(0xFF374151),
                          ),
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            final isMe = user.isCurrentUser;

                            return Container(
                              color: isMe ? const Color(0xFF4B5563) : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      "${index + 1}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: isMe
                                        ? const Color(0xFF0F766E)
                                        : const Color(0xFF334155),
                                    child: Text(
                                      user.name.characters.first.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      user.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "${user.coins}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.monetization_on,
                                    color: Color(0xFFFACC15),
                                    size: 22,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _handleContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    "Continue",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeagueUser {
  final String name;
  final int coins;
  final bool isCurrentUser;

  const _LeagueUser(this.name, this.coins, this.isCurrentUser);
}

class StreakCelebrationScreen extends StatelessWidget {
  final int currentStreak;

  const StreakCelebrationScreen({
    super.key,
    required this.currentStreak,
  });

  @override
  Widget build(BuildContext context) {
    final safeStreak = currentStreak <= 0 ? 1 : currentStreak;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 44, 24, 28),
          child: Column(
            children: [
              const Spacer(),
              const Text(
                "You're Making Progress!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 34),
              const Icon(
                Icons.local_fire_department,
                color: Color(0xFFF97316),
                size: 130,
              ),
              const SizedBox(height: 20),
              Text(
                "Day $safeStreak",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "Talk with calm people and maintain your streak.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    "Continue",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardStageScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String buttonText;
  final VoidCallback onPressed;

  const _RewardStageScaffold({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3730A3),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 44, 24, 28),
          child: Column(
            children: [
              if (title.isNotEmpty)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const SizedBox(height: 36),
              const Spacer(),
              Icon(icon, color: iconColor, size: 120),
              const SizedBox(height: 34),
              if (value.isNotEmpty) ...[
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 84,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    buttonText,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
