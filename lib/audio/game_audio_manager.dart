import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AudioRunState { inactive, menu, playing, paused, over }

enum GameSoundEffect {
  orbitSwitch,
  gemCollect,
  collision,
  start,
  pause,
  resume,
}

abstract class GameAudioController extends ChangeNotifier {
  bool get musicEnabled;
  bool get effectsEnabled;

  Future<void> initialize();
  void setGameState(AudioRunState state);
  void setAppActive(bool active);
  Future<void> setMusicEnabled(bool enabled);
  Future<void> setEffectsEnabled(bool enabled);
  void playEffect(GameSoundEffect effect);
  Future<void> shutdown();
}

class GameAudioSettings extends ChangeNotifier {
  static const musicPreferenceKey = 'orbit_dash_music_enabled';
  static const effectsPreferenceKey = 'orbit_dash_effects_enabled';

  bool _musicEnabled = true;
  bool _effectsEnabled = true;

  bool get musicEnabled => _musicEnabled;
  bool get effectsEnabled => _effectsEnabled;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _musicEnabled = preferences.getBool(musicPreferenceKey) ?? true;
    _effectsEnabled = preferences.getBool(effectsPreferenceKey) ?? true;
    notifyListeners();
  }

  Future<void> setMusicEnabled(bool enabled) async {
    if (_musicEnabled == enabled) return;
    _musicEnabled = enabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(musicPreferenceKey, enabled);
  }

  Future<void> setEffectsEnabled(bool enabled) async {
    if (_effectsEnabled == enabled) return;
    _effectsEnabled = enabled;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(effectsPreferenceKey, enabled);
  }
}

class GameAudioManager extends GameAudioController {
  GameAudioManager({GameAudioSettings? settings})
    : settings = settings ?? GameAudioSettings() {
    this.settings.addListener(_settingsChanged);
  }

  @visibleForTesting
  static const menuMusicAsset = 'audio/orbit_game_suno_test.mp3';
  static const _effectAssets = <GameSoundEffect, String>{
    GameSoundEffect.orbitSwitch: 'audio/orbit_switch.wav',
    GameSoundEffect.gemCollect: 'audio/gem_collect.wav',
    GameSoundEffect.collision: 'audio/collision.wav',
    GameSoundEffect.start: 'audio/start_run.wav',
    GameSoundEffect.pause: 'audio/pause.wav',
    GameSoundEffect.resume: 'audio/resume.wav',
  };

  final GameAudioSettings settings;
  final AudioPlayer _menuPlayer = AudioPlayer();
  final List<AudioPlayer> _effectPlayers = List.generate(
    4,
    (_) => AudioPlayer(),
  );

  AudioRunState _gameState = AudioRunState.inactive;
  bool _appActive = true;
  bool _initialized = false;
  bool _menuStarted = false;
  int _nextEffectPlayer = 0;
  int _fadeToken = 0;
  Timer? _fadeTimer;
  double _menuVolume = 0;
  bool _musicDisabledLogged = false;
  final Set<String> _reportedAudioErrors = {};

  @override
  bool get musicEnabled => settings.musicEnabled;

  @override
  bool get effectsEnabled => settings.effectsEnabled;

  @override
  Future<void> initialize() async {
    await settings.load();
    await Future.wait([
      ..._effectPlayers.map(
        (player) => player.setReleaseMode(ReleaseMode.stop),
      ),
      _menuPlayer.setReleaseMode(ReleaseMode.loop),
    ]);
    _initialized = true;
    await _syncMusic();
  }

  @override
  void setGameState(AudioRunState state) {
    _gameState = state;
    unawaited(_syncMusic());
  }

