import 'library.dart';
import 'my_list.dart';
import 'tmdb.dart';

/// Lo que el usuario pide. Todos los criterios se pueden combinar.
class RecQuery {
  RecQuery({
    required this.type,
    this.genres = const {},
    this.similar,
    this.person,
    this.asDirector = false,
    this.onlyMine = false,
  });

  final String type; // 'movie' | 'tv'
  final Set<int> genres;
  final MediaItem? similar;
  final Person? person;
  final bool asDirector;
  final bool onlyMine;

  bool get isEmpty => genres.isEmpty && similar == null && person == null;
}

class Recommendation {
  Recommendation(this.candidate, this.matchedGenres);
  final Candidate candidate;

  /// Géneros pedidos que tiene esta película o serie.
  final List<int> matchedGenres;
}

class RecResult {
  RecResult(this.items, this.requiredGenres);
  final List<Recommendation> items;
  final Set<int> requiredGenres;
}

/// Orden: primero las que tienen más géneros de los pedidos (todos > alguno),
/// y a igualdad, la de mejor puntuación.
List<Recommendation> rankCandidates(
  Iterable<Candidate> candidates, {
  required Set<int> requiredGenres,
  required int minVotes,
  required bool Function(MediaItem) exclude,
}) {
  final list = candidates
      .where((c) => c.votes >= minVotes && !exclude(c.item))
      .map((c) => Recommendation(c, c.genreIds.where(requiredGenres.contains).toList()))
      .where((r) => requiredGenres.isEmpty || r.matchedGenres.isNotEmpty)
      .toList()
    ..sort((a, b) {
      final m = b.matchedGenres.length.compareTo(a.matchedGenres.length);
      return m != 0 ? m : b.candidate.vote.compareTo(a.candidate.vote);
    });
  return list;
}

Future<RecResult> recommend(
  RecQuery q, {
  required bool Function(MediaItem) isWatched,
  required String region,
  required Set<int> myProviders,
  int limit = 10,
}) async {
  final tmdb = Tmdb.instance;
  final required = <int>{...q.genres};
  final sim = q.similar;
  if (sim != null) required.addAll(await tmdb.genresOf(sim));
  final onlyMine = q.onlyMine && myProviders.isNotEmpty;

  bool exclude(MediaItem m) => isWatched(m) || (sim != null && keyOf(m) == keyOf(sim));

  final byKey = <String, Candidate>{};
  void addAll(Iterable<Candidate> cs) {
    for (final c in cs) {
      byKey.putIfAbsent(keyOf(c.item), () => c);
    }
  }

  final person = q.person;
  List<Recommendation> ranked;

  if (person != null) {
    // Filmografía de la persona, filtrada por géneros si los hay.
    addAll(await tmdb.personCredits(person, q.type, asDirector: q.asDirector));
    ranked = rankCandidates(byKey.values, requiredGenres: required, minVotes: 30, exclude: exclude);
    if (ranked.isEmpty) {
      ranked = rankCandidates(byKey.values, requiredGenres: required, minVotes: 1, exclude: exclude);
    }
    if (onlyMine) {
      final kept = <Recommendation>[];
      var checked = 0;
      for (final r in ranked) {
        if (kept.length >= limit || checked >= 40) break;
        checked++;
        try {
          final a = await tmdb.availability(r.candidate.item);
          if (includedIn(a, region).any((p) => myProviders.contains(p.id))) kept.add(r);
        } catch (_) {}
      }
      ranked = kept;
    }
  } else {
    // Búsqueda por filtros en TMDB, ordenada por puntuación con un mínimo de votos
    // (si no, ganarían películas desconocidas con un 10 de 3 votos).
    final minVotes = q.type == 'tv' ? 150 : 300;
    Map<String, String> params(String withGenres, int page) => {
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '$minVotes',
          'page': '$page',
          if (withGenres.isNotEmpty) 'with_genres': withGenres,
          if (onlyMine) 'watch_region': region,
          if (onlyMine) 'with_watch_providers': myProviders.join('|'),
          if (onlyMine) 'with_watch_monetization_types': 'flatrate|free|ads',
        };
    // 1) Con TODOS los géneros pedidos.
    for (var page = 1; page <= 3; page++) {
      addAll(await tmdb.discover(q.type, params(required.join(','), page)));
    }
    // 2) Con AL MENOS UNO, para completar (quedan detrás al ordenar).
    if (required.length > 1) {
      for (var page = 1; page <= 3; page++) {
        addAll(await tmdb.discover(q.type, params(required.join('|'), page)));
      }
    }
    ranked = rankCandidates(byKey.values, requiredGenres: required, minVotes: minVotes, exclude: exclude);
  }

  return RecResult(ranked.take(limit).toList(), required);
}
