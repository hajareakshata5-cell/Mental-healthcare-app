import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
// removed debug-only foundation import
import 'package:shared_preferences/shared_preferences.dart';

import 'services/api.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'services/webrtc_call_service.dart';
import 'features/calls/advanced_call_tab.dart';
import 'features/detox/digital_detox_tab.dart';
import 'features/premium/advanced_premium_tab.dart';
import 'features/sleep/sleep_system_tab.dart';
import 'features/sound/sound_therapy_tab.dart';
import 'ui/app_layout.dart';
import 'ui/premium_kit.dart';

class MentalHealthApp extends StatelessWidget {
  const MentalHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MindCare',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          surface: const Color(0xFFF7FAFC),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF155E75),
          tertiary: const Color(0xFFF59E0B),
          surfaceTint: Colors.transparent,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.76),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withValues(alpha: 0.72),
          indicatorColor: const Color(0x1A0F766E),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF0F766E)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF09111C),
        ).copyWith(
          primary: const Color(0xFF2DD4BF),
          secondary: const Color(0xFF7DD3FC),
          tertiary: const Color(0xFFFBBF24),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        cardTheme: CardThemeData(
          color: const Color(0xFF0B1420).withValues(alpha: 0.86),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.instance.getJwt();
      if (token != null) {
        final payload = await ApiClient.instance.fetchProfile();
        _profile = payload['profile'] as Map<String, dynamic>?;
      } else {
        SocketService.instance.disconnect();
        await WebRtcCallService.instance.disposeService();
        _profile = null;
      }
    } catch (_) {
      await AuthService.instance.clearJwt();
      SocketService.instance.disconnect();
      await WebRtcCallService.instance.disposeService();
      _profile = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: PremiumShellBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_profile == null) {
      return AuthScreen(onAuthenticated: _bootstrap);
    }

    return AppRoot(
      profile: _profile!,
      onRefreshProfile: _bootstrap,
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final Future<void> Function() onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _guestAlias = TextEditingController(text: 'calm_guest');

  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _guestAlias.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_register) {
        await AuthService.instance.registerWithEmail(
          _email.text.trim(),
          _password.text,
          _username.text.trim(),
        );
      } else {
        await AuthService.instance.signInWithEmail(
          _email.text.trim(),
          _password.text,
        );
      }
      await widget.onAuthenticated();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guest() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await AuthService.instance.signInAsGuest(_guestAlias.text.trim());
      await widget.onAuthenticated();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumShellBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 18),
              const PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PremiumPill(
                        label: 'Emotionally safe support',
                        icon: Icons.verified,
                        active: true),
                    SizedBox(height: 18),
                    PremiumTitle(
                      title: 'MindCare',
                      subtitle:
                          'Anonymous support, AI guidance, and healing systems in one calm premium experience.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              PremiumCard(
                child: Column(
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign in')),
                        ButtonSegment(value: true, label: Text('Register')),
                      ],
                      selected: {_register},
                      onSelectionChanged: (v) => setState(() {
                        _register = v.first;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_register ? 'Create account' : 'Continue'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('or continue anonymously'),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _guestAlias,
                      decoration: const InputDecoration(
                        labelText: 'Guest alias',
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _guest,
                        child: const Text('Continue anonymously'),
                      ),
                    ),
                    // debug helpers removed
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.profile,
    required this.onRefreshProfile,
  });

  final Map<String, dynamic> profile;
  final Future<void> Function() onRefreshProfile;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int _index = 0;
  late Map<String, dynamic> _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _reloadProfile() async {
    await widget.onRefreshProfile();
    final payload = await ApiClient.instance.fetchProfile();
    setState(() => _profile = payload['profile'] as Map<String, dynamic>);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardTab(profile: _profile, onRefresh: _reloadProfile),
      MoodTab(),
      const AiSupportTab(),
      AdvancedCallTab(profile: _profile),
      const SoundTherapyTab(key: Key('sound_tab')),
      const WellnessTab(),
      const SleepSystemTab(),
      const DigitalDetoxTab(),
      AdvancedPremiumTab(onSubscriptionUpdated: _reloadProfile),
    ];

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.favorite_rounded, color: Color(0xFF0F766E)),
            const SizedBox(width: 10),
            Text(_titleForIndex(_index)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await AuthService.instance.signOut();
              SocketService.instance.disconnect();
              await WebRtcCallService.instance.disposeService();
              await widget.onRefreshProfile();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: PremiumShellBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            height: 78,
            selectedIndex: _index,
            onDestinationSelected: (v) => setState(() => _index = v),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.insights_outlined), label: 'Mood'),
              NavigationDestination(
                  icon: Icon(Icons.smart_toy_outlined), label: 'AI'),
              NavigationDestination(
                  icon: Icon(Icons.call_outlined), label: 'Call'),
              NavigationDestination(
                  icon: Icon(Icons.graphic_eq_outlined), label: 'Sound'),
              NavigationDestination(
                  icon: Icon(Icons.favorite_outline), label: 'Wellness'),
              NavigationDestination(
                  icon: Icon(Icons.nightlight_round), label: 'Sleep'),
              NavigationDestination(
                  icon: Icon(Icons.do_not_disturb_on_outlined), label: 'Detox'),
              NavigationDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  label: 'Premium'),
            ],
          ),
        ),
      ),
    );
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Mood Tracking';
      case 2:
        return 'AI Emotional Support';
      case 3:
        return 'Anonymous Calls';
      case 4:
        return 'Sound Therapy';
      case 5:
        return 'Wellness Engine';
      case 6:
        return 'Sleep System';
      case 7:
        return 'Digital Detox';
      case 8:
        return 'Premium & Payments';
      default:
        return 'MindCare';
    }
  }
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.profile,
    required this.onRefresh,
  });

  final Map<String, dynamic> profile;
  final Future<void> Function() onRefresh;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  int _detoxStreak = 0;
  int _focusSessions = 0;
  double _avgSleepHours = 0;
  int _sleepEntries = 0;
  int _soundRecent = 0;
  bool _loading = true;
  int _healingXp = 0;
  int _healingLevel = 1;
  int _meditationStreak = 0;
  int _hydrationStreak = 0;
  int _moodStreak = 0;

  String get _username => (widget.profile['username'] ?? 'user').toString();
  String get _alias =>
      (widget.profile['anonymousAlias'] ?? widget.profile['alias'] ?? 'anon')
          .toString();
  bool get _isSubscribed => widget.profile['isSubscribed'] == true;
  int get _freeCalls =>
      int.tryParse(widget.profile['freeCallsRemaining']?.toString() ?? '0') ??
      0;
  int get _wellnessScore {
    final score = 52 +
        (_detoxStreak * 4) +
        (_avgSleepHours * 5).round() +
        (_focusSessions * 2) +
        (_soundRecent * 2) +
        (_isSubscribed ? 8 : 0) +
        (_freeCalls > 0 ? 2 : 0);
    return score.clamp(0, 100);
  }

  @override
  void initState() {
    super.initState();
    _loadLocalSignals();
  }

  Future<void> _loadLocalSignals() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final sleepLogs = prefs.getStringList('sleep_logs_v1') ?? [];
    double sleepTotal = 0;
    _sleepEntries = sleepLogs.length;
    for (final raw in sleepLogs) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final hours = decoded['hours'];
        if (hours is num) {
          sleepTotal += hours.toDouble();
        }
      } catch (_) {}
    }

    _avgSleepHours = sleepLogs.isEmpty ? 0 : sleepTotal / sleepLogs.length;
    _detoxStreak = prefs.getInt('detox_streak_v1') ?? 0;
    final focusSessions = prefs.getStringList('focus_sessions_v1') ?? [];
    _focusSessions = focusSessions.length;
    final soundRecent = prefs.getStringList('sound_recent') ?? [];
    _soundRecent = soundRecent.length;

    // Extract persisted healing data from profile
    final healing = widget.profile['healing'] as Map<String, dynamic>?;
    if (healing != null) {
      _healingXp = int.tryParse(healing['wellnessXp']?.toString() ?? '0') ?? 0;
      _healingLevel =
          int.tryParse(healing['healingLevel']?.toString() ?? '1') ?? 1;
      _meditationStreak =
          int.tryParse(healing['meditationStreak']?.toString() ?? '0') ?? 0;
      _hydrationStreak =
          int.tryParse(healing['hydrationStreak']?.toString() ?? '0') ?? 0;
      _moodStreak = int.tryParse(healing['moodStreak']?.toString() ?? '0') ?? 0;
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await widget.onRefresh();
    await _loadLocalSignals();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumShellBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          PremiumCard(
            child: _DashboardHero(
              username: _username,
              alias: _alias,
              wellnessScore: _wellnessScore,
              isSubscribed: _isSubscribed,
              freeCalls: _freeCalls,
              detoxStreak: _detoxStreak,
              sleepHours: _avgSleepHours,
              healingXp: _healingXp,
              healingLevel: _healingLevel,
              meditationStreak: _meditationStreak,
              hydrationStreak: _hydrationStreak,
              moodStreak: _moodStreak,
              loading: _loading,
              onRefresh: _refreshAll,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Healing XP',
                  value: '$_healingXp',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Level',
                  value: '$_healingLevel',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Mood Streak',
                  value: '$_moodStreak days',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Hydration',
                  value: '$_hydrationStreak days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Avg Sleep',
                  value: '${_avgSleepHours.toStringAsFixed(1)}h',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatBox(
                  label: 'Meditation',
                  value: '$_meditationStreak days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const PremiumSectionHeader(
            title: 'Today\'s healing path',
            subtitle: 'Small actions that move the score forward',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PremiumPill(
                  label: 'Meditation',
                  icon: Icons.self_improvement,
                  active: _focusSessions > 0),
              PremiumPill(
                  label: 'Water',
                  icon: Icons.water_drop_outlined,
                  active: _avgSleepHours > 0),
              const PremiumPill(
                  label: 'Mood', icon: Icons.auto_awesome, active: true),
              PremiumPill(
                  label: 'Sleep',
                  icon: Icons.nightlight_round_outlined,
                  active: _sleepEntries > 0),
              PremiumPill(
                  label: 'Wellness',
                  icon: Icons.favorite_border,
                  active: _detoxStreak > 0),
            ],
          ),
          const SizedBox(height: 12),
          _InsightRow(
            title: 'Wellness score',
            subtitle: 'Composite of local healing activity and premium access',
            value: _wellnessScore,
          ),
          const SizedBox(height: 10),
          const _FeatureTile(
            icon: Icons.psychology_outlined,
            title: 'AI Copilot Active',
            subtitle:
                'Emotion-aware responses and recommendation engine ready.',
          ),
          const SizedBox(height: 8),
          const _FeatureTile(
            icon: Icons.call_outlined,
            title: 'Call Access Control',
            subtitle:
                '2-free-call policy + premium unlock is enforced by backend.',
          ),
          const SizedBox(height: 8),
          const _FeatureTile(
            icon: Icons.bolt_outlined,
            title: 'Realtime Core',
            subtitle:
                'Socket.IO room chat, signaling, and presence integrated.',
          ),
          const SizedBox(height: 8),
          const _FeatureTile(
            icon: Icons.auto_graph,
            title: 'Healing journey',
            subtitle:
                'Streaks, sleep logs, focus sessions, and sound history are reflected here.',
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.username,
    required this.alias,
    required this.wellnessScore,
    required this.isSubscribed,
    required this.freeCalls,
    required this.detoxStreak,
    required this.sleepHours,
    required this.healingXp,
    required this.healingLevel,
    required this.meditationStreak,
    required this.hydrationStreak,
    required this.moodStreak,
    required this.loading,
    required this.onRefresh,
  });

  final String username;
  final String alias;
  final int wellnessScore;
  final bool isSubscribed;
  final int freeCalls;
  final int detoxStreak;
  final double sleepHours;
  final int healingXp;
  final int healingLevel;
  final int meditationStreak;
  final int hydrationStreak;
  final int moodStreak;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF07111F), Color(0xFF0F766E), Color(0xFF155E75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome, $username',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              )),
                      const SizedBox(height: 8),
                      Text('Anonymous alias: $alias',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                _RingScore(value: wellnessScore),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroMetric(
                    label: 'Plan', value: isSubscribed ? 'Premium' : 'Free'),
                _HeroMetric(label: 'Free calls', value: '$freeCalls'),
                _HeroMetric(label: 'Streak', value: '$detoxStreak d'),
                _HeroMetric(
                    label: 'Sleep', value: '${sleepHours.toStringAsFixed(1)}h'),
                _HeroMetric(label: 'Wellness', value: '$wellnessScore/100'),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: loading ? null : onRefresh,
                  child: Text(loading ? 'Refreshing…' : 'Refresh dashboard'),
                ),
                const _PremiumBadge(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingScore extends StatelessWidget {
  const _RingScore({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final normalized = (value / 100).clamp(0.0, 1.0);
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: normalized,
            strokeWidth: 8,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
          ),
          Text(
            '$value',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFFFBBF24), Color(0xFFFB7185)]),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text('Commercial wellness mode',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow(
      {required this.title, required this.subtitle, required this.value});

  final String title;
  final String subtitle;
  final int value;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (value / 100).clamp(0.0, 1.0),
                  strokeWidth: 8,
                ),
                Text('$value',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MoodTab extends StatefulWidget {
  const MoodTab({super.key});

  @override
  State<MoodTab> createState() => _MoodTabState();
}

class _MoodTabState extends State<MoodTab> {
  final _notes = TextEditingController();
  String _mood = 'calm';
  double _stress = 5;
  double _energy = 5;
  bool _busy = false;
  String? _analysis;
  List<dynamic> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ApiClient.instance.fetchMoodHistory(limit: 20);
      setState(() => _history = (res['history'] as List<dynamic>? ?? []));
    } catch (_) {}
  }

  Future<void> _submitMood() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.submitMood(
        mood: _mood,
        stress: _stress.round(),
        energy: _energy.round(),
        notes: _notes.text.trim(),
      );
      final prompt = _notes.text.trim().isEmpty
          ? 'I feel $_mood with stress ${_stress.round()} and energy ${_energy.round()}'
          : _notes.text.trim();
      final analyzed = await ApiClient.instance.analyzeMoodText(prompt);
      setState(() {
        _analysis = (analyzed['analysis'] ??
                analyzed['text'] ??
                analyzed['message'] ??
                analyzed['result'] ??
                analyzed.toString())
            .toString();
      });
      await _loadHistory();
    } catch (e) {
      setState(() => _analysis = 'Mood analysis error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: appTabPadding(context),
      children: [
        const PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PremiumPill(
                  label: 'Mood tracking', icon: Icons.favorite, active: true),
              SizedBox(height: 12),
              Text(
                'Log how you feel and get an AI mood insight.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                      label: const Text('calm'),
                      selected: _mood == 'calm',
                      onSelected: (_) => setState(() => _mood = 'calm')),
                  ChoiceChip(
                      label: const Text('anxious'),
                      selected: _mood == 'anxious',
                      onSelected: (_) => setState(() => _mood = 'anxious')),
                  ChoiceChip(
                      label: const Text('sad'),
                      selected: _mood == 'sad',
                      onSelected: (_) => setState(() => _mood = 'sad')),
                  ChoiceChip(
                      label: const Text('stressed'),
                      selected: _mood == 'stressed',
                      onSelected: (_) => setState(() => _mood = 'stressed')),
                  ChoiceChip(
                      label: const Text('tired'),
                      selected: _mood == 'tired',
                      onSelected: (_) => setState(() => _mood = 'tired')),
                ],
              ),
              const SizedBox(height: 16),
              Text('Stress: ${_stress.round()}'),
              Slider(
                  value: _stress,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _stress.round().toString(),
                  onChanged: (v) => setState(() => _stress = v)),
              Text('Energy: ${_energy.round()}'),
              Slider(
                  value: _energy,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _energy.round().toString(),
                  onChanged: (v) => setState(() => _energy = v)),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'What happened today?',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submitMood,
                  child: Text(_busy ? 'Saving...' : 'Save mood'),
                ),
              ),
            ],
          ),
        ),
        if (_analysis != null) ...[
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI insight',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_analysis!),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text('Recent history',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ..._history.map((row) {
          final mood =
              (row is Map ? row['mood'] : null)?.toString() ?? 'unknown';
          final notes = (row is Map ? row['notes'] : null)?.toString() ?? '';
          final stress = (row is Map ? row['stress'] : null)?.toString() ?? '';
          final energy = (row is Map ? row['energy'] : null)?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PremiumCard(
              child:
                  Text('$mood  •  stress $stress  •  energy $energy\n$notes'),
            ),
          );
        }),
      ],
    );
  }
}