  @override
  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    unawaited(_syncMusic());
  }

  @override
  Future<void> setMusicEnabled(bool enabled) async {
    await settings.setMusicEnabled(enabled);
    await _syncMusic();
  }

  @override
  Future<void> setEffectsEnabled(bool enabled) =>
      settings.setEffectsEnabled(enabled);

  @override
  void playEffect(GameSoundEffect effect) {
    if (!_initialized || !_appActive || !effectsEnabled) return;
    final asset = _effectAssets[effect];
    if (asset == null) return;
    final player = _effectPlayers[_nextEffectPlayer];
    _nextEffectPlayer = (_nextEffectPlayer + 1) % _effectPlayers.length;
    unawaited(_playEffectOn(player, asset));
  }

  Future<void> _playEffectOn(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: 0.72);
    } catch (error, stackTrace) {
      _logAudioError('Playing effect $asset', error, stackTrace);
    }
  }

  void _settingsChanged() {
    notifyListeners();
    if (_initialized) unawaited(_syncMusic());
  }

  Future<void> _syncMusic() async {
    if (!_initialized) return;
    _fadeTimer?.cancel();
    final token = ++_fadeToken;

    if (!_appActive) {
      try {
        await _menuPlayer.pause();
      } catch (error, stackTrace) {
        _logAudioError(
          'Pausing music for lifecycle/state change',
          error,
          stackTrace,
        );
      }
      return;
    }

    if (!musicEnabled) {
      if (!_musicDisabledLogged) {
        debugPrint(
          '[Orbit Dash audio] Music is disabled by the saved audio setting.',
        );
        _musicDisabledLogged = true;
      }
      await _fadeTo(0, token);
      return;
    }
    _musicDisabledLogged = false;

    if (_gameState != AudioRunState.menu) {
      if (_menuStarted || _menuVolume > 0) await _fadeTo(0, token);
      return;
    }

    await _startLoop(_menuPlayer, menuMusicAsset);
    if (token != _fadeToken) return;
    await _fadeTo(0.38, token);
  }

  Future<void> _startLoop(AudioPlayer player, String asset) async {
    try {
      if (!_menuStarted) {
        debugPrint('[Orbit Dash audio] Starting menu music asset: $asset');
        _menuStarted = true;
        await player.play(AssetSource(asset), volume: 0);
      } else {
        debugPrint('[Orbit Dash audio] Resuming menu music asset: $asset');
        await player.resume();
      }
    } catch (error, stackTrace) {
      _logAudioError('Starting menu music asset $asset', error, stackTrace);
      _menuStarted = false;
    }
  }

  Future<void> _fadeTo(double menuTarget, int token) async {
    const steps = 8;
    const interval = Duration(milliseconds: 45);
    final menuStart = _menuVolume;
    var step = 0;
    final completer = Completer<void>();
    _fadeTimer = Timer.periodic(interval, (timer) async {
      if (token != _fadeToken) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      step++;
      final progress = (step / steps).clamp(0.0, 1.0);
      _menuVolume = menuStart + (menuTarget - menuStart) * progress;
      unawaited(_setPlayerVolume(_menuPlayer, _menuVolume));
      if (step >= steps) {
        timer.cancel();
        await _stopSilentPlayer(target: menuTarget);
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> _setPlayerVolume(AudioPlayer player, double volume) async {
    try {
      await player.setVolume(volume);
    } catch (error, stackTrace) {
      _logAudioError('Setting music volume', error, stackTrace);
    }
  }

  Future<void> _stopSilentPlayer({required double target}) async {
    if (target != 0) return;
    try {
      await _menuPlayer.stop();
    } catch (error, stackTrace) {
      _logAudioError('Stopping silent music player', error, stackTrace);
    }
    _menuStarted = false;
    _menuVolume = 0;
  }

  void _logAudioError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    final key = '$operation: $error';
    if (!_reportedAudioErrors.add(key)) return;
    debugPrint('[Orbit Dash audio] $operation failed: $error\n$stackTrace');
  }

  @override
  Future<void> shutdown() async {
    _fadeTimer?.cancel();
    _fadeToken++;
    settings.removeListener(_settingsChanged);
    await Future.wait([
      _menuPlayer.dispose(),
      ..._effectPlayers.map((player) => player.dispose()),
    ]);
    settings.dispose();
    super.dispose();
  }
}
