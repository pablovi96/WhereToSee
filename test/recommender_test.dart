import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosee/recommender.dart';
import 'package:wheretosee/tmdb.dart';

Candidate _c(int id, List<int> genres, double vote, {int votes = 1000}) => Candidate(
      item: MediaItem(id: id, mediaType: 'movie', title: 'P$id', originalTitle: '', year: '', posterPath: null),
      genreIds: genres,
      vote: vote,
      votes: votes,
    );

void main() {
  const drama = 18, crime = 80, comedy = 35;

  test('primero las que tienen todos los géneros, luego por puntuación', () {
    final r = rankCandidates(
      [
        _c(1, [drama], 9.0),
        _c(2, [drama, crime], 8.0),
        _c(3, [crime, drama], 8.5),
        _c(4, [comedy], 9.9),
      ],
      requiredGenres: {drama, crime},
      minVotes: 300,
      exclude: (_) => false,
    );
    expect(r.map((x) => x.candidate.item.id), [3, 2, 1]); // la 4 no comparte ninguno
  });

  test('descarta las vistas y las de pocos votos', () {
    final r = rankCandidates(
      [_c(1, [drama], 9.5), _c(2, [drama], 9.9, votes: 3), _c(3, [drama], 7.0)],
      requiredGenres: {drama},
      minVotes: 300,
      exclude: (m) => m.id == 1,
    );
    expect(r.map((x) => x.candidate.item.id), [3]);
  });

  test('sin géneros pedidos (solo persona) ordena por puntuación', () {
    final r = rankCandidates(
      [_c(1, [comedy], 6.0), _c(2, [drama], 8.0)],
      requiredGenres: {},
      minVotes: 30,
      exclude: (_) => false,
    );
    expect(r.map((x) => x.candidate.item.id), [2, 1]);
  });
}
