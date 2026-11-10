import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// A dónde llevar al usuario para una plataforma concreta.
class OpenTarget {
  const OpenTarget(this.uri, {required this.searches});
  final Uri uri;

  /// true: el enlace ya abre la búsqueda del título.
  /// false: solo abre la plataforma; copiamos el título para que lo pegue.
  final bool searches;
}

/// Devuelve el destino para [providerName] buscando [title], o null si no lo conocemos.
OpenTarget? openTargetFor(String providerName, String title) {
  final n = providerName.toLowerCase();
  final q = Uri.encodeQueryComponent(title);

  OpenTarget search(String url) => OpenTarget(Uri.parse(url), searches: true);
  OpenTarget home(String url) => OpenTarget(Uri.parse(url), searches: false);

  if (n.contains('netflix')) return search('https://www.netflix.com/search?q=$q');
  if (n.contains('prime video') || n.contains('amazon')) {
    return search('https://www.primevideo.com/search?phrase=$q');
  }
  if (n.contains('disney')) return search('https://www.disneyplus.com/search?q=$q');
  if (n.contains('apple tv')) return search('https://tv.apple.com/search?term=$q');
  if (n.contains('youtube')) return search('https://www.youtube.com/results?search_query=$q');
  if (n.contains('google play')) return search('https://play.google.com/store/search?q=$q&c=movies');

  if (n.contains('hbo') || n == 'max') return home('https://play.hbomax.com');
  if (n.contains('filmin')) return home('https://www.filmin.es');
  if (n.contains('movistar')) return home('https://ver.movistarplus.es');
  if (n.contains('skyshowtime')) return home('https://www.skyshowtime.com');
  if (n.contains('rakuten')) return home('https://www.rakuten.tv');
  if (n.contains('atresplayer')) return home('https://www.atresplayer.com');
  if (n.contains('rtve')) return home('https://www.rtve.es/play/');
  return null;
}

/// Abre la app de la plataforma si está instalada; si no, su web.
Future<void> openInProvider(BuildContext context, String providerName, String title) async {
  final target = openTargetFor(providerName, title);
  if (target == null) return;
  final messenger = ScaffoldMessenger.of(context);

  if (!target.searches) {
    await Clipboard.setData(ClipboardData(text: title));
    messenger.showSnackBar(SnackBar(
      content: Text('Título copiado. Pégalo en el buscador de $providerName.'),
    ));
  }

  var ok = false;
  try {
    ok = await launchUrl(target.uri, mode: LaunchMode.externalNonBrowserApplication);
  } catch (_) {}
  if (!ok) {
    try {
      ok = await launchUrl(target.uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir $providerName.')));
  }
}
