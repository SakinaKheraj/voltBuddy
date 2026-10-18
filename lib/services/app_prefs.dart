import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent key-value settings: participant ID, install ID and the
/// user's pet / persona choices (which previously reset on every launch).
class AppPrefs {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  static const _kParticipantId = 'vb_participant_id';
  static const _kInstallId = 'vb_install_id';
  static const _kSpecies = 'vb_species';
  static const _kPersona = 'vb_persona';

  SharedPreferences? _prefs;
  final Map<String, String> _memoryFallback = {};

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('VoltBuddy: SharedPreferences unavailable, using memory: $e');
    }
  }

  String? _get(String key) => _prefs?.getString(key) ?? _memoryFallback[key];

  void _set(String key, String value) {
    _memoryFallback[key] = value;
    _prefs?.setString(key, value).catchError((Object e) {
      debugPrint('VoltBuddy: Failed to persist $key: $e');
      return false;
    });
  }

  String? get participantId => _get(_kParticipantId);
  set participantId(String? value) {
    if (value != null) _set(_kParticipantId, value);
  }

  /// Random, non-identifying ID created on first launch of this version.
  String get installId {
    final existing = _get(_kInstallId);
    if (existing != null) return existing;
    final rng = math.Random.secure();
    final id = List.generate(8, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _set(_kInstallId, id);
    return id;
  }

  String? get species => _get(_kSpecies);
  set species(String? value) {
    if (value != null) _set(_kSpecies, value);
  }

  String? get persona => _get(_kPersona);
  set persona(String? value) {
    if (value != null) _set(_kPersona, value);
  }
}
