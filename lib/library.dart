import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tmdb.dart';

/// Película o serie guardada en una lista del usuario.
class SavedItem {
  SavedItem({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.year,
    required this.posterPath,
    required this.addedAt,
  });

  final int id;
  final String mediaType;
  final String title;
  final String year;
  final String? posterPath;
  final DateTime addedAt;

  String get key => '$mediaType:$id';

  MediaItem toMediaItem() => MediaItem(
        id: id,
        mediaType: mediaType,
        title: title,
        originalTitle: '',
        year: year,
        posterPath: posterPath,
      );

  factory SavedItem.fromMedia(MediaItem m) => SavedItem(
        id: m.id,
        mediaType: m.mediaType,
        title: m.title,
        year: m.year,
        posterPath: m.posterPath,
        addedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': mediaType,
        'title': title,
        'year': year,
        'poster': posterPath,
        'added': addedAt.millisecondsSinceEpoch,
      };

  factory SavedItem.fromJson(Map<String, dynamic> j) => SavedItem(
        id: j['id'] as int,
        mediaType: j['type'] as String,
        title: (j['title'] ?? '') as String,
        year: (j['year'] ?? '') as String,
        posterPath: j['poster'] as String?,
        addedAt: DateTime.fromMillisecondsSinceEpoch((j['added'] ?? 0) as int),
      );
}

String keyOf(MediaItem m) => '${m.mediaType}:${m.id}';

/// Todo lo del usuario, guardado solo en el teléfono (sin cuentas ni servidor).
/// Android incluye estos datos en la copia de seguridad automática de Google.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  static const _kWatched = 'lib_watched';
  static const _kPending = 'lib_pending';
  static const _kProviders = 'lib_my_providers';

  final Map<String, SavedItem> _watched = {};
  final Map<String, SavedItem> _pending = {};
  final Set<int> _myProviders = {};

  /// Más recientes primero.
  List<SavedItem> get watched => _sorted(_watched);
  List<SavedItem> get pending => _sorted(_pending);
  Set<int> get myProviders => Set.unmodifiable(_myProviders);

  bool isWatched(MediaItem m) => _watched.containsKey(keyOf(m));
  bool isPending(MediaItem m) => _pending.containsKey(keyOf(m));
  bool hasProvider(int id) => _myProviders.contains(id);

  List<SavedItem> _sorted(Map<String, SavedItem> m) =>
      m.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _readList(prefs.getString(_kWatched), _watched);
      _readList(prefs.getString(_kPending), _pending);
      final p = prefs.getStringList(_kProviders) ?? const <String>[];
      _myProviders
        ..clear()
        ..addAll(p.map(int.tryParse).whereType<int>());
      notifyListeners();
    } catch (_) {}
  }

  void _readList(String? raw, Map<String, SavedItem> into) {
    into.clear();
    if (raw == null) return;
    try {
      for (final e in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final item = SavedItem.fromJson(e);
        into[item.key] = item;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kWatched, jsonEncode(_watched.values.map((e) => e.toJson()).toList()));
      await prefs.setString(_kPending, jsonEncode(_pending.values.map((e) => e.toJson()).toList()));
      await prefs.setStringList(_kProviders, _myProviders.map((e) => '$e').toList());
    } catch (_) {}
  }

  /// Marcar como vista la quita de pendientes.
  Future<void> toggleWatched(MediaItem m) {
    final k = keyOf(m);
    if (_watched.remove(k) == null) {
      _watched[k] = SavedItem.fromMedia(m);
      _pending.remove(k);
    }
    return _save();
  }

  /// Añadir a pendientes la quita de vistas.
  Future<void> togglePending(MediaItem m) {
    final k = keyOf(m);
    if (_pending.remove(k) == null) {
      _pending[k] = SavedItem.fromMedia(m);
      _watched.remove(k);
    }
    return _save();
  }

  Future<void> remove(SavedItem item) {
    _watched.remove(item.key);
    _pending.remove(item.key);
    return _save();
  }

  Future<void> setProvider(int id, bool mine) {
    if (mine) {
      _myProviders.add(id);
    } else {
      _myProviders.remove(id);
    }
    return _save();
  }
}
