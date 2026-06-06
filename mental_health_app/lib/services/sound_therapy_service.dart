import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TherapySignal {
  const TherapySignal({
    required this.moodHint,
    required this.riskLevel,
    required this.emotion,
    required this.source,
  });

  final String moodHint;
  final String riskLevel;
  final String emotion;
  final String source;

  const TherapySignal.unknown()
      : moodHint = 'steady',
        riskLevel = 'low',
        emotion = 'supportive',
        source = 'app';

  TherapySignal copyWith({
    String? moodHint,
    String? riskLevel,
    String? emotion,
    String? source,
  }) {
    return TherapySignal(
      moodHint: moodHint ?? this.moodHint,
      riskLevel: riskLevel ?? this.riskLevel,
      emotion: emotion ?? this.emotion,
      source: source ?? this.source,
    );
  }
}

enum SoundWaveProfile {
  sleep,
  rain,
  ocean,
  forest,
  whiteNoise,
  breathing,
  anxiety,
  focus,
}

class SoundTherapyTrack {
  const SoundTherapyTrack({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.icon,
    required this.accent,
    required this.moods,
    required this.defaultTimerMinutes,
    this.premiumOnly = false,
    this.lockedBadge = 'Premium',
    this.assetPath,
  });

  final String id;
  final String title;
  final String subtitle;
  final SoundWaveProfile profile;
  final IconData icon;
  final Color accent;
  final List<String> moods;
  final int defaultTimerMinutes;
  final bool premiumOnly;
  final String lockedBadge;
  final String? assetPath;
}

class SoundTherapyHistoryEntry {
  const SoundTherapyHistoryEntry({
    required this.trackId,
    required this.trackTitle,
    required this.completedAt,
    required this.completed,
    required this.durationMinutes,
  });

  final String trackId;
  final String trackTitle;
  final DateTime completedAt;
  final bool completed;
  final int durationMinutes;

  factory SoundTherapyHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SoundTherapyHistoryEntry(
      trackId: json['trackId']?.toString() ?? '',
      trackTitle: json['trackTitle']?.toString() ?? '',
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? '') ??
          DateTime.now(),
      completed: json['completed'] == true,
      durationMinutes: json['durationMinutes'] is int
          ? json['durationMinutes'] as int
          : int.tryParse(json['durationMinutes']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trackId': trackId,
      'trackTitle': trackTitle,
      'completedAt': completedAt.toIso8601String(),
      'completed': completed,
      'durationMinutes': durationMinutes,
    };
  }
}

