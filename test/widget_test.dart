import 'package:donde_ver/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bandera de España', () {
    expect(flagOf('ES'), '🇪🇸');
  });

  test('orden sin tildes', () {
    expect(sortKey('Árbol'), 'arbol');
  });
}