class AiSupportTab extends StatefulWidget {
  const AiSupportTab({super.key});

  @override
  State<AiSupportTab> createState() => _AiSupportTabState();
}

class _AiSupportTabState extends State<AiSupportTab> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [
    {
      'role': 'AI',
      'text': 'I am here with you. Share what is on your mind.',
      'emotion': 'supportive',
      'riskLevel': 'low',
      'suggestions': <String>['You can start with one sentence.'],
      'doctorSuggestion': {
        'title': 'Self-help only',
        'recommendation':
            'Use self-care first: hydrate, journal, breathe slowly, and keep a steady sleep routine. This is not a diagnosis. Consider speaking with a licensed mental health professional if things persist.',
      },
      'meditationSuggestion': {
        'type': 'body-scan',
        'durationMinutes': 5,
        'reason':
            'A short body-scan gives a calm, low-effort reset for general emotional overload.',
      },
    },
  ];
  String _voiceMode = 'support';
  bool _busy = false;

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'You', 'text': text});
      _messages.add({'role': 'AI', 'loading': true});
      _input.clear();
      _busy = true;
    });
    try {
      final response = await ApiClient.instance.chatWithAi(
        text,
        mode: _voiceMode,
        context: const {
          'screen': 'support_chat',
          'flow': 'original_mindcare',
        },
        stressLevel: 5,
        conversationHistory: _messages
            .map((m) => '${m['role']}: ${m['text']}')
            .toList(growable: false),
      );

      final normalized = _normalizeAssistantResponse(text, response);
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((entry) => entry['loading'] == true);
        _messages.add(normalized);
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((entry) => entry['loading'] == true);
        _messages.add({
          'role': 'System',
          'text': 'Chat service error: $e',
        });
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _normalizeAssistantResponse(
    String message,
    Map<String, dynamic> response,
  ) {
    final reply = (response['reply'] ??
            response['response'] ??
            response['message'] ??
            response['text'] ??
            response['summary'] ??
            response['result'] ??
            response.toString())
        .toString();
    final emotion = (response['emotion'] ?? _detectEmotion(message)).toString();
    final riskLevel = (response['riskLevel'] ?? _detectRiskLevel(message))
        .toString();
    final suggestions = _toStringList(response['suggestions']);
    final doctorSuggestion = _asMap(response['doctorSuggestion']) ??
        _buildDoctorSuggestion(riskLevel);
    final meditationSuggestion = _asMap(response['meditationSuggestion']) ??
        _buildMeditationSuggestion(message, emotion, riskLevel);

    return {
      'role': 'AI',
      'text': reply,
      'emotion': emotion,
      'riskLevel': riskLevel,
      'suggestions': suggestions.isNotEmpty
          ? suggestions
          : _defaultSuggestions(riskLevel, emotion),
      'doctorSuggestion': doctorSuggestion,
      'meditationSuggestion': meditationSuggestion,
    };
  }

  Map<String, dynamic> _buildDoctorSuggestion(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return {
          'title': 'Urgent professional support recommended',
          'recommendation':
              'This is not a diagnosis. Consider speaking with a licensed mental health professional. If you may act on self-harm thoughts, call local emergency services or a crisis line now.',
        };
      case 'moderate':
        return {
          'title': 'Therapist or counselor suggestion',
          'recommendation':
              'This is not a diagnosis. Consider speaking with a licensed mental health professional. A counselor or therapist can help you build a safer support plan.',
        };
      default:
        return {
          'title': 'Self-help only',
          'recommendation':
              'Use self-care first: hydrate, journal, breathe slowly, and keep a steady sleep routine. This is not a diagnosis. Consider speaking with a licensed mental health professional if things persist.',
        };
    }
  }

  Map<String, dynamic> _buildMeditationSuggestion(
    String message,
    String emotion,
    String riskLevel,
  ) {
    final lower = message.toLowerCase();
    if (riskLevel.toLowerCase() == 'high' || emotion == 'panic') {
      return {
        'type': 'grounding',
        'durationMinutes': 5,
        'reason':
            'Grounding helps reduce panic-style arousal first, then professional support can follow if needed.',
      };
    }
    if (emotion == 'sleep' || lower.contains('sleep') || lower.contains('tired')) {
      return {
        'type': 'sleep',
        'durationMinutes': 5,
        'reason':
            'A body-scan sleep meditation can help settle the nervous system and support rest.',
      };
    }
    if (lower.contains('sad') || lower.contains('empty') || lower.contains('hopeless')) {
      return {
        'type': 'gratitude',
        'durationMinutes': 5,
        'reason':
            'Gratitude or journaling meditation can gently shift focus when sadness is present.',
      };
    }
    if (lower.contains('stress') || lower.contains('anxious') || lower.contains('tense')) {
      return {
        'type': 'breathing',
        'durationMinutes': 5,
        'reason':
            'Breathing meditation is a lightweight way to reduce stress without overwhelming the user.',
      };
    }
    return {
      'type': 'body-scan',
      'durationMinutes': 5,
      'reason': 'A short body-scan gives a calm, low-effort reset for general emotional overload.',
    };
  }

  List<String> _defaultSuggestions(String riskLevel, String emotion) {
    switch (riskLevel.toLowerCase()) {
      case 'high':
        return [
          'This is not a diagnosis. Consider speaking with a licensed mental health professional.',
          'If you might act on self-harm thoughts, call local emergency services or a crisis line now.',
        ];
      case 'moderate':
        return [
          'This is not a diagnosis. Consider speaking with a licensed mental health professional.',
          'A counselor or therapist can help you build a safer support plan.',
          emotion == 'sleep'
              ? 'Try a calm bedtime routine and keep the next step very small.'
              : 'Use a short breathing or grounding exercise for 3 minutes.',
        ];
      default:
        return [
          'Use a short breathing reset or grounding pause.',
          'Hydrate, journal for a few minutes, and keep the next step small.',
          'Try a sleep hygiene check: dim lights, reduce screens, and settle into a quiet routine.',
        ];
    }
  }

  List<String> _toStringList(Object? value) {
    if (value is List) {
      return value
          .map((entry) => entry.toString().trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, val) => MapEntry(key.toString(), val));
    return null;
  }

  String _detectEmotion(String message) {
    final lower = message.toLowerCase();
    if (_voiceMode == 'sleep' || lower.contains('sleep') || lower.contains('tired')) {
      return 'sleep';
    }
    if (_voiceMode == 'panic' || lower.contains('panic') || lower.contains('anxious')) {
      return 'panic';
    }
    if (_voiceMode == 'grounding') {
      return 'grounding';
    }
    return 'supportive';
  }

  String _detectRiskLevel(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('suicide') || lower.contains('kill myself') || lower.contains('self-harm')) {
      return 'high';
    }
    if (_voiceMode == 'panic' || lower.contains('panic') || lower.contains('overwhelmed')) {
      return 'high';
    }
    if (_voiceMode == 'sleep' || lower.contains('sad') || lower.contains('lonely') || lower.contains('angry')) {
      return 'moderate';
    }
    return 'low';
  }

  Future<void> _sendVoice() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add({'role': 'You', 'text': text});
      _input.clear();
      _busy = true;
    });
    try {
      final response = await ApiClient.instance.voiceWithAi(
        text,
        voiceMode: _voiceMode,
        stressLevel: 5,
        conversationHistory: _messages
            .map((m) => '${m['role']}: ${m['text']}')
            .toList(growable: false),
      );
      final summary = (response['summary'] ??
              response['response'] ??
              response['message'] ??
              response['text'] ??
              '')
          .toString();
      final rate =
          (response['rate'] ?? response['speaking_rate'] ?? '').toString();
      final steps = response['steps'] ??
          response['breathing_steps'] ??
          response['breathingSteps'];
      final stepText = steps is List && steps.isNotEmpty
          ? '\n\nBreathing:\n${steps.map((e) => '• $e').join('\n')}'
          : '';
      final reply =
          '${summary.isEmpty ? 'Voice support complete.' : summary}${rate.isEmpty ? '' : '\nSpeaking rate: $rate'}$stepText';
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'AI', 'text': reply});
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'System', 'text': 'Voice service error: $e'});
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PremiumPill(
                            label: 'AI companion',
                            icon: Icons.auto_awesome,
                            active: true,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'A calm, streaming therapeutic conversation.',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Support'),
                      selected: _voiceMode == 'support',
                      onSelected: (_) => setState(() => _voiceMode = 'support'),
                    ),
                    ChoiceChip(
                      label: const Text('Grounding'),
                      selected: _voiceMode == 'grounding',
                      onSelected: (_) =>
                          setState(() => _voiceMode = 'grounding'),
                    ),
                    ChoiceChip(
                      label: const Text('Panic'),
                      selected: _voiceMode == 'panic',
                      onSelected: (_) => setState(() => _voiceMode = 'panic'),
                    ),
                    ChoiceChip(
                      label: const Text('Sleep'),
                      selected: _voiceMode == 'sleep',
                      onSelected: (_) => setState(() => _voiceMode = 'sleep'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: appTabPadding(
              context,
              top: 8,
              baseBottom: 28,
              bottomNavBuffer: 96,
              extraBottom: 180,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final msg = _messages[i];
              final user = msg['role'] == 'You';
              final loading = msg['loading'] == true;
              final system = msg['role'] == 'System';
              return Align(
                alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                    gradient: user
                        ? const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF155E75)])
                        : const LinearGradient(
                            colors: [Color(0xCCFFFFFF), Color(0xCCF7FAFC)]),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 18,
                          offset: Offset(0, 8)),
                    ],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(user ? 18 : 4),
                      bottomRight: Radius.circular(user ? 4 : 18),
                    ),
                  ),
                    child: loading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  user
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Thinking…',
                              style: TextStyle(
                                color: user
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                        : Column(
                          crossAxisAlignment: user
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['role'] ?? '',
                              style: TextStyle(
                                color: user
                                    ? Colors.white70
                                    : Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              msg['text'] ?? '',
                              style: TextStyle(
                                color: user
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                                height: 1.35,
                              ),
                            ),
                            if (!user) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _MiniChip(
                                    label:
                                        'Emotion: ${(msg['emotion'] ?? 'supportive').toString()}',
                                    color: const Color(0xFF155E75),
                                  ),
                                  _MiniChip(
                                    label:
                                        'Risk level: ${(msg['riskLevel'] ?? 'low').toString()}',
                                    color: const Color(0xFF0F766E),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _GuideBlock(
                                title: 'Doctor / therapist suggestion',
                                text: (msg['doctorSuggestion'] as Map?)?['recommendation']
                                        ?.toString() ??
                                    'This is not a diagnosis. Consider speaking with a licensed mental health professional.',
                              ),
                              const SizedBox(height: 8),
                              _GuideBlock(
                                title: 'Meditation suggestion',
                                text: _meditationSummary(msg['meditationSuggestion']),
                              ),
                              if ((msg['suggestions'] as List?)?.isNotEmpty == true) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final suggestion in msg['suggestions'] as List)
                                      _MiniChip(
                                        label: suggestion.toString(),
                                        color: const Color(0xFFF59E0B),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                            if (system) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Try again in a moment. If this keeps happening, the backend may be offline.',
                                style: TextStyle(
                                  color: user
                                      ? Colors.white70
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: PremiumCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Share what you are feeling...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _send,
                        child: const Icon(Icons.send),
                      ),
                      const SizedBox(height: 6),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _sendVoice,
                        icon: const Icon(Icons.graphic_eq),
                        label: const Text('Voice'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )
      ],
    );
  }

  String _meditationSummary(Object? meditation) {
    final data = _asMap(meditation);
    if (data == null) {
      return 'Recommended: 5 min grounding meditation because your message suggests anxiety/stress.';
    }
    final type = (data['type'] ?? 'body-scan').toString();
    final duration = (data['durationMinutes'] ?? 5).toString();
    final reason = (data['reason'] ?? 'calm reset').toString();
    return 'Recommended: $duration min $type meditation because $reason';
  }
}

