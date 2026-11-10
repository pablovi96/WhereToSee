import 'package:flutter_test/flutter_test.dart';
import 'package:wheretosee/open_in.dart';

void main() {
  test('Netflix abre la búsqueda del título', () {
    final t = openTargetFor('Netflix', 'El padrino')!;
    expect(t.searches, isTrue);
    expect(t.uri.toString(), 'https://www.netflix.com/search?q=El+padrino');
  });

  test('Amazon Prime Video busca en primevideo', () {
    expect(openTargetFor('Amazon Prime Video', 'X')!.uri.host, 'www.primevideo.com');
  });

  test('Filmin abre la plataforma sin búsqueda', () {
    expect(openTargetFor('Filmin', 'X')!.searches, isFalse);
  });

  test('plataforma desconocida no da botón', () {
    expect(openTargetFor('Plataforma Rara', 'X'), isNull);
  });
}
