import 'dart:convert';

import 'package:http/http.dart' as http;

/// Clave de TMDB inyectada al compilar: --dart-define=TMDB_KEY=...
/// Vale la "API Key" (v3, corta) o el "API Read Access Token" (v4, largo).
const String tmdbKey = String.fromEnvironment('TMDB_KEY');
const String imgBase = 'https://image.tmdb.org/t/p/';

/// Categorías de disponibilidad que devuelve TMDB/JustWatch, en orden.
const List<(String, String)> categories = [
  ('flatrate', 'Suscripción'),
  ('free', 'Gratis'),
  ('ads', 'Con anuncios'),
  ('rent', 'Alquiler'),
  ('buy', 'Compra'),
];

class TmdbException implements Exception {
  TmdbException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MediaItem {
  MediaItem({
    required this.id,
    required this.mediaType,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.posterPath,
  });

  final int id;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String originalTitle;
  final String year;
  final String? posterPath;

  bool get isTv => mediaType == 'tv';

  factory MediaItem.fromJson(Map<String, dynamic> j) {
    final date = (j['release_date'] ?? j['first_air_date'] ?? '') as String;
    return MediaItem(
      id: j['id'] as int,
      mediaType: j['media_type'] as String,
      title: (j['title'] ?? j['name'] ?? '') as String,
      originalTitle: (j['original_title'] ?? j['original_name'] ?? '') as String,
      year: date.length >= 4 ? date.substring(0, 4) : '',
      posterPath: j['poster_path'] as String?,
    );
  }
}

class Provider {
  Provider({required this.id, required this.name, required this.logoPath});
  final int id;
  final String name;
  final String? logoPath;

  factory Provider.fromJson(Map<String, dynamic> j) => Provider(
        id: j['provider_id'] as int,
        name: (j['provider_name'] ?? '') as String,
        logoPath: j['logo_path'] as String?,
      );
}

class CountryAvailability {
  CountryAvailability({required this.link, required this.byCategory});
  final String link;
  final Map<String, List<Provider>> byCategory;
}

/// País (código ISO) -> disponibilidad en ese país.
typedef Availability = Map<String, CountryAvailability>;

class Tmdb {
  Tmdb._();
  static final Tmdb instance = Tmdb._();
  final http.Client _client = http.Client();

  Future<dynamic> _get(String path, [Map<String, String> query = const {}]) async {
    if (tmdbKey.isEmpty) {
      throw TmdbException('Esta versión se compiló sin clave de TMDB.');
    }
    final isToken = tmdbKey.length > 40;
    final params = <String, String>{...query};
    if (!isToken) params['api_key'] = tmdbKey;
    final uri = Uri.https('api.themoviedb.org', '/3$path', params);
    final headers = <String, String>{'accept': 'application/json'};
    if (isToken) headers['Authorization'] = 'Bearer $tmdbKey';

    final http.Response r;
    try {
      r = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw TmdbException('No hay conexión. Revisa tu internet e inténtalo de nuevo.');
    }
    if (r.statusCode == 401) throw TmdbException('La clave de TMDB no es válida.');
    if (r.statusCode == 429) throw TmdbException('Demasiadas búsquedas seguidas. Espera un momento.');
    if (r.statusCode != 200) throw TmdbException('Error de TMDB (${r.statusCode}).');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<List<MediaItem>> search(String query) async {
    final data = await _get('/search/multi', {
      'query': query,
      'language': 'es-ES',
      'include_adult': 'false',
    }) as Map<String, dynamic>;
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return results
        .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
        .map(MediaItem.fromJson)
        .toList();
  }

  Future<Availability> availability(MediaItem item) async {
    final data = await _get('/${item.mediaType}/${item.id}/watch/providers') as Map<String, dynamic>;
    final results = (data['results'] as Map<String, dynamic>?) ?? {};
    final out = <String, CountryAvailability>{};
    results.forEach((cc, value) {
      final m = value as Map<String, dynamic>;
      final byCat = <String, List<Provider>>{};
      for (final (cat, _) in categories) {
        final list = m[cat];
        if (list is List && list.isNotEmpty) {
          byCat[cat] = list.cast<Map<String, dynamic>>().map(Provider.fromJson).toList();
        }
      }
      out[cc] = CountryAvailability(link: (m['link'] ?? '') as String, byCategory: byCat);
    });
    return out;
  }

  /// Código ISO -> nombre del país en español.
  Future<Map<String, String>> regions() async {
    final data = await _get('/watch/providers/regions', {'language': 'es-ES'}) as Map<String, dynamic>;
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    return {
      for (final r in results)
        (r['iso_3166_1'] as String): ((r['native_name'] ?? r['english_name'] ?? r['iso_3166_1']) as String),
    };
  }
}