class ConnectTab extends StatefulWidget {
  const ConnectTab({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<ConnectTab> createState() => _ConnectTabState();
}

class _ConnectTabState extends State<ConnectTab> {
  final _room = TextEditingController(text: 'global_support');
  final _peerAlias = TextEditingController(text: 'ai_support');
  final _message = TextEditingController();

  final List<String> _events = [];
  bool _connected = false;
  String _callState = 'idle';
  int _seconds = 0;
  Timer? _timer;

  String get _alias =>
      (widget.profile['anonymousAlias'] ?? widget.profile['alias'] ?? 'anon')
          .toString();

  @override
  void dispose() {
    _timer?.cancel();
    _room.dispose();
    _peerAlias.dispose();
    _message.dispose();
    SocketService.instance.disconnect();
    super.dispose();
  }

  void _connect() {
    SocketService.instance.connect(baseUrl: ApiClient.instance.baseUrl);
    SocketService.instance.on('connect', (_) {
      if (!mounted) return;
      setState(() => _connected = true);
      _log('Connected to realtime server');
    });
    SocketService.instance.on('presence', (payload) {
      _log('Presence: ${payload.toString()}');
    });
    SocketService.instance.on('chat-message', (payload) {
      _log('Chat: ${payload['senderAlias']}: ${payload['body']}');
    });
    SocketService.instance.on('call-state', (payload) {
      final state = (payload['state'] ?? 'unknown').toString();
      setState(() => _callState = state);
      if (state == 'connected') {
        _timer?.cancel();
        _seconds = 0;
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
      }
      if (state == 'ended') {
        _timer?.cancel();
      }
      _log('Call state: $state');
    });
  }

  void _joinRoom() {
    SocketService.instance.emit('join-room', {
      'roomId': _room.text.trim(),
      'alias': _alias,
      'userId': widget.profile['_id'] ?? widget.profile['id'] ?? _alias,
    });
    _log('Joined room ${_room.text.trim()}');
  }

  void _sendMessage() {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    SocketService.instance.emit('chat-message', {
      'roomId': _room.text.trim(),
      'senderAlias': _alias,
      'recipientAlias': _peerAlias.text.trim(),
      'body': text,
    });
    _log('You: $text');
    _message.clear();
  }

  Future<void> _startCall() async {
    try {
      final res = await ApiClient.instance.startCall(
        peerAlias: _peerAlias.text.trim(),
      );
      final freeCalls = res['call']?['freeCallsRemaining'];
      _log('Call access granted. Free calls remaining: $freeCalls');
      SocketService.instance.emit('call-initiate', {
        'roomId': _room.text.trim(),
        'recipientAlias': _peerAlias.text.trim(),
      });
    } catch (e) {
      _log('Call blocked: $e');
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Premium Required'),
          content: const Text(
              'Your free call limit has been reached. Upgrade in Premium tab.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _log(String text) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, text);
      if (_events.length > 80) _events.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: appTabPadding(context),
      children: [
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _room,
                      decoration: const InputDecoration(
                        labelText: 'Room ID',
                        prefixIcon: Icon(Icons.group_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _peerAlias,
                      decoration: const InputDecoration(
                        labelText: 'Peer alias',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _connected ? null : _connect,
                    child: const Text('Connect Socket'),
                  ),
                  OutlinedButton(
                    onPressed: _connected ? _joinRoom : null,
                    child: const Text('Join Room'),
                  ),
                  OutlinedButton(
                    onPressed: _connected ? _startCall : null,
                    child: const Text('Start Anonymous Call'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  PremiumPill(
                      label: _connected ? 'Connected' : 'Offline',
                      icon: Icons.circle,
                      active: _connected),
                  const SizedBox(width: 8),
                  PremiumPill(
                      label: 'State: $_callState',
                      icon: Icons.call,
                      active: _callState == 'connected'),
                  const SizedBox(width: 8),
                  PremiumPill(
                      label: 'Timer $_seconds s',
                      icon: Icons.timer_outlined,
                      active: _seconds > 0),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PremiumCard(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _message,
                  decoration: const InputDecoration(
                    hintText: 'Message room...',
                    prefixIcon: Icon(Icons.chat_bubble_outline),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _connected ? _sendMessage : null,
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const PremiumSectionHeader(
          title: 'Realtime Activity',
          subtitle: 'Presence, chat, and call state updates in one stream.',
        ),
        const SizedBox(height: 8),
        ..._events.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PremiumCard(
              padding: const EdgeInsets.all(12),
              child: Text(e),
            ),
          ),
        ),
      ],
    );
  }
}

class WellnessTab extends StatefulWidget {
  const WellnessTab({super.key});

  @override
  State<WellnessTab> createState() => _WellnessTabState();
}

class _WellnessTabState extends State<WellnessTab> {
  double _consumed = 1200;
  final _weight = TextEditingController(text: '60');
  final _age = TextEditingController(text: '24');
  String _activity = 'moderate';
  String _weather = 'normal';

  String _dailyPlan = 'Loading...';
  String _emergency = 'Loading...';
  String _aiPlan = 'Tap Generate AI wellness plan';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weight.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plan = await ApiClient.instance.getDailyPlan();
      final emergency = await ApiClient.instance.getEmergencyToolkit();
      setState(() {
        _dailyPlan = (plan['plan'] ?? plan).toString();
        _emergency = (emergency['panicMode'] ?? emergency).toString();
      });
    } catch (e) {
      setState(() {
        _dailyPlan = 'Unable to load daily plan: $e';
        _emergency = 'Unable to load emergency toolkit: $e';
      });
    }
  }

  Future<void> _saveWater() async {
    final now = DateTime.now();
    await ApiClient.instance.submitWaterLog(
      date:
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      consumedMl: _consumed.round(),
      weightKg: int.tryParse(_weight.text) ?? 60,
      age: int.tryParse(_age.text) ?? 24,
      activityLevel: _activity,
      weather: _weather,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Hydration log saved')));
  }

  Future<void> _logMeditation(String category, int minutes) async {
    await ApiClient.instance.createMeditationSession(
      category: category,
      durationMinutes: minutes,
      completed: true,
      recommendedByAI: category == 'ai-recommended',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Meditation session logged: $category $minutes min')),
    );
  }

  Future<void> _generateAiPlan() async {
    final plan = await ApiClient.instance.getAiWellnessPlan(
      mood: 'neutral',
      stressLevel: 5,
      sleepHours: 7,
      hydrationScore: (_consumed / 2500).clamp(0.0, 1.0),
    );
    setState(() => _aiPlan = plan.toString());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: appTabPadding(context),
      children: [
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PremiumSectionHeader(
                title: 'Hydration Tracker',
                subtitle:
                    'Calibrate your recovery rhythm with better water habits.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _weight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                        prefixIcon: Icon(Icons.monitor_weight_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        prefixIcon: Icon(Icons.cake_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Consumed water: ${_consumed.round()} ml'),
              Slider(
                value: _consumed,
                min: 0,
                max: 5000,
                divisions: 50,
                onChanged: (v) => setState(() => _consumed = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _activity,
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low activity')),
                  DropdownMenuItem(
                      value: 'moderate', child: Text('Moderate activity')),
                  DropdownMenuItem(value: 'high', child: Text('High activity')),
                ],
                onChanged: (v) => setState(() => _activity = v ?? 'moderate'),
                decoration: const InputDecoration(labelText: 'Activity level'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _weather,
                items: const [
                  DropdownMenuItem(value: 'cold', child: Text('Cold')),
                  DropdownMenuItem(value: 'normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'hot', child: Text('Hot')),
                ],
                onChanged: (v) => setState(() => _weather = v ?? 'normal'),
                decoration: const InputDecoration(labelText: 'Weather'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saveWater,
                  child: const Text('Save hydration'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PremiumSectionHeader(
                title: 'Meditation & Recovery',
                subtitle: 'Quick recovery actions with immediate logging.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _logMeditation('breathing', 10),
                    child: const Text('Breathing 10m'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _logMeditation('sleep', 20),
                    child: const Text('Sleep wind-down 20m'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _logMeditation('ai-recommended', 15),
                    child: const Text('AI recommended 15m'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PremiumSectionHeader(
                title: 'Daily Wellness Plan',
                subtitle: 'A calmer, more emotionally aware daily path.',
              ),
              const SizedBox(height: 8),
              Text(_dailyPlan),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _generateAiPlan,
                  child: const Text('Generate AI wellness plan'),
                ),
              ),
              const SizedBox(height: 8),
              Text(_aiPlan),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PremiumSectionHeader(
                title: 'Emergency Support Toolkit',
                subtitle: 'Fast access to grounding tools and support states.',
              ),
              const SizedBox(height: 8),
              Text(_emergency),
            ],
          ),
        ),
      ],
    );
  }
}

class PremiumTab extends StatefulWidget {
  const PremiumTab({super.key, required this.onSubscriptionUpdated});

  final Future<void> Function() onSubscriptionUpdated;

  @override
  State<PremiumTab> createState() => _PremiumTabState();
}

class _PremiumTabState extends State<PremiumTab> {
  Map<String, dynamic>? _subscription;
  List<dynamic> _history = const [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final sub = await ApiClient.instance.getSubscription();
      final history = await ApiClient.instance.getPaymentHistory();
      setState(() {
        _subscription = sub;
        _history = history['history'] as List<dynamic>? ?? [];
      });
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activatePlan(String plan) async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance
          .activateSubscription(plan: plan, autoRenew: true);
      await widget.onSubscriptionUpdated();
      await _load();
      setState(() => _message = 'Subscription activated: $plan');
    } catch (e) {
      setState(() => _message = 'Unable to activate subscription: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createPayment() async {
    setState(() => _busy = true);
    try {
      final order = await ApiClient.instance.createPaymentOrder();
      setState(() => _message =
          'Payment order created. Complete gateway flow with order: ${order['order']?['id'] ?? 'n/a'}');
      await _load();
    } catch (e) {
      setState(() => _message = 'Payment init failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subscription?['subscription'];
    final callAccess = _subscription?['callAccess'];

    return ListView(
      padding: appTabPadding(context),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Premium Subscription',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    'Current: ${sub?['plan'] ?? 'free'} (${sub?['status'] ?? 'free'})'),
                Text(
                    'Call access: ${callAccess?['allowed'] == true ? 'Allowed' : 'Locked'}'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _activatePlan('3m'),
                      child: const Text('3 months'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _activatePlan('6m'),
                      child: const Text('6 months'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : () => _activatePlan('12m'),
                      child: const Text('12 months'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _createPayment,
                  child: const Text('Create payment order (UPI/Card/Wallet)'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Payment History',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ..._history.map((row) => Card(
              child: ListTile(
                title:
                    Text('${row['plan'] ?? 'plan'} • ₹${row['amount'] ?? '-'}'),
                subtitle: Text(
                    '${row['status'] ?? 'status'} • ${row['gateway'] ?? 'gateway'} • ${row['createdAt'] ?? ''}'),
              ),
            )),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GuideBlock extends StatelessWidget {
  const _GuideBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x220F766E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(height: 1.35),
          ),
        ],
      ),
    );
  }
}