class SoundTherapyNotice {
  const SoundTherapyNotice({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accent;
}

class SoundTherapyService extends ChangeNotifier {
  SoundTherapyService({SharedPreferences? prefs}) : _prefs = prefs;

  static const _premiumKey = 'sound_premium_unlocked';
  static const _favoritesKey = 'sound_favorites';
  static const _historyKey = 'sound_history';
  static const _soundStreakKey = 'sound_streak_days';
  static const _soundLastDateKey = 'sound_last_completed_date';
  static const _sleepStreakKey = 'sound_sleep_streak_days';
  static const _meditationStreakKey = 'sound_meditation_streak_days';
  static const _soundTimerKey = 'sound_timer_minutes';

  final SharedPreferences? _prefs;
  final AudioPlayer _player = AudioPlayer();
  final StreamController<SoundTherapyNotice> _noticeController =
      StreamController<SoundTherapyNotice>.broadcast();
  final Map<String, File> _cachedFiles = {};

  final List<SoundTherapyTrack> _tracks = const [
    SoundTherapyTrack(
      id: 'sleep',
      title: 'Sleep Sounds',
      subtitle: 'Deep sleep ambience with soft low tones.',
      profile: SoundWaveProfile.sleep,
      icon: Icons.nights_stay_outlined,
      accent: Color(0xFF2563EB),
      moods: ['sleep_issue', 'tired', 'restless'],
      defaultTimerMinutes: 20,
      assetPath: 'sounds/sleep.mpeg',
    ),
    SoundTherapyTrack(
      id: 'rain',
      title: 'Rain Sounds',
      subtitle: 'Soft rainfall for calm focus and settling the mind.',
      profile: SoundWaveProfile.rain,
      icon: Icons.water_drop_outlined,
      accent: Color(0xFF0EA5E9),
      moods: ['anxious', 'stressed', 'calm'],
      defaultTimerMinutes: 15,
      assetPath: 'sounds/rain.mpeg',
    ),
    SoundTherapyTrack(
      id: 'ocean',
      title: 'Ocean Waves',
      subtitle: 'Premium wave wash for slow breathing and decompression.',
      profile: SoundWaveProfile.ocean,
      icon: Icons.beach_access_outlined,
      accent: Color(0xFF0F766E),
      moods: ['stressed', 'overwhelmed'],
      defaultTimerMinutes: 20,
      assetPath: 'sounds/ocean.mpeg',
    ),
    SoundTherapyTrack(
      id: 'forest',
      title: 'Forest Nature',
      subtitle: 'Premium nature bed with soft air and bird-like textures.',
      profile: SoundWaveProfile.forest,
      icon: Icons.forest_outlined,
      accent: Color(0xFF15803D),
      moods: ['stressed', 'burnt_out'],
      defaultTimerMinutes: 18,
      assetPath: 'sounds/forest.mpeg',
    ),
    SoundTherapyTrack(
      id: 'white_noise',
      title: 'White Noise',
      subtitle: 'Clean neutral noise for sleep, masking, and reset.',
      profile: SoundWaveProfile.whiteNoise,
      icon: Icons.graphic_eq,
      accent: Color(0xFF64748B),
      moods: ['sleep_issue', 'focus_issue', 'neutral'],
      defaultTimerMinutes: 25,
      assetPath: 'sounds/white_noise.mpeg',
    ),
    SoundTherapyTrack(
      id: 'breathing',
      title: 'Breathing Audio',
      subtitle: 'Guided calm waves for meditation and paced breathing.',
      profile: SoundWaveProfile.breathing,
      icon: Icons.air_outlined,
      accent: Color(0xFF8B5CF6),
      moods: ['anxious', 'panic', 'need_grounding'],
      defaultTimerMinutes: 10,
      assetPath: 'sounds/breathing.mpeg',
    ),
    SoundTherapyTrack(
      id: 'anxiety_relief',
      title: 'Anxiety Relief',
      subtitle: 'Premium relief pad for panic spikes and tension drops.',
      profile: SoundWaveProfile.anxiety,
      icon: Icons.spa_outlined,
      accent: Color(0xFFB45309),
      moods: ['anxious', 'panic'],
      defaultTimerMinutes: 12,
      assetPath: 'sounds/anxiety_relief.mpeg',
    ),
    SoundTherapyTrack(
      id: 'focus',
      title: 'Focus Sounds',
      subtitle: 'Premium steady ambience for deep work and attention.',
      profile: SoundWaveProfile.focus,
      icon: Icons.center_focus_strong_outlined,
      accent: Color(0xFF7C3AED),
      moods: ['focus_issue', 'overwhelmed'],
      defaultTimerMinutes: 25,
      assetPath: 'sounds/focus.mpeg',
    ),
  ];

  bool _initialized = false;
  bool _premiumUnlocked = false;
  bool _isPlaying = false;
  bool _isPreviewMode = false;
  String? _currentTrackId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration? _timerTarget;
  Timer? _countdownTimer;
  int _soundStreakDays = 0;
  int _sleepStreakDays = 0;
  int _meditationStreakDays = 0;
  List<SoundTherapyHistoryEntry> _history = const [];
  final Set<String> _favoriteTrackIds = {};
  TherapySignal _signal = const TherapySignal.unknown();
  int _remainingSeconds = 0;

  Stream<SoundTherapyNotice> get notices => _noticeController.stream;

  List<SoundTherapyTrack> get tracks => List.unmodifiable(_tracks);
  bool get isPlaying => _isPlaying;
  bool get isPremiumUnlocked => _premiumUnlocked;
  bool get isPreviewMode => _isPreviewMode;
  String? get currentTrackId => _currentTrackId;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration? get timerTarget => _timerTarget;
  List<SoundTherapyHistoryEntry> get history => List.unmodifiable(_history);
  Set<String> get favoriteTrackIds => Set.unmodifiable(_favoriteTrackIds);
  int get soundStreakDays => _soundStreakDays;
  int get sleepStreakDays => _sleepStreakDays;
  int get meditationStreakDays => _meditationStreakDays;
  TherapySignal get signal => _signal;

  SoundTherapyTrack? get currentTrack =>
      _currentTrackId == null ? null : trackById(_currentTrackId!);

  List<SoundTherapyTrack> get recommendedTracks {
    final ids = recommendedTrackIdsForSignal(_signal);
    final ordered = <SoundTherapyTrack>[];
    for (final id in ids) {
      final track = trackById(id);
      if (track != null) ordered.add(track);
    }
    return ordered.isEmpty ? _tracks.take(3).toList(growable: false) : ordered;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await _getPrefs();
    _premiumUnlocked = prefs.getBool(_premiumKey) ?? false;
    _favoriteTrackIds
      ..clear()
      ..addAll(prefs.getStringList(_favoritesKey) ?? const <String>[]);
    _history = (prefs.getStringList(_historyKey) ?? const <String>[])
        .map((entry) {
          try {
            return SoundTherapyHistoryEntry.fromJson(
                jsonDecode(entry) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<SoundTherapyHistoryEntry>()
        .toList(growable: false);
    _soundStreakDays = prefs.getInt(_soundStreakKey) ?? 0;
    _sleepStreakDays = prefs.getInt(_sleepStreakKey) ?? 0;
    _meditationStreakDays = prefs.getInt(_meditationStreakKey) ?? 0;

    final soundLastDate = prefs.getString(_soundLastDateKey);
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';

    if (soundLastDate != null &&
        soundLastDate != todayKey &&
        !_isYesterday(soundLastDate, now)) {
      _soundStreakDays = 0;
      await prefs.setInt(_soundStreakKey, 0);
    }

    _currentTrackId = prefs.getString('$_soundTimerKey.trackId');
    final savedTimer = prefs.getInt(_soundTimerKey);
    if (savedTimer != null && savedTimer > 0) {
      _timerTarget = Duration(minutes: savedTimer);
      _remainingSeconds = savedTimer * 60;
    }

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _player.onPositionChanged.listen((value) {
      _position = value;
      notifyListeners();
    });
    _player.onDurationChanged.listen((value) {
      _duration = value;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      _finishSession(completed: true, fromPlayerComplete: true);
    });

    for (final track in _tracks) {
      await _ensureTrackFile(track);
    }
    notifyListeners();
  }

  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs!;
    return SharedPreferences.getInstance();
  }

  Future<void> _saveStringList(String key, Iterable<String> values) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(key, values.toList(growable: false));
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(key, value);
  }

  Future<void> _saveInt(String key, int value) async {
    final prefs = await _getPrefs();
    await prefs.setInt(key, value);
  }

  Future<File> _ensureTrackFile(SoundTherapyTrack track) async {
    final existing = _cachedFiles[track.id];
    if (existing != null && await existing.exists()) return existing;

    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}sound_therapy');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}${Platform.pathSeparator}${track.id}.wav');
    if (!await file.exists()) {
      await file.writeAsBytes(_buildWave(track.profile), flush: true);
    }
    _cachedFiles[track.id] = file;
    return file;
  }

  Uint8List _buildWave(SoundWaveProfile profile) {
    const sampleRate = 22050;
    const durationSeconds = 16;
    final totalSamples = sampleRate * durationSeconds;
    final pcm = Int16List(totalSamples);

    for (var i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final sample = _sample(profile, t, i).clamp(-1.0, 1.0);
      pcm[i] = (sample * 32767).round();
    }

    final bytesPerSample = 2;
    final dataSize = totalSamples * bytesPerSample;
    final buffer = BytesBuilder();
    final header = ByteData(44);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * bytesPerSample, Endian.little);
    header.setUint16(32, bytesPerSample, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataSize, Endian.little);
    buffer.add(header.buffer.asUint8List());
    buffer.add(pcm.buffer.asUint8List());
    return buffer.toBytes();
  }

  double _noise(int index, int seed) {
    final value = sin((index + seed) * 12.9898) * 43758.5453;
    return (value - value.floorToDouble()) * 2 - 1;
  }

  double _sample(SoundWaveProfile profile, double t, int index) {
    final low = sin(2 * pi * 110 * t);
    final mid = sin(2 * pi * 220 * t);
    final pulse = (sin(2 * pi * 0.12 * t) + 1) / 2;
    final breath = (sin(2 * pi * 0.08 * t) + 1) / 2;
    final envelope = 0.7 + 0.3 * sin(2 * pi * 0.03 * t).abs();

    switch (profile) {
      case SoundWaveProfile.sleep:
        return (low * 0.24 + mid * 0.08 + _noise(index, 1) * 0.05) *
            envelope *
            0.65;
      case SoundWaveProfile.rain:
        return (_noise(index, 7) * 0.32 + _noise(index, 11) * 0.12) *
            (0.72 + 0.28 * sin(2 * pi * 0.20 * t).abs());
      case SoundWaveProfile.ocean:
        return (_noise(index, 23) * 0.28 + low * 0.05) *
            (0.55 + 0.45 * sin(2 * pi * 0.06 * t).abs());
      case SoundWaveProfile.forest:
        return ((sin(2 * pi * 196 * t) * 0.12) +
                (sin(2 * pi * 294 * t) * 0.10) +
                (sin(2 * pi * 392 * t) * 0.08) +
                _noise(index, 19) * 0.05) *
            (0.82 + 0.18 * sin(2 * pi * 0.04 * t).abs());
      case SoundWaveProfile.whiteNoise:
        return _noise(index, 31) * 0.25;
      case SoundWaveProfile.breathing:
        return (low * 0.12 + mid * 0.06) * (0.35 + 0.65 * breath);
      case SoundWaveProfile.anxiety:
        return ((sin(2 * pi * 174 * t) * 0.15) +
                (sin(2 * pi * 285 * t) * 0.11) +
                _noise(index, 41) * 0.03) *
            (0.48 + 0.52 * pulse);
      case SoundWaveProfile.focus:
        return (sin(2 * pi * 432 * t) * 0.11 +
                sin(2 * pi * 528 * t) * 0.06 +
                _noise(index, 53) * 0.02) *
            (0.76 + 0.24 * sin(2 * pi * 0.5 * t).abs());
    }
  }

  SoundTherapyTrack? trackById(String id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  List<String> recommendedTrackIdsForSignal(TherapySignal signal) {
    final mood = signal.moodHint.toLowerCase();
    final risk = signal.riskLevel.toLowerCase();
    final emotion = signal.emotion.toLowerCase();

    if (risk == 'high' || mood.contains('anx') || emotion.contains('panic')) {
      return const ['breathing', 'rain', 'anxiety_relief'];
    }
    if (mood.contains('sleep')) {
      return const ['sleep', 'white_noise', 'breathing'];
    }
    if (mood.contains('focus')) {
      return const ['focus', 'white_noise'];
    }
    if (mood.contains('stress') || mood.contains('burnt')) {
      return const ['ocean', 'forest', 'breathing'];
    }
    return const ['breathing', 'rain', 'white_noise'];
  }

  void updateSignal(TherapySignal signal) {
    _signal = signal;
    notifyListeners();
  }

  bool isFavorite(String trackId) => _favoriteTrackIds.contains(trackId);

  Future<void> toggleFavorite(String trackId) async {
    if (_favoriteTrackIds.contains(trackId)) {
      _favoriteTrackIds.remove(trackId);
    } else {
      _favoriteTrackIds.add(trackId);
    }
    await _saveStringList(_favoritesKey, _favoriteTrackIds);
    notifyListeners();
  }

  Future<void> unlockPremium() async {
    _premiumUnlocked = true;
    await _saveBool(_premiumKey, true);
    _notifyNotice(
      const SoundTherapyNotice(
        title: 'Premium unlocked',
        message:
            'Ocean, forest, anxiety relief, and focus sounds are now open.',
        icon: Icons.workspace_premium,
        accent: Color(0xFF7C3AED),
      ),
    );
    notifyListeners();
    // ignore: avoid_print
    debugPrint('PREMIUM_OK');
  }

  Future<void> playTrack(String trackId, {bool forcePreview = false}) async {
    await initialize();
    final track = trackById(trackId);
    if (track == null) return;

    final premiumLocked =
        track.premiumOnly && !_premiumUnlocked && !forcePreview;
    final actualPreview = track.premiumOnly && !_premiumUnlocked;
    final file = await _ensureTrackFile(track);
    final timerMinutes = _timerTarget == null
        ? track.defaultTimerMinutes
        : _timerTarget!.inMinutes;
    final previewMinutes = actualPreview ? 1 : timerMinutes;

    await _player.stop();
    _currentTrackId = trackId;
    _isPreviewMode = actualPreview;
    _position = Duration.zero;
    _duration = Duration.zero;
    _timerTarget = Duration(minutes: previewMinutes);
    _remainingSeconds = previewMinutes * 60;
    await _saveInt(_soundTimerKey, previewMinutes);
    await _saveString(_soundTimerKeyTrackId, trackId);

    if (premiumLocked) {
      _notifyNotice(
        SoundTherapyNotice(
          title: '${track.title} preview',
          message:
              'Premium sound preview is playing. Unlock premium for the full loop.',
          icon: Icons.lock_open,
          accent: track.accent,
        ),
      );
    } else {
      _notifyNotice(
        SoundTherapyNotice(
          title: track.title,
          message: 'Sound therapy started. Timer set to ${previewMinutes} min.',
          icon: track.icon,
          accent: track.accent,
        ),
      );
    }

    await _player.setReleaseMode(ReleaseMode.loop);

    if (track.assetPath != null && track.assetPath!.isNotEmpty) {
      await _player.play(AssetSource(track.assetPath!));
    } else {
      await _player.play(DeviceFileSource(file.path));
    }

    _startCountdown();
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    _cancelCountdown();
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.resume();
    if (_currentTrackId != null && _remainingSeconds > 0) {
      _startCountdown(remainingSeconds: _remainingSeconds);
    }
    notifyListeners();
  }

  Future<void> stop({bool completed = false}) async {
    await _player.stop();
    _cancelCountdown();
    _finishSession(completed: completed, fromPlayerComplete: false);
  }

  Future<void> setTimerMinutes(int minutes) async {
    _timerTarget = Duration(minutes: minutes);
    _remainingSeconds = minutes * 60;
    await _saveInt(_soundTimerKey, minutes);
    if (_currentTrackId != null) {
      await _saveString(_soundTimerKeyTrackId, _currentTrackId!);
    }
    notifyListeners();
  }

  void _startCountdown({int? remainingSeconds}) {
    _countdownTimer?.cancel();
    final seconds = remainingSeconds ?? _remainingSeconds;
    if (seconds <= 0) return;
    _remainingSeconds = seconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _finishSession(completed: true, fromPlayerComplete: false);
        return;
      }
      _remainingSeconds -= 1;
      if (_remainingSeconds <= 0) {
        _remainingSeconds = 0;
        timer.cancel();
        _finishSession(completed: true, fromPlayerComplete: false);
        return;
      }
      notifyListeners();
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> completeCurrentSession() async {
    await stop(completed: true);
  }

  Future<void> _finishSession({
    required bool completed,
    required bool fromPlayerComplete,
  }) async {
    if (_currentTrackId == null) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    final track = trackById(_currentTrackId!);
    final completedAt = DateTime.now();
    final durationMinutes = _timerTarget?.inMinutes ?? 0;
    final wasFullCompletion =
        (completed || fromPlayerComplete) && !_isPreviewMode;
    _history = [
      SoundTherapyHistoryEntry(
        trackId: _currentTrackId!,
        trackTitle: track?.title ?? _currentTrackId!,
        completedAt: completedAt,
        completed: wasFullCompletion,
        durationMinutes: durationMinutes,
      ),
      ..._history,
    ].take(12).toList(growable: false);
    await _saveStringList(
      _historyKey,
      _history.map((entry) => jsonEncode(entry.toJson())),
    );
    final dayKey =
        '${completedAt.year}-${completedAt.month}-${completedAt.day}';
    final prefs = await _getPrefs();
    final previousDate = prefs.getString(_soundLastDateKey);
    if (wasFullCompletion) {
      if (previousDate == null) {
        _soundStreakDays = 1;
      } else if (_isYesterday(previousDate, completedAt)) {
        _soundStreakDays += 1;
      } else if (previousDate != dayKey) {
        _soundStreakDays = 1;
      }
      if (track?.id == 'sleep') {
        if (_isYesterday(
            prefs.getString('$_sleepStreakKey.lastDate'), completedAt)) {
          _sleepStreakDays += 1;
        } else {
          _sleepStreakDays = 1;
        }
        await prefs.setString('$_sleepStreakKey.lastDate', dayKey);
        _notifyNotice(
          SoundTherapyNotice(
            title: 'Sleep sound completed',
            message:
                'Sleep sound completed. Sleep streak: Day $_sleepStreakDays',
            icon: Icons.nights_stay_outlined,
            accent: const Color(0xFF2563EB),
          ),
        );
      } else if (track?.id == 'breathing') {
        if (_isYesterday(
            prefs.getString('$_meditationStreakKey.lastDate'), completedAt)) {
          _meditationStreakDays += 1;
        } else {
          _meditationStreakDays = 1;
        }
        await prefs.setString('$_meditationStreakKey.lastDate', dayKey);
        _notifyNotice(
          SoundTherapyNotice(
            title: 'Meditation audio completed',
            message:
                'Meditation audio completed. Meditation streak: Day $_meditationStreakDays',
            icon: Icons.air_outlined,
            accent: const Color(0xFF8B5CF6),
          ),
        );
      } else {
        _notifyNotice(
          SoundTherapyNotice(
            title: 'Sound therapy streak',
            message: 'Sound therapy streak: Day $_soundStreakDays',
            icon: Icons.local_fire_department_outlined,
            accent: const Color(0xFF0F766E),
          ),
        );
      }
      await prefs.setString(_soundLastDateKey, dayKey);
      await prefs.setInt(_soundStreakKey, _soundStreakDays);
      await prefs.setInt(_sleepStreakKey, _sleepStreakDays);
      await prefs.setInt(_meditationStreakKey, _meditationStreakDays);
      _notifyNotice(
        SoundTherapyNotice(
          title: track?.title ?? 'Sound therapy',
          message: '${track?.title ?? 'Sound therapy'} session completed.',
          icon: track?.icon ?? Icons.graphic_eq,
          accent: track?.accent ?? const Color(0xFF0F766E),
        ),
      );
    } else {
      _notifyNotice(
        SoundTherapyNotice(
          title: '${track?.title ?? 'Sound therapy'} stopped',
          message: 'Playback stopped. You can resume or choose a new sound.',
          icon: Icons.pause_circle_outline,
          accent: const Color(0xFF64748B),
        ),
      );
    }
    _currentTrackId = null;
    _isPreviewMode = false;
    _timerTarget = null;
    _remainingSeconds = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    notifyListeners();
  }

  bool _isYesterday(String? storedDate, DateTime now) {
    if (storedDate == null || storedDate.isEmpty) return false;
    final parts = storedDate.split('-');
    if (parts.length != 3) return false;
    final stored = DateTime.tryParse(
        '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}');
    if (stored == null) return false;
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    return stored.year == yesterday.year &&
        stored.month == yesterday.month &&
        stored.day == yesterday.day;
  }

  void _notifyNotice(SoundTherapyNotice notice) {
    if (!_noticeController.isClosed) {
      _noticeController.add(notice);
    }
  }

  String _soundTimerKeyTrackId = 'sound_timer_track_id';

  Future<void> _saveString(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  @override
  void dispose() {
    _cancelCountdown();
    _player.dispose();
    _noticeController.close();
    super.dispose();
  }
}
