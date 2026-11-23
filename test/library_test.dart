import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wheretosee/library.dart';
import 'package:wheretosee/my_list.dart';
import 'package:wheretosee/tmdb.dart';

MediaItem _movie(int id) => MediaItem(
      id: id,
      mediaType: 'movie',
      title: 'Peli $id',
      originalTitle: '',
      year: '1972',
      posterPath: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Library.instance.load();
  });

  test('pendiente y vista se excluyen entre sí', () async {
    final lib = Library.instance;
    final m = _movie(238);
    await lib.togglePending(m);
    expect(lib.isPending(m), isTrue);
    await lib.toggleWatched(m);
    expect(lib.isWatched(m), isTrue);
    expect(lib.isPending(m), isFalse);
    await lib.toggleWatched(m);
    expect(lib.isWatched(m), isFalse);
  });

  test('se guarda y se vuelve a cargar', () async {
    final lib = Library.instance;
    await lib.togglePending(_movie(1));
    await lib.setProvider(8, true);
    await lib.load();
    expect(lib.pending.single.id, 1);
    expect(lib.hasProvider(8), isTrue);
  });

  test('includedIn junta suscripción, gratis y anuncios sin repetir', () {
    final netflix = Provider(id: 8, name: 'Netflix', logoPath: null);
    final rtve = Provider(id: 541, name: 'RTVE', logoPath: null);
    final apple = Provider(id: 2, name: 'Apple TV', logoPath: null);
    final Availability a = {
      'ES': CountryAvailability(link: '', byCategory: {
        'flatrate': [netflix],
        'free': [rtve, netflix],
        'rent': [apple],
      }),
    };
    expect(includedIn(a, 'ES').map((p) => p.id), [8, 541]);
    expect(includedIn(a, 'FR'), isEmpty);
  });
}
