import 'dart:ui' show PlatformDispatcher;

/// Idioma de la app: castellano si el móvil está en español; si no, inglés.
final bool isSpanish = PlatformDispatcher.instance.locale.languageCode == 'es';

/// Devuelve [es] o [en] según el idioma del móvil.
String tr(String es, String en) => isSpanish ? es : en;

/// Idioma en el que se piden a TMDB títulos, géneros y nombres de países.
String get tmdbLanguage => isSpanish ? 'es-ES' : 'en-US';

/// País del móvil (p. ej. 'US'), para usarlo como país por defecto.
String? get deviceCountry {
  final c = PlatformDispatcher.instance.locale.countryCode;
  return (c != null && c.length == 2) ? c.toUpperCase() : null;
}
